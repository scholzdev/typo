import Foundation
import TypstEngine

public struct CompletionList: Sendable {
    public let file: RelPath
    public let from: Int            // UTF-16 start of the replaced range, valid at `seq`
    public let seq: Seq
    public let items: [CompletionItem]
}

/// An `apply` string with its tab stops resolved.
public struct Snippet: Equatable, Sendable {
    public let text: String
    public let placeholders: [NSRange]      // UTF-16, in order of appearance
    /// The group of each placeholder (parallel to `placeholders`): `N > 0` for `${N…}` (equal ids mirror each other),
    /// `0` for the exit point `${0}`, negative (-1, -2, … in order of appearance) for unnumbered `${}`/`${name}`.
    public var groups: [Int]

    /// `groups` defaults to one unnumbered group per placeholder.
    public init(text: String, placeholders: [NSRange], groups: [Int]? = nil) {
        self.text = text
        self.placeholders = placeholders
        self.groups = groups.flatMap { $0.count == placeholders.count ? $0 : nil } ?? placeholders.indices.map { -($0 + 1) }
    }

    /// `${}` is an empty stop, `${name}` inserts the name. `${N}` and `${N:default}` are numbered stops: equal `N` mirror each
    /// other (all take the first default given), `${0}` is the final caret position. Numbered stops are visited ascending, then
    /// the unnumbered ones, then the exit. A `$` not followed by `{` is literal, and so are braces anywhere else.
    public static func parse(_ apply: String) -> Snippet {
        var defaults: [Int: String] = [:]
        for m in apply.matches(of: /\$\{(\d+):([^}]*)\}/) {
            if let n = Int(m.output.1), !m.output.2.isEmpty, defaults[n] == nil { defaults[n] = String(m.output.2) }
        }
        var out = "", stops: [NSRange] = [], ids: [Int] = [], unnumbered = 0
        var rest = Substring(apply)
        while let ch = rest.first {
            if ch == "$", rest.dropFirst().first == "{", let close = rest.firstIndex(of: "}") {
                let body = rest[rest.index(rest.startIndex, offsetBy: 2)..<close]
                var name = body, id = 0, numbered = false
                let digits = body.prefix(while: \.isASCIIDigit)
                if let n = Int(digits) {
                    let after = body.dropFirst(digits.count)
                    if after.isEmpty || after.first == ":" {
                        numbered = true; id = n
                        let given = after.dropFirst()
                        name = given.isEmpty ? Substring(defaults[n] ?? "") : given
                    }
                }
                if !numbered { unnumbered += 1; id = -unnumbered }
                stops.append(NSRange(location: out.utf16.count, length: name.utf16.count))
                ids.append(id)
                out += name
                rest = rest[rest.index(after: close)...]
            } else {
                out.append(ch)
                rest = rest.dropFirst()
            }
        }
        return Snippet(text: out, placeholders: stops, groups: ids)
    }

    /// Group ids in visiting order: numbered ascending, then unnumbered by appearance. The exit (0) is not a stop.
    var order: [Int] {
        let ids = Set(groups.filter { $0 != 0 })
        return ids.filter { $0 > 0 }.sorted() + ids.filter { $0 < 0 }.sorted(by: >)
    }

    /// The stops in visiting order, each with all its (mirrored) ranges in text order.
    public var tabOrder: [[NSRange]] {
        order.map { id in placeholders.indices.filter { groups[$0] == id }.map { placeholders[$0] } }
    }

    /// The final caret position `${0}`, if any.
    public var exit: NSRange? {
        groups.firstIndex(of: 0).map { placeholders[$0] }
    }

    /// Where the selection goes after inserting `text` at `start`: the first stop in tab order, else the exit, else the end.
    public func selection(insertedAt start: Int) -> NSRange {
        guard let p = tabOrder.first?.first ?? exit else { return NSRange(location: start + text.utf16.count, length: 0) }
        return NSRange(location: start + p.location, length: p.length)
    }
}

extension CompletionList {
    /// Case-insensitive prefix matches first, then subsequence matches, each in typst-ide order.
    func filtered(by typed: String) -> [CompletionItem] {
        if typed.isEmpty { return items }
        let t = typed.lowercased()
        var prefix: [CompletionItem] = [], subseq: [CompletionItem] = []
        for item in items {
            let l = item.label.lowercased()
            if l.hasPrefix(t) { prefix.append(item) }
            else if Self.isSubsequence(t, of: l) { subseq.append(item) }
        }
        return prefix + subseq
    }

    private static func isSubsequence(_ t: String, of l: String) -> Bool {
        var it = l.makeIterator()
        return t.allSatisfy { c in while let x = it.next() { if x == c { return true } }; return false }
    }
}

private extension Character { var isASCIIDigit: Bool { isASCII && isNumber } }
