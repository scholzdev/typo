import Foundation

/// Sticky Scroll: the headings pinned over the top of the editor while their section scrolls by.
public enum StickyScroll {
    /// The sections around a viewport whose top line starts at `top` whose heading line lies above it, outermost first
    /// and at most `limit` deep. A heading on the top line itself is visible and not pinned.
    public static func headings(_ regions: [FoldRegion], top: Int, limit: Int = 3) -> [FoldRegion] {
        Array(regions.filter { $0.heading < top && top < NSMaxRange($0.hidden) }.prefix(limit))
    }
}

extension Buffer {
    /// The headings pinned above a viewport whose top line holds `p` (a hidden position counts as its fold's heading line).
    public func stickyHeadings(top p: Int, limit: Int = 3) -> [FoldRegion] {
        StickyScroll.headings(headingRegions, top: visibleLine(of: p), limit: limit)
    }
}
