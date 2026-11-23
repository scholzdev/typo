import CoreGraphics
import Foundation
import TypstEngine

/// Pure helpers behind the editor visuals (DESIGN 12.1); the app only draws what these decide.

public enum CompletionBadge {
    public enum Tint: Sendable, Equatable { case blue, purple, orange, green, teal, pink, indigo, brown, gray }

    /// The badge letter(s); nil for symbols, which show their glyph.
    public static func letters(for kind: CompletionKind) -> String? {
        switch kind {
        case .function: "F"
        case .label: "L"
        case .parameter: "P"
        case .type: "T"
        case .constant: "C"
        case .syntax: "K"
        case .path: "Pa"
        case .package: "Pk"
        case .font: "Fo"
        case .symbol: nil
        }
    }

    public static func tint(for kind: CompletionKind) -> Tint {
        switch kind {
        case .function: .purple
        case .label: .orange
        case .parameter: .blue
        case .type: .green
        case .constant: .teal
        case .syntax: .pink
        case .path: .gray
        case .package: .brown
        case .font: .indigo
        case .symbol: .gray
        }
    }
}

public enum CompletionMatch {
    /// Character offsets in `label` that `typed` matches, using the rule of `Project.live`: a
    /// case-insensitive prefix, else the first greedy subsequence. Empty when nothing matches.
    public static func indices(of typed: String, in label: String) -> [Int] {
        let t = Array(typed.lowercased()), l = Array(label.lowercased())
        guard !t.isEmpty, l.count == label.count else { return [] }   // lowercasing that changes the length would shift offsets
        if l.starts(with: t) { return Array(0..<t.count) }
        var out: [Int] = [], next = 0
        for (i, c) in l.enumerated() where next < t.count && c == t[next] { out.append(i); next += 1 }
        return next == t.count ? out : []
    }
}

public struct LinePill: Equatable, Sendable {
    public let line: Int
    public let error: Bool          // the shown message is an error (errors sort first)
    public let message: String      // first line of the message
    public let more: Int            // further diagnostics on the line
}

public enum PillLayout {
    /// One pill per line: the first diagnostic (errors before warnings, then input order) plus the count of the others.
    public static func pills(_ items: [(line: Int, error: Bool, message: String)]) -> [LinePill] {
        var byLine: [Int: [(error: Bool, message: String)]] = [:]
        for i in items { byLine[i.line, default: []].append((i.error, i.message)) }
        return byLine.keys.sorted().map { line in
            let all = byLine[line]!
            let first = all.first(where: \.error) ?? all[0]
            let text = first.message.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? first.message
            return LinePill(line: line, error: first.error, message: text, more: all.count - 1)
        }
    }

    /// The pill text cut to `width` with an ellipsis; the "+N" suffix is kept. Nil if not even one character fits.
    public static func text(_ pill: LinePill, fitting width: CGFloat, measure: (String) -> CGFloat) -> String? {
        let suffix = pill.more > 0 ? "  +\(pill.more)" : ""
        let full = pill.message + suffix
        if measure(full) <= width { return full }
        let chars = Array(pill.message)
        var n = chars.count - 1
        while n > 0 {
            let candidate = String(chars[..<n]) + "…" + suffix
            if measure(candidate) <= width { return candidate }
            n -= 1
        }
        return nil
    }
}

public enum SelectionShape {
    /// Merges segments that sit on the same line (equal vertical extent) into one rect, in top-to-bottom order.
    public static func lineRects(_ segments: [CGRect]) -> [CGRect] {
        var out: [CGRect] = []
        for s in segments.sorted(by: { ($0.minY, $0.minX) < ($1.minY, $1.minX) }) where s.width > 0 || s.height > 0 {
            if let last = out.last, abs(last.minY - s.minY) < 0.5, abs(last.height - s.height) < 0.5 {
                out[out.count - 1] = last.union(s)
            } else {
                out.append(s)
            }
        }
        return out
    }
}
