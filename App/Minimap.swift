import AppKit
import TypoKit

extension SettingsKey {
    static let minimap = "showMinimap"
}

/// The View menu's Minimap toggle, observable so the menu's checkmark follows it; stored in UserDefaults.
@MainActor @Observable final class MinimapSetting {
    static let shared = MinimapSetting()
    var isOn = UserDefaults.standard.object(forKey: SettingsKey.minimap) as? Bool ?? true {
        didSet { UserDefaults.standard.set(isOn, forKey: SettingsKey.minimap) }
    }
}

/// The minimap at the right edge of an editor pane (as in Xcode): the whole document scaled down, one 2 pt bar per
/// shown line, the visible region as a band and the caret's line filled. It draws a `MinimapModel` built off the main actor
/// after each edit, so neither drawing nor scrolling lays out text.
final class MinimapView: NSView {
    private weak var textView: NSTextView?
    private weak var scroll: AnchoredScrollView?
    private weak var editor: EditorView.Coordinator?
    /// Off in Focus Mode or by the View menu; the scroll view's `tile` leaves it no room then.
    var shown = true

    private var model = MinimapModel()
    private var palette: [NSColor] = []
    private weak var builtStorage: NSTextStorage?
    private var builtFolds = -1
    private var build: Task<Void, Never>?
    /// The editor's visible lines, in shown lines (see `MinimapGeometry`).
    private var top = 0.0, visible = 1.0
    private var grab: CGFloat?                       // the pointer's distance below the band's top while dragging it
    private var hoverY: CGFloat?
    var diagnostics: [DecorationView.Item] = [] { didSet { if diagnostics != oldValue { needsDisplay = true } } }

    private static let lineHeight: CGFloat = 4
    private static let columnWidth: CGFloat = 1
    private static let inset: CGFloat = 8
    private static let barHeight: CGFloat = 2

