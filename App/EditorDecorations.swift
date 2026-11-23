import AppKit
import QuartzCore
import SwiftUI
import TypoKit
import TypstEngine

/// The one decoration layer of the editor (DESIGN 12.1): current line, rounded selection, diagnostic tints and
/// pills, and the animated caret. It is a transparent, click-through subview over the text view that reads the
/// layout fragments at draw time, so nothing is cached that could drift. All fills are translucent because the
/// layer sits above the text (a subview cannot go below TextKit 2's text without private API); that also keeps
/// the find bar's match highlights visible through the selection.
@MainActor final class DecorationView: NSView {
    struct Item: Equatable { let range: NSRange; let error: Bool; let message: String; var fixable = false }

    weak var textView: NSTextView?
    var onPillClick: ((NSRange) -> Void)?
    /// A click on a pill whose diagnostic has quick fixes: the diagnostic's range and the pill's rect in this view.
    var onFixablePillClick: ((NSRange, NSRect) -> Void)?
    var items: [Item] = [] { didSet { if items != oldValue { needsDisplay = true } } }
    var brackets: [NSRange] = [] { didSet { if brackets != oldValue { needsDisplay = true } } }
    var animatedCaret = false { didSet { if animatedCaret != oldValue { refresh() } } }
    /// A block or underline caret is always this layer; the glide stays tied to `animatedCaret`.
    var caretShape = CaretShape.bar { didSet { if caretShape != oldValue { refresh() } } }
    private var usesCaretLayer: Bool { animatedCaret || caretShape != .bar }
    /// Folding (design/14e): lines hidden under a heading, the line a position shows on, a click on a "⋯ N lines" badge.
    var foldedLines: ((Int) -> Int?)?
    /// A folded block's closing line, drawn after its badge.
    var foldTail: ((Int) -> NSAttributedString?)?
    var shownLine: ((Int) -> Int)?
    /// Badge opacity while its fold animates (nil: not animating).
    var foldFade: ((Int) -> CGFloat?)?
    var onBadgeClick: ((Int) -> Void)?
    /// Start offsets of bookmarked lines: tinted lavender across the editor, as Xcode marks them (no gutter flag).
    var bookmarkStarts: (() -> Set<Int>)?
    /// The text range of the fold region under the pointer in the ruler: its lines get a faint band, as in Xcode.
    var hoverBand: NSRange? { didSet { if hoverBand != oldValue { needsDisplay = true } } }
    var badgeHits: [(rect: NSRect, heading: Int)] = []
    /// Color swatches after color literals: the literals to draw, and the click on one.
    var colorLiterals: (() -> [ColorLiteral])?
    var onSwatchClick: ((ColorLiteral, NSRect) -> Void)?
    private var swatchHits: [(rect: NSRect, literal: ColorLiteral)] = []
    /// Parameter names drawn in the kern gap before positional arguments; display only, they take no clicks.
    var inlayHints: (() -> [InlayHint])?
    var display = DisplayDecor() { didSet { if display != oldValue { needsDisplay = true } } }

    private var pillHits: [(rect: NSRect, range: NSRange, fixable: Bool)] = []
    private let caret = CALayer()
    /// The extra carets (App/MultiCursor.swift): one layer per caret under one container that carries the blink.
    private let extraCarets = CALayer()
    private var extraFrames: [CGRect] = []
    private var caretShown = false
    private var caretFrame = CGRect.null

