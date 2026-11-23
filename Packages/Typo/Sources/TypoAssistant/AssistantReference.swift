import Foundation

/// Retrieval of Typst documentation for the identifiers a request mentions: the whole documentation does not fit into
/// a prompt, so only the signatures and summaries of the functions in the passage go in.
public enum AssistantReference {
    /// Reference text per request: hosted models get more than the on-device model.
    public static let hostedBudget = 8_000, onDeviceBudget = 1_200

    /// An identifier and where it first occurs in the file, which is where the engine is asked about it.
    public struct Candidate: Equatable, Sendable {
        public var name: String
        /// UTF-16 offset inside the identifier in the file text.
        public var offset: Int
    }

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var text: String
        public init(name: String, text: String) { self.name = name; self.text = text }
    }

    static let keywords: Set<String> = ["let", "set", "show", "if", "else", "for", "in", "while", "import", "include", "return", "context",
                                        "none", "auto", "true", "false", "and", "or", "not", "break", "continue", "as"]

    /// Identifiers to look up in `range` of `text`, most relevant first: names the question mentions, then by count, then by
    /// first use. Functions after `#` in markup, called names in code and math (`frac(`, `calc.pow(`).
    public static func candidates(in text: String, range: NSRange, question: String, limit: Int = 12) -> [Candidate] {
        let ns = text as NSString
        let passage = ns.substring(with: range)
        // `#name`, `#name.sub`, or `name(` / `name.sub(` anywhere (code, math).
        let pattern = try! NSRegularExpression(pattern: #"(?:#([A-Za-z][\w-]*(?:\.[A-Za-z][\w-]*)*))|(?<![\w.#-])([A-Za-z][\w]*(?:\.[A-Za-z]\w*)*)\("#)
        var count: [String: Int] = [:], first: [String: Int] = [:]
        for m in pattern.matches(in: passage, range: NSRange(location: 0, length: (passage as NSString).length)) {
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            let name = (passage as NSString).substring(with: r)
            guard !keywords.contains(name) else { continue }
            count[name, default: 0] += 1
            if first[name] == nil { first[name] = range.location + r.location + 1 }
        }
        let asked = Set(question.split { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }.map(String.init))
        return count.keys.sorted { a, b in
            let qa = asked.contains(a), qb = asked.contains(b)
            if qa != qb { return qa }
            if count[a]! != count[b]! { return count[a]! > count[b]! }
            return first[a]! < first[b]!
        }.prefix(limit).map { Candidate(name: $0, offset: first[$0]!) }
    }

    /// The entries that fit in `budget` characters, in order, under a heading; nil when none fits.
    public static func block(_ entries: [Entry], budget: Int) -> String? {
        let heading = "Typst reference:\n"
        var used = heading.count, parts: [String] = []
        for e in entries {
            let part = "\n" + e.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
            guard used + part.count <= budget else { continue }
            used += part.count
            parts.append(part)
        }
        return parts.isEmpty ? nil : heading + parts.joined()
    }

    /// One entry from a signature and a builtin's Markdown docs: the signature, then the first paragraph of the docs.
    public static func entry(name: String, signature: String?, docs: String?) -> Entry? {
        let summary = docs?.components(separatedBy: "\n\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = [signature.map { "```typst\n\($0)\n```" }, summary.isEmpty ? nil : String(summary.prefix(400))].compactMap { $0 }
        return parts.isEmpty ? nil : Entry(name: name, text: parts.joined(separator: "\n"))
    }
}
