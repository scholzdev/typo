import Foundation

/// "@file" mentions in the prompt: the typed query, the files it matches, and where mentioned names stand in a message.
public enum AssistantMentions {
    /// The "@query" the caret ends, as a UTF-16 range (including "@") and the query; nil when the caret is not in one.
    /// The "@" starts the text or follows whitespace, and the query has no whitespace.
    public static func query(in text: String, caret: Int) -> (range: NSRange, query: String)? {
        let s = text as NSString
        guard caret <= s.length else { return nil }
        var i = caret
        while i > 0 {
            let c = s.character(at: i - 1)
            if c == 0x40 {    // "@"
                guard i == 1 || isSpace(s.character(at: i - 2)) else { return nil }
                return (NSRange(location: i - 1, length: caret - i + 1), s.substring(with: NSRange(location: i, length: caret - i)))
            }
            if isSpace(c) { return nil }
            i -= 1
        }
        return nil
    }

    private static func isSpace(_ c: unichar) -> Bool { Character(Unicode.Scalar(c) ?? " ").isWhitespace }

    /// The project paths whose file name matches `query`: names starting with it, then names containing it, then paths
    /// containing it, then names holding its letters in order; shorter names first within each.
    public static func matches(_ query: String, in paths: [String], limit: Int = 50) -> [String] {
        let q = query.lowercased()
        func rank(_ path: String) -> Int? {
            let name = (path as NSString).lastPathComponent.lowercased()
            if q.isEmpty || name.hasPrefix(q) { return 0 }
            if name.contains(q) { return 1 }
            if path.lowercased().contains(q) { return 2 }
            var rest = Substring(q)
            for ch in name where ch == rest.first { rest = rest.dropFirst() }
            return rest.isEmpty ? 3 : nil
        }
        return paths.compactMap { p in rank(p).map { (p, $0) } }
            .sorted { a, b in
                let na = (a.0 as NSString).lastPathComponent, nb = (b.0 as NSString).lastPathComponent
                return (a.1, na.count, a.0) < (b.1, nb.count, b.0)
            }
            .prefix(limit).map(\.0)
    }

    /// Where the file names of `paths` stand in `text` as whole words, without overlaps, in order.
    public static func ranges(of paths: [String], in text: String) -> [Range<String.Index>] {
        let names = Set(paths.map { ($0 as NSString).lastPathComponent }).filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        var out: [Range<String.Index>] = []
        for name in names {
            var from = text.startIndex
            while let r = text.range(of: name, range: from..<text.endIndex) {
                from = r.upperBound
                let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
                let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
                guard !isWordy(before), !isWordy(after), !out.contains(where: { $0.overlaps(r) }) else { continue }
                out.append(r)
            }
        }
        return out.sorted { $0.lowerBound < $1.lowerBound }
    }

    private static func isWordy(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false }
}

/// An agent's "/" entry: a built-in command, or a skill (its description names its source in parentheses).
public enum AssistantCommandKind: Equatable, Sendable {
    case command, skill

    /// The kind and the description without its source: "… (user)", "… (project)" at the end, or "(plugin) …" at the start.
    public static func classify(_ description: String) -> (kind: AssistantCommandKind, description: String) {
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.hasSuffix(")"), let open = matching(Array(d.reversed()), open: ")", close: "(") {
            let rest = String(d.dropLast(open + 1)).trimmingCharacters(in: .whitespaces)
            return (.skill, rest)
        }
        if d.hasPrefix("("), let close = matching(Array(d), open: "(", close: ")") {
            let rest = String(d.dropFirst(close + 1)).trimmingCharacters(in: .whitespaces)
            return (.skill, rest)
        }
        return (.command, d)
    }

    /// The offset of the bracket closing the one at offset 0, counting nested pairs.
    private static func matching(_ chars: [Character], open: Character, close: Character) -> Int? {
        var depth = 0
        for (i, c) in chars.enumerated() {
            if c == open { depth += 1 } else if c == close { depth -= 1; if depth == 0 { return i } }
        }
        return nil
    }
}