    /// Puts a minimap into `scroll` for `textView`.
    static func attach(to scroll: AnchoredScrollView, textView: NSTextView, editor: EditorView.Coordinator) {
        let map = MinimapView(frame: .zero)
        map.textView = textView
        map.scroll = scroll
        map.editor = editor
        scroll.addSubview(map, positioned: .above, relativeTo: scroll.contentView)
        scroll.minimap = map
        let nc = NotificationCenter.default
        scroll.contentView.postsBoundsChangedNotifications = true
        nc.addObserver(map, selector: #selector(updateBand), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        nc.addObserver(map, selector: #selector(updateBand), name: NSView.frameDidChangeNotification, object: scroll.contentView)
        // A rewrap changes the text view's height without an edit.
        nc.addObserver(map, selector: #selector(updateBand), name: NSView.frameDidChangeNotification, object: textView)
        nc.addObserver(map, selector: #selector(updateBand), name: NSTextView.didChangeSelectionNotification, object: textView)
        nc.addObserver(map, selector: #selector(storageEdited), name: NSTextStorage.didProcessEditingNotification, object: nil)
        let folded = editor.folds.onChange
        editor.folds.onChange = { [weak map] in folded?(); map?.foldsChanged() }
        map.clipsToBounds = true                     // long lines and labels near the edges stay inside
        map.setAccessibilityElement(true)
        map.setAccessibilityRole(.group)
        map.setAccessibilityLabel("Minimap")
    }

    override var isFlipped: Bool { true }

    private var geometry: MinimapGeometry {
        MinimapGeometry(lineCount: model.lines.count, lineHeight: Self.lineHeight, viewHeight: bounds.height)
    }

    /// Narrower in a narrow pane, none below 360 pt.
    static func width(for paneWidth: CGFloat) -> CGFloat { paneWidth < 360 ? 0 : min(140, floor(paneWidth * 0.3)) }

    /// Called from the scroll view's `tile`: takes its width off the clip view's right side and moves the scrollers.
    func place(in scroll: NSScrollView) {
        let w = shown ? Self.width(for: scroll.bounds.width) : 0
        isHidden = w == 0
        guard w > 0 else { return }
        let clip = scroll.contentView
        clip.frame.size.width -= w
        // As in Xcode the vertical scroller stays at the window edge, right of the map.
        if let h = scroll.horizontalScroller { h.frame.size.width -= w }
        frame = NSRect(x: clip.frame.maxX, y: clip.frame.minY, width: w, height: clip.frame.height)
    }

    // MARK: Model

    @objc private func storageEdited(_ n: Notification) {
        guard let s = n.object as? NSTextStorage, s === editor?.buffer?.storage else { return }
        rebuild(after: .milliseconds(150))
    }

    /// After every fold or unfold the editor applies (FoldController.onChange).
    func foldsChanged() {
        if let b = editor?.buffer, b.foldRevision != builtFolds { rebuild(after: .zero) }
    }

    /// Rebuilds now for another file; the app calls this on every update of the editor. A theme change recolours
    /// the storage, whose edit notification rebuilds.
    func refresh() {
        if editor?.buffer?.storage !== builtStorage { rebuild(after: .zero) }
    }

    /// Debounced: snapshots text, colours, headings and folds on the main actor, builds the model off it.
    private func rebuild(after delay: Duration) {
        build?.cancel()
        build = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, let buffer = self.editor?.buffer else { return }
            let storage = buffer.storage
            var palette: [NSColor] = [], index: [NSColor: Int] = [:]
            var runs: [MinimapModel.ColorRun] = []
            storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
                let color = value as? NSColor ?? .textColor
                let i = index[color] ?? { palette.append(color); index[color] = palette.count - 1; return palette.count - 1 }()
                runs.append(.init(range: range, color: i))
            }
            let text = storage.string, colors = runs, headings = buffer.headingLines, hidden = buffer.hiddenRanges.map(\.range)
            let folds = buffer.foldRevision
            let model = await Task.detached(priority: .userInitiated) {
                MinimapModel.build(text: text, runs: colors, headings: headings, hidden: hidden)
            }.value
            guard !Task.isCancelled, self.editor?.buffer === buffer else { return }
            self.model = model
            self.palette = (palette.isEmpty ? [.textColor] : palette).map { $0.withAlphaComponent(0.45) }
            self.builtStorage = storage
            self.builtFolds = folds
            self.updateBand()
        }
    }

    // MARK: Band

    /// The editor's visible lines from the layout fragments at the clip's top and bottom edges (already laid out).
    @objc private func updateBand() {
        guard !isHidden, let tv = textView, let scroll, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage,
              !model.lines.isEmpty else { return }
        let origin = tv.textContainerOrigin
        func line(atY y: CGFloat) -> Double? {
            guard let f = tlm.textLayoutFragment(for: CGPoint(x: 0, y: y - origin.y)) else { return nil }
            let frame = f.layoutFragmentFrame
            let within = frame.height > 0 ? min(max((y - origin.y - frame.minY) / frame.height, 0), 1) : 0
            return Double(model.lineIndex(of: tcs.offset(of: f.rangeInElement.location))) + Double(within)
        }
        let clip = scroll.contentView.bounds
        let t = line(atY: clip.minY) ?? Double(model.lines.count)
        let b = line(atY: clip.maxY) ?? Double(model.lines.count)
        top = min(t, Double(model.lines.count))
        visible = max(b - top, 1)
        let first = model.lines[min(Int(top), model.lines.count - 1)].number + 1
        let last = model.lines[min(max(Int(b.rounded(.up)) - 1, 0), model.lines.count - 1)].number + 1
        setAccessibilityValue("Lines \(first) to \(last)")
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let colors = Highlighter.style.colors
        (textView?.backgroundColor ?? colors.background).setFill()
        bounds.fill()
        let g = geometry, h = Self.lineHeight
        let offset = g.offset(top: top, visible: visible)
        let band = g.band(top: top, visible: visible)
        colors.text.withAlphaComponent(grab == nil ? 0.08 : 0.14).setFill()
        NSRect(x: 0, y: band.y, width: bounds.width, height: band.height).fill()

        if let tv = textView, !model.lines.isEmpty {   // the caret's line
            let y = CGFloat(model.lineIndex(of: tv.selectedRange().location)) * h - offset
            colors.text.withAlphaComponent(0.05).setFill()
            NSRect(x: 0, y: y, width: bounds.width, height: h).fill()
        }
        let first = max(0, Int(offset / h)), last = min(model.lines.count, Int((offset + bounds.height) / h) + 1)
        if first < last {
            for i in first..<last {
                let y = CGFloat(i) * h - offset
                for run in model.lines[i].runs {
                    palette[min(run.color, palette.count - 1)].setFill()
                    NSRect(x: Self.inset + CGFloat(run.column) * Self.columnWidth, y: y, width: CGFloat(run.length) * Self.columnWidth, height: Self.barHeight).fill()
                }
            }
        }
        drawDiagnostics(offset: offset)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        drawHover(offset: offset)
    }

    private func drawDiagnostics(offset: CGFloat) {
        for warnings in [true, false] {                 // errors draw over warnings
            (warnings ? NSColor.systemOrange : NSColor.systemRed).setFill()
            for d in diagnostics where d.error != warnings {
                let y = CGFloat(model.lineIndex(of: d.range.location)) * Self.lineHeight - offset
                guard y > -4, y < bounds.height else { continue }
                NSRect(x: bounds.width - 4, y: y - 1, width: 3, height: 4).fill()
            }
        }
    }

    /// The heading of the section under the pointer, in a small label above it.
    private func drawHover(offset: CGFloat) {
        guard let y = hoverY, grab == nil,
              let heading = model.heading(containing: Int(geometry.line(atY: y, top: top, visible: visible))) else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
        let size = (heading.title as NSString).size(withAttributes: attrs)
        let width = min(size.width + 10, bounds.width - 6)
        let rect = NSRect(x: bounds.width - width - 3, y: max(2, y - size.height - 10), width: width, height: size.height + 4)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        (heading.title as NSString).draw(in: rect.insetBy(dx: 5, dy: 2), withAttributes: attrs)
    }

    // MARK: Mouse (the wheel passes on to the scroll view by the responder chain)

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        let band = geometry.band(top: top, visible: visible)
        if y < band.y || y > band.y + band.height {
            scrollEditor(toTop: geometry.top(centering: y, top: top, visible: visible))
            grab = visible * Self.lineHeight / 2         // a click then drag keeps moving the band from its middle
        } else {
            grab = y - band.y
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let grab else { return }
        let y = convert(event.locationInWindow, from: nil).y
        scrollEditor(toTop: geometry.top(forBandY: y - grab, visible: visible))
    }

    override func mouseUp(with event: NSEvent) {
        grab = nil
        needsDisplay = true
    }

    private func scrollEditor(toTop t: Double) {
        guard !model.lines.isEmpty, let editor, let scroll else { return }
        let i = min(max(Int(t), 0), model.lines.count - 1)
        editor.restore((index: model.lines[i].offset, offset: 0), in: scroll)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        hoverY = convert(event.locationInWindow, from: nil).y
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverY = nil
        needsDisplay = true
    }
}

extension EditorView.Coordinator {
    /// Each editor update: shows or hides the minimap (toggle, Focus Mode), passes the diagnostics and repaints.
    func updateMinimap(_ scroll: NSScrollView) {
        guard let scroll = scroll as? AnchoredScrollView, let map = scroll.minimap else { return }
        let shown = MinimapSetting.shared.isOn && layout?.focus != true
        if map.shown != shown {
            scroll.holdAnchor()                           // the text rewraps to the new width
            map.shown = shown
            scroll.tile()
            scroll.settleAnchor()
        }
        map.diagnostics = decor?.items ?? []
        map.refresh()
    }
}
