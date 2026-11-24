import AppKit
import TypoKit

/// The assistant's pending edit, reviewed in the editor: the text it would replace struck through on a red band, the
/// replacement on a green card below it, and Accept / Reject floating at the change. The buffer is not touched until
/// Accept. A transparent subview of the text view, like `DecorationView`; only the buttons take clicks.
@MainActor final class InlineDiffOverlay: NSView {
    weak var textView: NSTextView?
    weak var buffer: Buffer? { didSet { if buffer !== oldValue { sync() } } }
    private var preview: InlineDiffPreview?
    private let bar = NSStackView()

    override var isFlipped: Bool { true }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: textView.bounds)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.zPosition = 1001
        let accept = NSButton(title: "Accept", target: self, action: #selector(acceptChange))
        let reject = NSButton(title: "Reject", target: self, action: #selector(rejectChange))
        accept.setAccessibilityLabel(String(localized: "Accept the assistant's change"))
        reject.setAccessibilityLabel(String(localized: "Reject the assistant's change"))
        for b in [reject, accept] {
            b.controlSize = .small
            b.bezelStyle = .rounded
            bar.addArrangedSubview(b)
        }
        accept.bezelColor = .controlAccentColor
        bar.orientation = .horizontal
        bar.spacing = 6
        bar.isHidden = true
        addSubview(bar)
        NotificationCenter.default.addObserver(self, selector: #selector(changed(_:)), name: .bufferInlineDiffChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func changed(_ n: Notification) { if (n.object as? Buffer) === buffer { sync() } }
    @objc private func acceptChange() { preview?.accept() }
    @objc private func rejectChange() { preview?.reject() }

    private func sync() {
        preview = buffer?.inlineDiff
        bar.isHidden = preview == nil
        needsLayout = true
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return bar.isHidden || !bar.frame.contains(p) ? nil : bar.hitTest(p) ?? bar
    }

    override func accessibilityChildren() -> [Any]? { bar.isHidden ? [] : [bar] }

    /// Where the change is, in this view's coordinates.
    private struct Geometry {
        var bands: [NSRect] = []
        var strikes: [NSRect] = []
        var card: NSRect?
        var lineHeight: CGFloat = 16
    }

    private func geometry() -> Geometry? {
        guard let p = preview, let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage,
              NSMaxRange(p.range) <= (tv.textStorage?.length ?? 0), let range = tcs.textRange(for: p.range) else { return nil }
        let origin = tv.textContainerOrigin
        var g = Geometry()
        tlm.enumerateTextLayoutFragments(from: range.location, options: [.ensuresLayout]) { frag in
            guard tcs.offset(of: frag.rangeInElement.location) < NSMaxRange(p.range) else { return false }
            if g.bands.isEmpty, let h = frag.textLineFragments.first?.typographicBounds.height { g.lineHeight = h }
            g.bands.append(frag.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        tlm.enumerateTextSegments(in: range, type: .standard, options: []) { _, rect, _, _ in
            if rect.width > 0 { g.strikes.append(rect.offsetBy(dx: origin.x, dy: origin.y)) }
            return true
        }
        guard let last = g.bands.last else { return nil }
        if !p.replacement.isEmpty {
            g.card = NSRect(x: 0, y: last.maxY, width: bounds.width, height: g.lineHeight * CGFloat(Self.lines(p.replacement).count) + 6)
        }
        return g
    }

    private static func lines(_ s: String) -> [String] {
        var parts = s.components(separatedBy: "\n")
        if parts.count > 1, parts.last == "" { parts.removeLast() }
        return parts
    }

    override func layout() {
        super.layout()
        guard !bar.isHidden, let g = geometry(), let first = g.bands.first, let tv = textView else { return }
        let size = bar.fittingSize
        bar.frame = NSRect(x: max(8, tv.visibleRect.maxX - size.width - 12), y: max(2, first.minY - size.height - 2), width: size.width, height: size.height)
    }

    override func draw(_ dirty: NSRect) {
        guard let p = preview, let g = geometry() else { return }
        NSColor.systemRed.withAlphaComponent(0.16).setFill()
        for band in g.bands { NSRect(x: 0, y: band.minY, width: bounds.width, height: band.height).fill() }
        NSColor.systemRed.withAlphaComponent(0.85).setFill()
        for s in g.strikes { NSRect(x: s.minX, y: s.midY - 0.5, width: s.width, height: 1).fill() }
        guard let card = g.card, let tv = textView else { return }
        Highlighter.style.colors.background.setFill()
        card.fill()
        NSColor.systemGreen.withAlphaComponent(0.16).setFill()
        card.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Highlighter.baseFont, .foregroundColor: Highlighter.style.colors.text]
        let x = tv.textContainerOrigin.x + (tv.textContainer?.lineFragmentPadding ?? 5)
        for (i, line) in Self.lines(p.replacement).enumerated() {
            (line as NSString).draw(at: NSPoint(x: x, y: card.minY + 3 + CGFloat(i) * g.lineHeight), withAttributes: attrs)
        }
    }
}
