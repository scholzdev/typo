import Foundation
import TypstEngine

/// The pages field of File › Export › PDF: "1-3, 7, 9-" as runs of pages.
public enum PageSelection {
    /// Nil for an empty field (every page); otherwise the runs, or a message saying what is wrong.
    /// Accepts single pages, `a-b`, open ends `a-` and `-b`, en dashes, and commas or spaces between items.
    public static func parse(_ text: String, pageCount: Int) -> Result<[PageSpan], Failure>? {
        let items = text.replacingOccurrences(of: "–", with: "-")
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isWhitespace })
        guard !items.isEmpty else { return nil }
        var spans: [PageSpan] = []
        for item in items {
            let parts = item.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            func page(_ s: Substring) -> Int?? {
                if s.isEmpty { return .some(nil) }
                guard let n = Int(s), n >= 1 else { return nil }
                return .some(n)
            }
            guard let first = page(parts[0]), let last = parts.count == 2 ? page(parts[1]) : first,
                  first != nil || last != nil else { return .failure(Failure(String(localized: "“\(item)” is not a page or a range of pages.", bundle: .module))) }
            if let f = first, let l = last, f > l { return .failure(Failure(String(localized: "“\(item)” runs backwards.", bundle: .module))) }
            if let p = [first, last].compactMap({ $0 }).first(where: { $0 > pageCount }) {
                return .failure(Failure(String(localized: "The document has \(pageCount) pages, so there is no page \(p).", bundle: .module)))
            }
            spans.append(PageSpan(first: first, last: last))
        }
        return .success(spans)
    }

    public struct Failure: Error, Equatable {
        public let message: String
        init(_ message: String) { self.message = message }
    }
}
