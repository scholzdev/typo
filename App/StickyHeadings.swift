import AppKit
import TypoKit

extension SettingsKey {
    static let stickyScroll = "stickyScroll"
}

/// Sticky Scroll: the headings of the sections the viewport's top line lies in, pinned over the top of the text,
/// outermost first. A view of the scroll view (not of the text view), so it stays put while the text scrolls under it.
/// A click jumps to the heading.
final class StickyHeadingsView: NSView {
    weak var textView: NSTextView?
    weak var editor: EditorView.Coordinator?
    var enabled = true { didSet { if enabled != oldValue { refresh() } } }
    private var rows: [FoldRegion] = []
    private var hovered: Int?

    init(scrollView: NSScrollView, textView: NSTextView, editor: EditorView.Coordinator) {
        self.textView = textView
        self.editor = editor
        super.init(frame: .zero)
        isHidden = true
        let nc = NotificationCenter.default
        scrollView.contentView.postsBoundsChangedNotifications = true
        nc.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(refresh), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        // A swapped storage, a fold or a rewrap changes the document height without any edit notification.
        nc.addObserver(self, selector: #selector(refresh), name: NSView.frameDidChangeNotification, object: textView)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    private var rowHeight: CGFloat { Self.rowHeight }

    static var rowHeight: CGFloat {
        let font = Highlighter.baseFont
        return ceil(font.ascender - font.descender + font.leading) + 4
    }

    /// Recomputes the pinned headings and the frame over the clip view's top edge.
    @objc func refresh() {
        guard enabled, let tv = textView, let scroll = tv.enclosingScrollView, let buffer = editor?.buffer,
              let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return show([]) }
        let origin = tv.textContainerOrigin
        func offset(atY y: CGFloat) -> Int? {
            tlm.textLayoutFragment(for: CGPoint(x: 0, y: y - origin.y)).map { tcs.offset(of: $0.rangeInElement.location) }
        }
        let top = tv.visibleRect.minY + scroll.contentInsets.top
        guard let first = offset(atY: top) else { return show([]) }
        var pinned = buffer.stickyHeadings(top: first)
        // The line that decides is the one right under the pinned rows, not the one they cover.
        if !pinned.isEmpty, let below = offset(atY: top + CGFloat(pinned.count) * rowHeight) {
            pinned = buffer.stickyHeadings(top: below)
        }
        show(pinned)
    }

    private func show(_ pinned: [FoldRegion]) {
        let changed = pinned != rows
        rows = pinned
        isHidden = rows.isEmpty
        guard !rows.isEmpty, let scroll = textView?.enclosingScrollView else { return }
        let clip = scroll.contentView
        let local = NSRect(x: clip.bounds.minX, y: clip.bounds.minY + scroll.contentInsets.top,
                           width: clip.bounds.width, height: CGFloat(rows.count) * rowHeight)
        let target = clip.convert(local, to: scroll)
        if frame != target { frame = target; window?.invalidateCursorRects(for: self) }
        if changed { hovered = nil; needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView, let storage = editor?.buffer?.storage else { return }
        tv.backgroundColor.setFill()
        bounds.fill()
        let text = storage.string as NSString
        let x = tv.textContainerOrigin.x + (tv.textContainer?.lineFragmentPadding ?? 0) - (tv.enclosingScrollView?.contentView.bounds.minX ?? 0)
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        for (i, r) in rows.enumerated() {
            let rowRect = NSRect(x: 0, y: CGFloat(i) * rowHeight, width: bounds.width, height: rowHeight)
            if i == hovered {
                NSColor.labelColor.withAlphaComponent(0.06).setFill()
                rowRect.fill()
            }
            var line = text.lineRange(for: NSRange(location: min(r.heading, text.length), length: 0))
            while line.length > 0, [10, 13].contains(text.character(at: NSMaxRange(line) - 1)) { line.length -= 1 }
            let title = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: line))
            title.addAttribute(.paragraphStyle, value: truncating, range: NSRange(location: 0, length: title.length))
            let h = title.size().height
            title.draw(with: NSRect(x: x, y: rowRect.minY + (rowHeight - h) / 2, width: bounds.width - x - 8, height: h),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    private func row(at event: NSEvent) -> Int? {
        let i = Int(convert(event.locationInWindow, from: nil).y / rowHeight)
        return rows.indices.contains(i) ? i : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let i = row(at: event) else { return }
        editor?.jumpToStickyHeading(rows[i].heading)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { setHovered(row(at: event)) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func setHovered(_ i: Int?) {
        if hovered != i { hovered = i; needsDisplay = true }
    }
}

extension EditorView.Coordinator {
    /// A pinned heading was clicked: the caret goes to its line, which scrolls up to sit right under the headings
    /// still pinned above it (its parents), so it is not hidden behind them.
    func jumpToStickyHeading(_ heading: Int) {
        guard let tv = textView, let buffer, let scroll = tv.enclosingScrollView else { return }
        selectProgrammatically(NSRange(location: heading, length: 0), in: tv, scroll: false)
        tv.window?.makeFirstResponder(tv)
        guard let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage, let loc = tcs.location(at: heading),
              let fragment = tlm.textLayoutFragment(for: loc) else { return tv.scrollRangeToVisible(tv.selectedRange()) }
        let parents = StickyScroll.headings(buffer.headingRegions, top: heading).count
        let y = fragment.layoutFragmentFrame.minY + tv.textContainerOrigin.y - CGFloat(parents) * StickyHeadingsView.rowHeight
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(-scroll.contentInsets.top, y - scroll.contentInsets.top)))
        scroll.reflectScrolledClipView(clip)
    }
}
