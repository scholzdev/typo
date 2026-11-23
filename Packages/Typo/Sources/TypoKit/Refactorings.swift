import Foundation
import TypstEngine

/// One replacement of `range` by `snippet.text`; a snippet without placeholders is a plain replacement.
public struct Refactoring: Equatable, Sendable, Identifiable {
    public let title: String
    public let range: NSRange
    public let snippet: Snippet
    public var id: String { title }
}

/// Selection-based edits offered next to the diagnostic quick fixes, as pure functions of the text and its syntax.
enum Refactorings {
    static func available(in text: String, selection: NSRange, syntax: SyntaxMirror) -> [Refactoring] {
        let ns = text as NSString
        guard selection.location >= 0, NSMaxRange(selection) <= ns.length else { return [] }
        let spans = syntax.spans(in: NSRange(location: 0, length: ns.length))
        let equation = equation(around: selection, spans)
        return toggleEquation(ns, equation) + headings(ns, selection, spans) + extract(ns, selection, syntax, equation)
    }

    /// The innermost `$…$` around `sel`: the mathDelimiter spans are single `$`, paired in order of appearance.
    private static func equation(around sel: NSRange, _ spans: [SyntaxSpan]) -> NSRange? {
        let d = spans.filter { $0.tag == .mathDelimiter }.map(\.range)
        return stride(from: 0, to: d.count - 1, by: 2).reversed().lazy
            .map { NSRange(location: d[$0].location, length: NSMaxRange(d[$0 + 1]) - d[$0].location) }
            .first { $0.location <= sel.location && NSMaxRange(sel) <= NSMaxRange($0) }
    }

    private static func isSpace(_ u: unichar) -> Bool { u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D }

    private static func toggleEquation(_ ns: NSString, _ eq: NSRange?) -> [Refactoring] {
        guard let eq, eq.length > 2 else { return [] }
        let inner = ns.substring(with: NSRange(location: eq.location + 1, length: eq.length - 2))
        let body = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }
        let block = isSpace(ns.character(at: eq.location + 1)) && isSpace(ns.character(at: NSMaxRange(eq) - 2))
        let (title, text) = block ? ("Convert to Inline Equation", "$" + body + "$") : ("Convert to Block Equation", "$ " + body + " $")
        return [Refactoring(title: title, range: eq, snippet: Snippet(text: text, placeholders: []))]
    }

    private static func headings(_ ns: NSString, _ sel: NSRange, _ spans: [SyntaxSpan]) -> [Refactoring] {
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        guard let h = Folding.candidates(ns).first(where: { $0.marker >= line.location && $0.marker < NSMaxRange(line) }),
              spans.contains(where: { $0.tag == .heading && $0.range.location == h.marker }) else { return [] }
        let demote = Refactoring(title: "Demote Heading", range: NSRange(location: h.marker, length: 0), snippet: Snippet(text: "=", placeholders: []))
        let promote = Refactoring(title: "Promote Heading", range: NSRange(location: h.marker, length: 1), snippet: Snippet(text: "", placeholders: []))
        return h.level > 1 ? [promote, demote] : [demote]
    }

    // shortcut: no extraction in code mode, add when asked
    // shortcut: an unbalanced `]` in the selection breaks the `[..]`
    private static func extract(_ ns: NSString, _ sel: NSRange, _ syntax: SyntaxMirror, _ eq: NSRange?) -> [Refactoring] {
        guard sel.length > 0 else { return [] }
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let picked = ns.substring(with: sel)
        guard !picked.contains(where: \.isNewline) else { return [] }
        let mode = syntax.mode(at: sel.location)
        guard mode == .markup || mode == .math else { return [] }
        if mode == .math, let eq, eq.location < line.location { return [] }
        let head = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        let (open, close, ref) = mode == .math ? ("$", "$", "") : ("[", "]", "#")
        let prefix = "#let "
        // Text right after the selection would continue the name (`#namerest`, `#name.x`, `#name(`): end it explicitly.
        let next = NSMaxRange(sel) < ns.length ? Character(UnicodeScalar(ns.character(at: NSMaxRange(sel))) ?? " ") : " "
        let joins = next.isLetter || next.isNumber || "_-.([".contains(next)
        let end = !joins ? "" : mode == .math ? " " : ";"
        let text = "\(prefix)name = \(open)\(picked)\(close)\n\(head)\(ref)name\(end)"
        let first = NSRange(location: prefix.utf16.count, length: 4)
        let second = NSRange(location: (text as NSString).length - 4 - end.utf16.count, length: 4)
        return [Refactoring(title: "Extract to Variable", range: NSRange(location: line.location, length: NSMaxRange(sel) - line.location),
                            snippet: Snippet(text: text, placeholders: [first, second], groups: [1, 1]))]
    }
}
