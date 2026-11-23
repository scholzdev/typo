import Foundation
import TypstEngine

public enum PairAction: Equatable, Sendable {
    case none                                   // the text view handles the key itself
    case stepOver                               // the typed closer is swallowed, the caret moves right by one
    /// One replacement (one undo step), then the selection; `autoCloser` is the UTF-16 location of the
    /// closer this edit inserted on its own, if any.
    case edit(range: NSRange, replacement: String, selection: NSRange, autoCloser: Int?)
}

/// Auto-closing pairs as pure decisions. The editor executes the action.
public enum PairEdit {
    static let closers: Set<Character> = [")", "]", "}"]
    static let pairs: [Character: Character] = ["(": ")", "[": "]", "{": "}", "$": "$", "\"": "\""]

    /// `autoInserted` holds the locations of closers this editor inserted that are still unchanged.
    public static func decide(typed: String, text: String, selection: NSRange, mode: SyntaxMode,
                              autoInserted: Set<Int>, marked: Bool = false, enabled: Bool = true) -> PairAction {
        guard enabled, !marked, typed.count == 1, let c = typed.first else { return .none }
        let ns = text as NSString
        guard selection.location >= 0, NSMaxRange(selection) <= ns.length else { return .none }

        if selection.length == 0, autoInserted.contains(selection.location), selection.location < ns.length,
           ns.substring(with: NSRange(location: selection.location, length: 1)) == typed,
           closers.contains(c) || c == "$" || c == "\"" {
            return .stepOver
        }
        // A space inside a fresh `$|$` opens display math: `$ | $`.
        if c == " ", mode == .math, selection.length == 0, autoInserted.contains(selection.location),
           selection.location > 0, selection.location < ns.length,
           ns.substring(with: NSRange(location: selection.location - 1, length: 2)) == "$$" {
            return .edit(range: selection, replacement: "  ", selection: NSRange(location: selection.location + 1, length: 0),
                         autoCloser: selection.location + 2)
        }
        guard let closer = pairs[c] else { return .none }
        if c == "$", selection.location > 0, ns.substring(with: NSRange(location: selection.location - 1, length: 1)) == "\\" { return .none }   // `\$`
        switch c {
        case "$" where mode != .markup, "\"" where mode != .code && mode != .math: return .none
        default: break
        }
        if selection.length > 0 {
            let inner = ns.substring(with: selection)
            return .edit(range: selection, replacement: "\(c)\(inner)\(closer)",
                         selection: NSRange(location: selection.location + 1, length: selection.length), autoCloser: nil)
        }
        let next = selection.location < ns.length ? ns.substring(with: NSRange(location: selection.location, length: 1)) : nil
        guard next.map({ $0.allSatisfy { $0.isWhitespace || closers.contains($0) } }) ?? true else { return .none }
        return .edit(range: selection, replacement: "\(c)\(closer)",
                     selection: NSRange(location: selection.location + 1, length: 0), autoCloser: selection.location + 1)
    }

    /// Backspace with the caret between an auto-inserted, still empty pair deletes both characters.
    public static func decideBackspace(text: String, selection: NSRange, autoInserted: Set<Int>, marked: Bool = false, enabled: Bool = true) -> PairAction {
        let ns = text as NSString
        let p = selection.location
        guard enabled, !marked, selection.length == 0, p > 0, p < ns.length, autoInserted.contains(p),
              let open = ns.substring(with: NSRange(location: p - 1, length: 1)).first,
              pairs[open].map(String.init) == ns.substring(with: NSRange(location: p, length: 1)) else { return .none }
        return .edit(range: NSRange(location: p - 1, length: 2), replacement: "", selection: NSRange(location: p - 1, length: 0), autoCloser: nil)
    }

    /// Moves tracked closer locations through an edit of `pre` (pre-edit range) that left `newLength` characters there.
    static func shift(_ closers: Set<Int>, edit pre: NSRange, newLength: Int) -> Set<Int> {
        Set(closers.compactMap { p in
            if p < pre.location { return p }
            if p >= NSMaxRange(pre) { return p - pre.length + newLength }
            return nil
        })
    }
}
