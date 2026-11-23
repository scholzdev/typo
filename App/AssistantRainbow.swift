import AppKit
import QuartzCore
import SwiftUI
import TypoKit

extension Notification.Name {
    /// The gutter's "Discard Change" on an assistant bar; object: the Buffer, userInfo "range": the mark's NSRange.
    static let assistantDiscardChange = Notification.Name("Tympan.assistantDiscardChange")
}

/// The bar beside lines the agent changed: a pill outlined in a slowly drifting blue, purple, red and orange gradient,
/// its inside the same gradient washed out to a pastel. Changes from earlier turns get a grey outline instead.
final class RainbowBarLayer: CALayer {
    private let gradient = CAGradientLayer()
    /// Covers all but the outline with the background at 60%, so only the ring shows the full colors.
    private let wash = CALayer()
    private static let ring: CGFloat = 1.25
    private static let stops: [Double] = [0, 0.33, 0.66, 1]
    /// Xcode's bar as it renders: blue, a magenta-purple, a coral red and orange, measured from its gutter.
    private static let colors: [CGColor] = [0x5B97E2, 0xD56ADA, 0xF56D69, 0xF59A5F].map {
        CGColor(srgbRed: CGFloat($0 >> 16 & 0xFF) / 255, green: CGFloat($0 >> 8 & 0xFF) / 255, blue: CGFloat($0 & 0xFF) / 255, alpha: 1)
    }
    /// A change from an earlier turn.
    var previous = false

    override init() {
        super.init()
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.locations = Self.stops.map { $0 as NSNumber }
        addSublayer(gradient)
        addSublayer(wash)
        animate()
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The pill's width for a line height, as Xcode sizes its change bars: 5 pt at ordinary heights, wider for tall lines.
    static func width(lineHeight: CGFloat) -> CGFloat {
        let margin = lineHeight < 20 ? 11 : 2 * floor((lineHeight - 9) / 2) + 1
        return max(floor(margin * 5 / 11), 5)
    }

    /// Colors are resolved for `appearance`: CGColors don't follow light and dark by themselves.
    func style(for appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            gradient.colors = Self.colors
            wash.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.6).cgColor
            borderColor = NSColor.systemGray.withAlphaComponent(0.5).cgColor
        }
        gradient.isHidden = previous
        wash.isHidden = previous
        borderWidth = previous ? 1 : 0
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        cornerRadius = bounds.width / 2
        gradient.frame = bounds
        gradient.cornerRadius = cornerRadius
        wash.frame = bounds.insetBy(dx: Self.ring, dy: Self.ring)
        wash.cornerRadius = max(cornerRadius - Self.ring, 0)
    }

    /// Eight small random shifts of the inner stops, back and forth over 20 s; none with Reduce Motion.
    private func animate() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let frames: [[NSNumber]] = (0..<8).map { k in
            guard k > 0 else { return Self.stops.map { $0 as NSNumber } }
            let inner = Self.stops.dropFirst().dropLast().map { min(max($0 + Double.random(in: -0.08...0.08), 0.02), 0.98) }.sorted()
            return ([0] + inner + [1]).map { $0 as NSNumber }
        }
        let a = CAKeyframeAnimation(keyPath: "locations")
        a.values = frames
        a.duration = 20
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(a, forKey: "drift")
    }
}

/// The same bar in SwiftUI, for the diff panel.
struct RainbowBar: NSViewRepresentable {
    var previous = false

    final class BarView: NSView {
        let bar = RainbowBarLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(bar)
        }
        required init?(coder: NSCoder) { fatalError("not used") }
        /// Flipped like the gutter's `RainbowOverlay`, so the gradient runs blue at the top here too.
        override var isFlipped: Bool { true }
        override func layout() {
            super.layout()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            bar.frame = bounds
            CATransaction.commit()
        }
        override func viewDidChangeEffectiveAppearance() { bar.style(for: effectiveAppearance) }
    }

    func makeNSView(context: Context) -> BarView { BarView() }
    func updateNSView(_ v: BarView, context: Context) {
        v.bar.previous = previous
        v.bar.style(for: v.effectiveAppearance)
    }
}