    override var isFlipped: Bool { true }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: textView.bounds)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.zPosition = 1000
        caret.isHidden = true
        caret.cornerRadius = 0.75
        layer?.addSublayer(caret)
        extraCarets.isHidden = true
        layer?.addSublayer(extraCarets)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    /// Only the pills and fold badges take clicks; everything else reaches the text view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return pillHits.contains { $0.rect.contains(p) } || badgeHits.contains { $0.rect.contains(p) } || swatchHits.contains { $0.rect.contains(p) } ? self : nil
    }

    override func resetCursorRects() { for h in swatchHits { addCursorRect(h.rect, cursor: .pointingHand) } }

    override func accessibilityChildren() -> [Any]? {
        swatchHits.map { hit in
            let e = NSAccessibilityElement.element(withRole: .button, frame: window?.convertToScreen(convert(hit.rect, to: nil)) ?? hit.rect,
                                                   label: "Pick color", parent: self)
            return e
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let badge = badgeHits.first(where: { $0.rect.contains(p) }) { return onBadgeClick?(badge.heading) ?? () }
        if let swatch = swatchHits.first(where: { $0.rect.contains(p) }) { return onSwatchClick?(swatch.literal, swatch.rect) ?? () }
        if let hit = pillHits.first(where: { $0.rect.contains(p) }) {
            if hit.fixable, let onFixablePillClick { onFixablePillClick(hit.range, hit.rect) } else { onPillClick?(hit.range) }
        }
    }

    func refresh() {
        needsDisplay = true
        updateCaret()
        updateExtraCarets(restartBlink: true)
    }

    // MARK: Caret

    private func updateCaret() {
        guard let tv = textView, let window = tv.window else { return hideCaret() }
        let sel = tv.selectedRange()
        guard usesCaretLayer, sel.length == 0, window.isKeyWindow, window.firstResponder === tv else { return hideCaret() }
        let r: CGRect
        if let laidOut = caretRect(in: tv, at: sel.location) {
            r = laidOut
        } else {
            r = tv.viewRect(forCharacterRange: sel)
        }
        let frame = caretBox(r)
        caretFrame = r
        let color = Highlighter.style.colors.cursor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB) ?? color
            caret.backgroundColor = (caretShape == .block ? c.withAlphaComponent(c.alphaComponent * 0.35) : c).cgColor
        }
        CATransaction.begin()
        // Glides only for keyboard moves; a click must put the caret where the pointer is at once.
        let glide = animatedCaret && caretShown && NSApp.currentEvent?.type == .keyDown && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.setAnimationDuration(glide ? 0.08 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        caret.frame = frame
        caret.isHidden = false
        CATransaction.commit()
        caretShown = true
        // Solid right after a move, then blinking at the system's insertion point rate, like the extra carets.
        let blink = Self.blinkAnimation()
        caret.removeAnimation(forKey: "blink")
        caret.add(blink, forKey: "blink")
    }

    /// The caret as drawn in the cursor style, for the insertion rect `r`.
    func caretBox(_ r: CGRect) -> CGRect {
        // shortcut: the cell is the width of "0", so a proportional font's wide or narrow letters are not matched.
        let cell = ceil(("0" as NSString).size(withAttributes: [.font: Highlighter.baseFont]).width)
        return switch caretShape {
        case .bar: CGRect(x: r.minX - 0.75, y: r.minY, width: 1.5, height: r.height)
        case .block: CGRect(x: r.minX, y: r.minY, width: cell, height: r.height)
        case .underline: CGRect(x: r.minX, y: r.maxY - 2, width: cell, height: 2)
        }
    }

    /// Solid, then off and on again at the system's insertion point periods (`NSTextInsertionPointBlinkPeriodOn/Off`).
    static func blinkAnimation() -> CAKeyframeAnimation {
        let d = UserDefaults.standard
        let on = d.double(forKey: "NSTextInsertionPointBlinkPeriodOn"), off = d.double(forKey: "NSTextInsertionPointBlinkPeriodOff")
        let (a, b) = (on > 0 ? on : 0.5, off > 0 ? off : 0.5)
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0]
        blink.keyTimes = [0, NSNumber(value: a / (a + b))]
        blink.calculationMode = .discrete
        blink.duration = a + b
        blink.repeatCount = .infinity
        return blink
    }

    /// Carets of the extra cursors (empty selections in view), as layers. A move or an edit restarts the blink, so they
    /// stay solid while typing and blink in step with the primary caret, which restarts on the same events.
    func updateExtraCarets(restartBlink: Bool) {
        guard let tv = textView as? EditorTextView, tv.hasExtras, let window = tv.window, window.isKeyWindow, window.firstResponder === tv,
              let tcs = tv.textContentStorage, let viewport = tv.textLayoutManager?.textViewportLayoutController.viewportRange else {
            extraCarets.removeAnimation(forKey: "blink")
            extraCarets.isHidden = true
            extraFrames = []
            return
        }
        let length = tcs.textStorage?.length ?? 0
        let lo = tcs.offset(of: viewport.location), hi = tcs.offset(of: viewport.endLocation)
        let frames = tv.multi.extras.filter { $0.range.length == 0 && $0.head <= length && $0.head >= lo && $0.head <= hi }
            .compactMap { Self.insertionRect(in: tv, at: $0.head).map(caretBox) }
        guard restartBlink || frames != extraFrames else { return }
        extraFrames = frames
        let color = Highlighter.style.colors.cursor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var layers = extraCarets.sublayers ?? []
        while layers.count < frames.count { let l = CALayer(); l.cornerRadius = 0.75; extraCarets.addSublayer(l); layers.append(l) }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB) ?? color
            let fill = (caretShape == .block ? c.withAlphaComponent(c.alphaComponent * 0.35) : c).cgColor
            for (l, f) in zip(layers, frames) { l.frame = f; l.backgroundColor = fill; l.isHidden = false }
        }
        for l in layers.dropFirst(frames.count) { l.isHidden = true }
        extraCarets.isHidden = false
        CATransaction.commit()
        extraCarets.removeAnimation(forKey: "blink")
        extraCarets.add(Self.blinkAnimation(), forKey: "blink")
    }

    /// Insertion-point rect from TextKit 2 after laying out the location, in text-view coordinates (the same as
    /// this view's); `firstRect` can answer from stale layout, and the segment API also covers the empty last line.
    static func insertionRect(in tv: NSTextView, at offset: Int) -> CGRect? {
        guard let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage,
              let loc = tcs.location(at: offset) else { return nil }
        // Lay out only the caret's own line: laying out to the document end made every keystroke O(rest of file).
        let end = tcs.location(loc, offsetBy: 1) ?? tcs.documentRange.endLocation
        if let range = NSTextRange(location: loc, end: end) { tlm.ensureLayout(for: range) }
        var rect: CGRect?
        tlm.enumerateTextSegments(in: NSTextRange(location: loc), type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
            rect = frame
            return false
        }
        return rect?.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y)
    }

    /// `insertionRect`, moved out of a kern gap: TextKit 2 puts the caret in the middle of the gap after a kerned
    /// character, but a hint's gap belongs before its argument and a swatch's after its `)`.
    private func caretRect(in tv: NSTextView, at offset: Int) -> CGRect? {
        guard let r = Self.insertionRect(in: tv, at: offset) else { return nil }
        guard offset > 0, let storage = tv.textStorage, offset <= storage.length,
              let kern = storage.attribute(.kern, at: offset - 1, effectiveRange: nil) as? NSNumber else { return r }
        let half = CGFloat(kern.doubleValue) / 2
        return r.offsetBy(dx: inlayHints?().contains { $0.offset == offset } == true ? half : -half, dy: 0)
    }

    private func hideCaret() {
        caret.removeAnimation(forKey: "blink")
        caret.isHidden = true
        caretShown = false
        caretFrame = .null
    }

    // MARK: Drawing

    override func draw(_ dirty: NSRect) {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage,
              let storage = tcs.textStorage, let viewport = tlm.textViewportLayoutController.viewportRange else { return }
        // Layout has settled by the end of a draw, so a caret placed against stale layout is corrected here.
        defer {
            updateExtraCarets(restartBlink: false)
            if usesCaretLayer, tv.selectedRange().length == 0, let r = caretRect(in: tv, at: tv.selectedRange().location),
               abs(r.minX - caretFrame.minX) > 0.5 || abs(r.minY - caretFrame.minY) > 0.5 { updateCaret() }
        }
        let text = storage.string as NSString
        let origin = tv.textContainerOrigin
        let sel = tv.selectedRange()
        pillHits = []
        badgeHits = []
        let hadSwatches = swatchHits.map(\.rect)
        swatchHits = []
        defer { if swatchHits.map(\.rect) != hadSwatches { window?.invalidateCursorRects(for: self) } }

        if sel.length > 0 { drawSelection(sel, tv: tv, tlm: tlm, tcs: tcs, viewport: viewport, origin: origin) }
        drawMultiCursors(tv: tv, tlm: tlm, tcs: tcs, viewport: viewport, origin: origin)

        let currentLine = text.lineRange(for: NSRange(location: min(sel.location, text.length), length: 0)).location
        var shown: [Int: NSRange] = [:], shownIsError: Set<Int> = [], shownFixable: Set<Int> = []
        let lines = items.map { item -> (line: Int, error: Bool, message: String) in
            // A diagnostic in a folded section shows on its heading line.
            let line = shownLine?(item.range.location) ?? text.lineRange(for: NSRange(location: min(item.range.location, text.length), length: 0)).location
            return (line, item.error, item.message)
        }
        let pills = Dictionary(uniqueKeysWithValues: PillLayout.pills(lines).map { ($0.line, $0) })
        // The pill shows the first error of its line, else the first diagnostic; a click reveals that one.
        for (item, l) in zip(items, lines) where shown[l.line] == nil || (item.error && !shownIsError.contains(l.line)) {
            shown[l.line] = item.range
            if item.fixable { shownFixable.insert(l.line) } else { shownFixable.remove(l.line) }
            if item.error { shownIsError.insert(l.line) }
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: Highlighter.fontSize - 3, weight: .semibold), .foregroundColor: NSColor.white]
        var guideLines: [(frag: NSTextLayoutFragment, frame: NSRect, start: Int)] = []
        let bookmarked = bookmarkStarts?() ?? []

        tlm.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { frag in
            let frame = frag.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            if frame.minY > dirty.maxY { return false }
            guard frame.maxY >= dirty.minY else { return true }
            let start = tcs.offset(of: frag.rangeInElement.location)
            let band = NSRect(x: 0, y: frame.minY, width: self.bounds.width, height: frame.height)
            if bookmarked.contains(start) {
                NSColor.systemPurple.withAlphaComponent(0.09).setFill()
                band.fill()
            }
            if sel.length == 0, start == currentLine {
                Highlighter.style.colors.currentLine.setFill()
                band.fill()
            }
            if let hb = self.hoverBand, start >= hb.location, start < NSMaxRange(hb) {
                Highlighter.style.colors.text.withAlphaComponent(0.05).setFill()
                band.fill()
            }
            let badgeEnd = self.drawFoldBadge(frag, at: start, frame: frame)
            if self.display.scopeGuides { guideLines.append((frag, frame, start)) }
            guard let pill = pills[start] else { return true }
            let color: NSColor = pill.error ? .systemRed : .systemOrange
            // A line holding both kinds is tinted by its worst diagnostic, which is what the pill shows.
            color.withAlphaComponent(0.10).setFill()
            band.fill()
            guard let first = frag.textLineFragments.first else { return true }
            let bounds = first.typographicBounds
            let right = min(self.bounds.width, tv.visibleRect.maxX) - 10      // without wrapping the view is wider than what shows
            let fixable = shownFixable.contains(start)
            let bulb: CGFloat = fixable ? 14 : 0
            let room = right - (max(frame.minX + bounds.maxX, badgeEnd ?? 0) + 14) - 14 - bulb
            guard room > 20, let label = PillLayout.text(pill, fitting: room, measure: { ($0 as NSString).size(withAttributes: attrs).width }) else { return true }
            let width = ceil((label as NSString).size(withAttributes: attrs).width) + 14 + bulb
            let height = min(Highlighter.fontSize + 3, bounds.height)
            let rect = NSRect(x: right - width, y: frame.minY + bounds.minY + (bounds.height - height) / 2, width: width, height: height)
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            let size = (label as NSString).size(withAttributes: attrs)
            if fixable, let img = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: Highlighter.fontSize - 4, weight: .semibold).applying(.init(paletteColors: [.white]))) {
                img.draw(in: NSRect(x: rect.minX + 6, y: rect.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
            }
            (label as NSString).draw(at: NSPoint(x: rect.minX + 7 + bulb, y: rect.midY - size.height / 2), withAttributes: attrs)
            if let range = shown[start] { self.pillHits.append((rect, range, fixable)) }
            return true
        }
        drawScopeGuides(guideLines, text: text)
        drawFormatGuide(tv, in: dirty)
        drawSwatches(tv: tv, text: text, viewport: viewport)
        drawInlayHints(tv: tv, viewport: viewport)
        drawOccurrences(tlm: tlm, tcs: tcs, length: text.length, origin: origin)
        // Last, so the current-line band doesn't cover the bracket on the caret's line.
        drawBrackets(tlm: tlm, tcs: tcs, length: text.length, origin: origin)
    }

    /// A rounded square in the kern gap behind each literal's `)`, centered on its line.
    private func drawSwatches(tv: NSTextView, text: NSString, viewport: NSTextRange) {
        guard let tcs = tv.textContentStorage, let literals = colorLiterals?() else { return }
        let lo = tcs.offset(of: viewport.location), hi = tcs.offset(of: viewport.endLocation)
        let side: CGFloat = 11
        for lit in literals where lit.range.location >= lo && lit.range.location <= hi {
            // Anchor on the `)` itself: TextKit 2 reports a kerned character's end mid-gap, and ignores the kern at a
            // line end, so the glyph's start plus its advance is the only reliable gap start.
            let close = NSMaxRange(lit.range) - 1
            guard let r = Self.insertionRect(in: tv, at: close), r.height > 1 else { continue }
            let font = tv.textStorage?.attribute(.font, at: close, effectiveRange: nil) as? NSFont ?? .monospacedSystemFont(ofSize: Highlighter.fontSize, weight: .regular)
            let advance = (")" as NSString).size(withAttributes: [.font: font]).width
            let gapStart = r.minX + advance
            let box = NSRect(x: gapStart + (Buffer.swatchGap - side) / 2, y: r.midY - side / 2, width: side, height: side)
            let shape = NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5)
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            if lit.alpha < 1 {
                NSColor.white.setFill()
                box.fill()
                NSColor.lightGray.setFill()
                NSRect(x: box.minX, y: box.minY, width: side / 2, height: side / 2).fill()
                NSRect(x: box.midX, y: box.midY, width: side / 2, height: side / 2).fill()
            }
            NSColor(srgbRed: lit.red, green: lit.green, blue: lit.blue, alpha: lit.alpha).setFill()
            box.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.separatorColor.setStroke()
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            outline.stroke()
            swatchHits.append((box.insetBy(dx: -2, dy: -2), lit))
        }
    }

    /// Each hint's label on a faint rounded background, filling the kern gap before its argument, centered on its line.
    private func drawInlayHints(tv: NSTextView, viewport: NSTextRange) {
        guard let tcs = tv.textContentStorage, let hints = inlayHints?(), !hints.isEmpty else { return }
        let lo = tcs.offset(of: viewport.location), hi = tcs.offset(of: viewport.endLocation)
        let attrs: [NSAttributedString.Key: Any] = [.font: InlayHints.font, .foregroundColor: NSColor.secondaryLabelColor]
        for h in hints where h.offset >= lo && h.offset <= hi {
            // The raw insertion point is the middle of the gap (see caretRect).
            guard let r = Self.insertionRect(in: tv, at: h.offset), r.height > 1 else { continue }
            let gap = InlayHints.gap(h.label)
            let size = (h.label as NSString).size(withAttributes: attrs)
            let height = min(ceil(size.height), r.height)
            let pill = NSRect(x: r.minX - gap / 2 + InlayHints.margin, y: r.midY - height / 2, width: gap - 2 * InlayHints.margin, height: height)
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: pill, xRadius: 3, yRadius: 3).fill()
            (h.label as NSString).draw(at: NSPoint(x: pill.minX + InlayHints.padding, y: pill.midY - size.height / 2), withAttributes: attrs)
        }
    }

    private func drawBrackets(tlm: NSTextLayoutManager, tcs: NSTextContentStorage, length: Int, origin: NSPoint) {
        let color = Highlighter.style.colors.text
        for r in brackets where NSMaxRange(r) <= length {
            guard let range = tcs.textRange(for: r) else { continue }
            tlm.enumerateTextSegments(in: range, type: .selection, options: []) { _, rect, _, _ in
                let path = NSBezierPath(roundedRect: rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
                color.withAlphaComponent(0.18).setFill()
                path.fill()
                color.withAlphaComponent(0.6).setStroke()
                path.lineWidth = 1
                path.stroke()
                return false
            }
        }
    }

    func drawSelection(_ sel: NSRange, tv: NSTextView, tlm: NSTextLayoutManager, tcs: NSTextContentStorage,
                               viewport: NSTextRange, origin: NSPoint) {
        let lo = max(sel.location, tcs.offset(of: viewport.location))
        let hi = min(NSMaxRange(sel), tcs.offset(of: viewport.endLocation))
        guard hi > lo, let range = tcs.textRange(for: NSRange(location: lo, length: hi - lo)) else { return }
        var segments: [CGRect] = []
        tlm.enumerateTextSegments(in: range, type: .selection, options: []) { _, rect, _, _ in
            segments.append(rect.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        (window?.isKeyWindow == true ? Highlighter.style.colors.selection : Highlighter.style.colors.inactiveSelection).setFill()
        for r in SelectionShape.lineRects(segments) {
            NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        }
    }
}


extension SettingsKey {
    static let bracketMatch = "bracketMatchHighlight"
    static let rainbowBrackets = "rainbowBrackets"
    static let colorSwatches = "colorSwatches"
    static let colorPickerStyle = "colorPickerStyle"
    static let inlayHints = "inlayHints"
}

extension EditorView.Coordinator {
    /// Opens a popover below `anchor` (the swatch, in the decoration view) editing `literal`; each change rewrites
    /// it in place as its own undo step (Buffer.apply groups per call). Escape or a click outside closes it.
    func pickColor(_ literal: ColorLiteral, anchor: NSRect) {
        guard let decor else { return }
        swatchRange = literal.range
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ColorPopoverView(
            color: literal, onChange: { [weak self] in self?.colorPicked($0) }))
        popover.show(relativeTo: anchor, of: decor, preferredEdge: .maxY)
    }

    func colorPicked(_ c: NSColor) {
        guard let buffer, let range = swatchRange,
              let old = buffer.colorLiterals.first(where: { $0.range == range }),   // the text moved on: let go
              let c = c.usingColorSpace(.sRGB) else { swatchRange = nil; return }
        let same = { (a: Double, b: CGFloat) in abs(a - Double(b)) < 0.5 / 255 }
        guard !(same(old.red, c.redComponent) && same(old.green, c.greenComponent) && same(old.blue, c.blueComponent) && same(old.alpha, c.alphaComponent)) else { return }
        let text = ColorLiterals.source(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
        buffer.apply([Replacement(range: range, text: text)], actionName: "Change Color")
        swatchRange = NSRange(location: range.location, length: (text as NSString).length)
        decor?.refresh()
    }
}

/// Red, green, blue and alpha sliders; every drag step reports the new color.
/// Hue around the circle (red at the right, clockwise), saturation from the centre out; dimmed by brightness.
private struct ColorWheel: View {
    let hue: Double, saturation: Double, brightness: Double
    let pick: (_ hue: Double, _ saturation: Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2, c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let angle = hue * 2 * .pi
            ZStack {
                Circle().fill(AngularGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: r))
                Circle().fill(.black.opacity(1 - brightness))
                Circle().strokeBorder(.white, lineWidth: 2).background(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 3))
                    .frame(width: 14, height: 14)
                    .position(x: c.x + cos(angle) * saturation * r, y: c.y + sin(angle) * saturation * r)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - c.x, dy = g.location.y - c.y
                var h = atan2(dy, dx) / (2 * .pi)
                if h < 0 { h += 1 }
                pick(h, min(1, hypot(dx, dy) / r))
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Color wheel")
        .accessibilityValue("Hue \(Int(hue * 360)) degrees, saturation \(Int(saturation * 100)) percent")
    }
}

/// How the swatch popover picks: a colour wheel (hue and saturation, then brightness) or one slider per channel.
enum ColorPickerStyle: String, CaseIterable {
    case wheel, sliders
    var title: String { self == .wheel ? "Color Wheel" : "RGB Sliders" }
}

struct ColorPopoverView: View {
    @State private var rgba: [Double]
    /// Kept apart from `rgba` so a grey keeps its hue while saturation or brightness is zero.
    @State private var hsb: [Double]
    @AppStorage(SettingsKey.colorPickerStyle) private var style = ColorPickerStyle.wheel
    let onChange: (NSColor) -> Void

    init(color: ColorLiteral, onChange: @escaping (NSColor) -> Void) {
        let rgba = [color.red, color.green, color.blue, color.alpha]
        _rgba = State(initialValue: rgba)
        _hsb = State(initialValue: Self.hsb(rgba, hue: 0))
        self.onChange = onChange
    }

    /// Red, green and blue edit as 0–255, alpha as a percentage, like Typst's own `rgb` arguments.
    private static let channels: [(name: String, scale: Double, unit: String)] = [("Red", 255, ""), ("Green", 255, ""), ("Blue", 255, ""), ("Alpha", 100, "%")]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if style == .wheel {
                ColorWheel(hue: hsb[0], saturation: hsb[1], brightness: hsb[2]) { h, sat in setHSB([h, sat, hsb[2]]) }
                    .frame(width: 180, height: 180).frame(maxWidth: .infinity)
                HStack {
                    Text("Bright").frame(width: 44, alignment: .leading)
                    Slider(value: Binding(get: { hsb[2] }, set: { setHSB([hsb[0], hsb[1], $0]) }), in: 0...1).accessibilityLabel("Brightness")
                    Spacer().frame(width: 64)
                }
            }
            ForEach(Array(Self.channels.enumerated()), id: \.offset) { i, ch in
                HStack {
                    Text(ch.name).frame(width: 44, alignment: .leading)
                    if style == .sliders || i == 3 {
                        Slider(value: Binding(get: { rgba[i] }, set: { set(i, $0) }), in: 0...1)
                            .accessibilityLabel(ch.name)
                    } else {
                        Spacer()
                    }
                    TextField(ch.name, value: Binding(get: { Int((rgba[i] * ch.scale).rounded()) },
                                                      set: { set(i, Double(min(max($0, 0), Int(ch.scale))) / ch.scale) }),
                              format: .number)
                        .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).monospacedDigit()
                        .frame(width: 48).labelsHidden()
                        .accessibilityLabel("\(ch.name) value")
                    Text(ch.unit).foregroundStyle(.secondary).frame(width: 12, alignment: .leading)
                }
            }
            HStack {
                Text("Hex").frame(width: 44, alignment: .leading)
                TextField("Hex", text: Binding(get: { hex }, set: { if let c = Self.parseHex($0) { for k in 0..<4 { rgba[k] = c[k] }; hsb = Self.hsb(rgba, hue: hsb[0]); changed() } }))
                    .textFieldStyle(.roundedBorder).monospaced().labelsHidden()
                    .accessibilityLabel("Hex value")
            }
        }
        .padding(12)
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color picker")
    }

    private func set(_ i: Int, _ v: Double) {
        rgba[i] = v
        hsb = Self.hsb(rgba, hue: hsb[0])
        changed()
    }

    private func setHSB(_ v: [Double]) {
        hsb = v
        let c = NSColor(hue: v[0], saturation: v[1], brightness: v[2], alpha: 1).usingColorSpace(.sRGB) ?? .black
        rgba = [c.redComponent, c.greenComponent, c.blueComponent, rgba[3]]
        changed()
    }

    static func hsb(_ rgba: [Double], hue: Double) -> [Double] {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return [s == 0 || b == 0 ? hue : h, s, b]
    }

    private func changed() { onChange(NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: rgba[3])) }

    private var hex: String {
        let b = rgba.map { Int(($0 * 255).rounded()) }
        return b[3] == 255 ? String(format: "#%02x%02x%02x", b[0], b[1], b[2]) : String(format: "#%02x%02x%02x%02x", b[0], b[1], b[2], b[3])
    }

    /// "#rgb", "#rrggbb" or "#rrggbbaa", with or without "#"; nil while incomplete.
    static func parseHex(_ s: String) -> [Double]? {
        var h = s.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let n = h.count == 6 ? (v << 8) | 0xff : v
        return [24, 16, 8, 0].map { Double((n >> $0) & 0xff) / 255 }
    }
}

