import AppKit
import TypoKit

/// One fold's ~0.25 s transition, done as Xcode does it: a placeholder of animated height sits in the layout under the
/// fold line (FoldController.setPad), so the real text after the region moves by itself, and a paper-fold view of
/// just the folding lines fills it, in the text and in the gutter. A display link drives the placeholder, the paper,
/// and the ribbon, chevron and badge, all from one eased progress per frame.
@MainActor final class FoldAnimator: NSObject {
    struct State {
        let heading: Int, folding: Bool, start: CFTimeInterval
        let full: CGFloat                 // the placeholder's height when open: the folding lines' visible part
        let foldY: CGFloat                // the fold line in text view coordinates
        let region: NSRange               // heading line through the region's end, laid out again at the end
        var eased: CGFloat = 0
    }
    private(set) var state: State?
    private var link: CADisplayLink?
    private var papers: [FoldPaperView] = []
    private var duration = FoldPaper.duration
    /// Each frame, after `state.eased` moved: the editor sets the placeholder and redraws the gutter and decorations.
    var onFrame: ((State) -> Void)?
    /// Once, when the motion ends or is cut short: the editor drops the placeholder and lays the region out for real.
    var onEnd: ((State) -> Void)?

    /// Eased progress (0 start, 1 done) of the fold animating at `heading`, as of this frame.
    func progress(_ heading: Int) -> (eased: CGFloat, state: State)? {
        guard let s = state, s.heading == heading else { return nil }
        return (s.eased, s)
    }

    func start(_ s: State, papers: [FoldPaperView], on view: NSView) {
        finish()
        state = s
        self.papers = papers
        duration = DisplaySettings.foldDuration
        let link = view.displayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)   // ProMotion's full rate
        link.add(to: .main, forMode: .common)
        self.link = link
        apply(s)
        // A link that never fires (window hidden, display asleep) must not leave the placeholder behind.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) { [weak self] in
            if self?.state?.start == s.start { self?.finish() }
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard var s = state else { return }
        let t = (link.targetTimestamp - s.start) / duration  // where this frame will be when it shows
        s.eased = FoldPaper.eased(t)
        state = s
        apply(s)
        if t >= 1 { finish() }
    }

    private func apply(_ s: State) {
        let current = FoldPaper.height(full: s.full, eased: s.eased, folding: s.folding)
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // standalone layers would otherwise smear every change over 0.25 s
        papers.forEach { $0.show(height: current) }
        CATransaction.commit()
        onFrame?(s)
    }

    /// Ends the motion at once (an edit, a scroll, another fold): the layout takes its final shape.
    func finish() {
        link?.invalidate()
        link = nil
        papers.forEach { $0.removeFromSuperview() }
        papers = []
        guard let s = state else { return }
        state = nil
        onEnd?(s)
    }

    /// The host's picture of `rect` (its own coordinates), or nil when it drew nothing usable.
    static func snapshot(_ host: NSView, _ rect: NSRect) -> (image: CGImage, scale: CGFloat)? {
        guard rect.height >= 1, let rep = host.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        host.cacheDisplay(in: rect, to: rep)
        return rep.cgImage.map { ($0, CGFloat(rep.pixelsHigh) / rect.height) }
    }
}

/// The folding lines as paper folded in two (Xcode's substitution view): the top half hangs from the fold line, the
/// bottom half stands on the placeholder's bottom edge, and both tilt about the horizontal axis with perspective while
/// a black shade deepens on them. Opaque in the editor background, so nothing stretched under it shows through.
final class FoldPaperView: NSView {
    private let full: CGFloat
    private let halves: [(panel: CALayer, shade: CALayer, top: Bool)]

    /// `frame`: where the placeholder starts and how wide, in the host's flipped coordinates; `full`: its open height.
    init(image: CGImage, scale: CGFloat, frame: NSRect, full: CGFloat, background: CGColor) {
        self.full = full
        let half = Int(image.height / 2)
        halves = [true, false].map { top in
            let panel = CALayer()
            panel.contentsScale = scale
            panel.contentsGravity = .resize
            panel.contents = image.cropping(to: CGRect(x: 0, y: top ? 0 : half, width: image.width, height: top ? half : image.height - half))
            panel.anchorPoint = CGPoint(x: 0.5, y: top ? 1 : 0)
            panel.bounds = CGRect(x: 0, y: 0, width: frame.width, height: full / 2)
            let shade = CALayer()
            shade.backgroundColor = .black
            shade.frame = panel.bounds
            shade.opacity = 0
            panel.addSublayer(shade)
            return (panel, shade, top)
        }
        super.init(frame: frame)
        wantsLayer = true
        clipsToBounds = true
        layer?.backgroundColor = background
        // The lower half after the upper one: where the seam overlaps under perspective, the darker half is in front.
        halves.forEach { layer?.addSublayer($0.panel) }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Lays the paper out spanning `height` (0...full). Not flipped: layer y runs up, so the top half hangs from maxY.
    func show(height: CGFloat) {
        setFrameSize(NSSize(width: frame.width, height: height))
        let angle = FoldPaper.angle(current: height, full: full)
        for h in halves {
            h.panel.position = CGPoint(x: frame.width / 2, y: h.top ? height : 0)
            h.panel.transform = FoldPaper.panel(top: h.top, angle: angle, full: full)
            h.shade.opacity = FoldPaper.shade(top: h.top, angle: angle)
        }
    }
}
