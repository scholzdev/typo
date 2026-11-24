import CoreGraphics
import Foundation
import TypstEngine

/// The bottom bar's word count: the compiled total comes from the engine, a selection from its prose ranges.
public enum WordCount {
    /// Words of the selection's markup text only (no code, math, strings or raw), by the same segmentation as the total.
    static func selected(in text: String, prose: [NSRange], selection: NSRange) -> Int {
        let ns = text as NSString
        return prose.reduce(0) { n, r in
            let i = NSIntersectionRange(r, selection)
            return i.length > 0 && NSMaxRange(i) <= ns.length ? n + Bridge.words(in: ns.substring(with: i)) : n
        }
    }

    /// "4,075 words", "12 of 4,075 words" with a selection, or "4,075 / 20,000 words" with a goal (a selection wins).
    public static func label(total: Int, selected: Int? = nil, goal: Int? = nil, locale: Locale = .current) -> String {
        func n(_ v: Int) -> String { v.formatted(.number.locale(locale)) }
        if selected == nil, let goal { return String(localized: "\(n(total)) / \(n(goal)) words", bundle: .module) }
        if let selected {
            return total == 1 ? String(localized: "\(n(selected)) of \(n(total)) word", bundle: .module)
                              : String(localized: "\(n(selected)) of \(n(total)) words", bundle: .module)
        }
        return total == 1 ? String(localized: "\(n(total)) word", bundle: .module) : String(localized: "\(n(total)) words", bundle: .module)
    }
}

/// Zoom and paging arithmetic of the preview toolbar. `PreviewModel.zoom` 1 fits the column width; the
/// percentage the user sees is relative to the page's natural size (1 pt of page = 1 pt on screen).
public enum PreviewMath {
    public static let presets = [50, 75, 100, 125, 150, 200]
    public static let zoomRange: ClosedRange<CGFloat> = 0.25...4
    public static let fitWidthZoom: CGFloat = 1
    /// Space around and between pages in the preview's scroll content.
    public static let pageInset: CGFloat = 16

    /// The zoom at which `fit` holds for pages of `page` size: Fit Page shows a whole page in the viewport,
    /// Two Pages two side by side. Never wider than the column (zoom 1).
    public static func zoom(fitting fit: PreviewFit, page: CGSize, viewport: CGSize, fitWidth: CGFloat, inset: CGFloat = pageInset) -> CGFloat {
        guard fit != .width, fitWidth > 0, page.width > 0, page.height > 0, viewport.height > 0 else { return fitWidthZoom }
        let byHeight = (viewport.height - 2 * inset) * page.width / page.height
        let byWidth = fit == .twoPages ? (fitWidth - inset) / 2 : fitWidth
        return min(max(min(byHeight, byWidth) / fitWidth, zoomRange.lowerBound), zoomRange.upperBound)
    }

    public static func percent(zoom: CGFloat, fitWidth: CGFloat, pageWidth: CGFloat) -> Int {
        guard pageWidth > 0 else { return 100 }
        return Int((zoom * fitWidth / pageWidth * 100).rounded())
    }

    public static func zoom(percent: Int, fitWidth: CGFloat, pageWidth: CGFloat) -> CGFloat {
        guard fitWidth > 0 else { return 1 }
        return min(max(CGFloat(percent) / 100 * pageWidth / fitWidth, zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// Frames of the pages in the scroll content: rows of `columns` pages, each `width` wide with its own aspect,
    /// `inset` around and between, a row as tall as its tallest page.
    public static func frames(sizes: [CGSize], width: CGFloat, inset: CGFloat, columns: Int = 1) -> [CGRect] {
        let columns = max(columns, 1)
        var y = inset, rects: [CGRect] = []
        for row in stride(from: 0, to: sizes.count, by: columns) {
            let heights = sizes[row..<min(row + columns, sizes.count)].map { width * $0.height / max($0.width, 1) }
            for (i, h) in heights.enumerated() {
                rects.append(CGRect(x: inset + CGFloat(i) * (width + inset), y: y, width: width, height: h))
            }
            y += heights.max()! + inset
        }
        return rects
    }

    /// Page indices grouped into rows of `columns`.
    public static func rows(count: Int, columns: Int) -> [Range<Int>] {
        let columns = max(columns, 1)
        return stride(from: 0, to: count, by: columns).map { $0..<min($0 + columns, count) }
    }

    /// The page with the largest visible area (the first on a tie); nil when none is visible.
    public static func mostVisiblePage(frames: [CGRect], visible: CGRect) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (i, f) in frames.enumerated() {
            let r = f.intersection(visible)
            let area = r.isNull ? 0 : r.width * r.height
            if area > (best?.area ?? 0) { best = (i, area) }
        }
        return best?.index
    }
}