extension EditorView.Coordinator {
    func refreshBracketMatch() {
        guard matchesBrackets, let tv = textView, tv.selectedRange().length == 0, let buffer else { decor?.brackets = []; return }
        decor?.brackets = buffer.bracketPair(at: tv.selectedRange().location).map { [$0.0, $0.1] } ?? []
    }

    func setMatchesBrackets(_ on: Bool) {
        guard on != matchesBrackets else { return }
        matchesBrackets = on
        refreshBracketMatch()
    }
}

extension EditorView.Coordinator {
    /// Gold, orchid, sky blue by depth, darker on light backgrounds so they stay readable.
    static let rainbow: [NSColor] = [(0xB8860B, 0xFFD700), (0xA626A4, 0xDA70D6), (0x0B7BD6, 0x87CEFA)].map { light, dark in
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .hex(dark) : .hex(light) }
    }

    /// Rendering attributes: the highlighter's storage colors stay untouched, and depth changes anywhere repaint for free.
    func refreshRainbow() {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return }
        tlm.removeRenderingAttribute(.foregroundColor, for: tcs.documentRange)
        guard rainbowBrackets, let buffer else { return }
        let length = tv.textStorage?.length ?? 0
        for b in buffer.bracketDepths() where b.depth >= 0 && b.location < length {
            guard let r = tcs.textRange(for: NSRange(location: b.location, length: 1)) else { continue }
            tlm.addRenderingAttribute(.foregroundColor, value: Self.rainbow[b.depth % Self.rainbow.count], for: r)
        }
    }

    func setRainbowBrackets(_ on: Bool) {
        guard on != rainbowBrackets else { return }
        rainbowBrackets = on
        refreshRainbow()
    }
}
