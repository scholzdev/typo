import Foundation
import TypstEngine

/// The pages choice of File › Export › PDF, as in the print dialog: every page, a range, or the pages ticked in
/// the sidebar. Page numbers start at 1.
public enum PageSelection: Equatable, Sendable {
    case all
    case range(from: Int, to: Int)
    case pages(Set<Int>)

    /// The runs to export: nil for every page, empty when nothing is chosen. A reversed range counts the right way round.
    public func spans(pageCount: Int) -> [PageSpan]? {
        let chosen: [Int]
        switch self {
        case .all: return nil
        case .range(let a, let b):
            let lo = max(1, min(a, b)), hi = min(pageCount, max(a, b))
            if lo == 1 && hi == pageCount { return nil }
            chosen = lo <= hi ? Array(lo...hi) : []
        case .pages(let set):
            chosen = set.filter { (1...pageCount).contains($0) }.sorted()
            if chosen.count == pageCount { return nil }
        }
        var spans: [PageSpan] = []
        for p in chosen {
            if let last = spans.last?.last, last + 1 == p { spans[spans.count - 1].last = p } else { spans.append(PageSpan(first: p, last: p)) }
        }
        return spans
    }
}