extension LineNumberRuler: NSViewToolTipOwner {
    /// Lays one bar over each assistant change in view, reusing the layers so scrolling doesn't restart their drift.
    func layoutRainbow(_ tv: NSTextView, _ tcs: NSTextContentStorage, viewport: NSTextRange) {
        guard let buffer = editor?.buffer else { return }
        let vs = tcs.offset(of: viewport.location), ve = tcs.offset(of: viewport.endLocation)
        var blocks = buffer.aiMarks.ranges
        if let d = buffer.inlineDiff?.range, !blocks.contains(where: { NSIntersectionRange($0, d).length > 0 }) { blocks.append(d) }
        var hits: [RainbowHit] = []
        for r in blocks where r.location <= ve && NSMaxRange(r) >= vs {
            let first = r.location >= vs ? rowSpan(of: r.location) : nil
            let last = NSMaxRange(r) <= ve ? rowSpan(of: max(NSMaxRange(r) - 1, r.location)) : nil
            let top = first?.0 ?? bounds.minY - 4, bottom = last?.1 ?? bounds.maxY + 4
            guard bottom > top else { continue }
            let previous = buffer.isPreviousAIBlock(r)
            let full = RainbowBarLayer.width(lineHeight: (first ?? last).map { $0.1 - $0.0 } ?? 16)
            let w = previous ? floor(full * 0.8) : full
            hits.append(RainbowHit(rect: NSRect(x: 1 + (full - w) / 2, y: top + 1, width: w, height: bottom - top - 2), range: r, previous: previous))
        }
        rainbowHits = hits
        let overlay = subviews.compactMap { $0 as? RainbowOverlay }.first ?? {
            let v = RainbowOverlay(frame: bounds)
            v.autoresizingMask = [.width, .height]
            addSubview(v)
            return v
        }()
        if overlay.frame != bounds { overlay.frame = bounds }
        guard let host = overlay.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        while rainbowLayers.count < hits.count {
            let l = RainbowBarLayer()
            host.addSublayer(l)
            rainbowLayers.append(l)
        }
        for (i, l) in rainbowLayers.enumerated() {
            guard hits.indices.contains(i) else { l.isHidden = true; continue }
            l.isHidden = false
            l.previous = hits[i].previous
            l.style(for: effectiveAppearance)
            l.frame = hits[i].rect
        }
        CATransaction.commit()
        removeAllToolTips()
        for h in hits { addToolTip(h.rect, owner: self, userData: nil) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        rainbowHits.first { $0.rect.insetBy(dx: -2, dy: 0).contains(point) }?.previous == true ? "Previous changes" : "Generated change"
    }

    /// A click on an assistant bar: Dismiss (the bar goes, the text stays) or Discard Change (the text goes back).
    func clickRainbow(_ event: NSEvent) -> Bool {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = rainbowHits.first(where: { $0.rect.insetBy(dx: -2, dy: 0).contains(p) }), let buffer = editor?.buffer else { return false }
        let menu = NSMenu()
        menu.addItem(RainbowMenuItem("Dismiss") { buffer.dismissAIMark(hit.range) })
        let discard = RainbowMenuItem("Discard Change") {
            NotificationCenter.default.post(name: .assistantDiscardChange, object: buffer, userInfo: ["range": NSValue(range: hit.range)])
        }
        discard.isEnabled = buffer.aiChanges(in: hit.range).contains { buffer.canRevert($0.id) }
        menu.addItem(discard)
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: hit.rect.maxX + 2, y: p.y), in: self)
        return true
    }
}

/// The ruler's layer for the bars: its own flipped, layer-backed view, so the bars sit in ruler coordinates; clicks pass through.
final class RainbowOverlay: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { superview?.isFlipped ?? true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct RainbowHit {
    let rect: NSRect
    let range: NSRange
    let previous: Bool
}

private final class RainbowMenuItem: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("not used") }
    @objc private func fire() { run() }
}
