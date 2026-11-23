import Foundation
import TypstEngine

/// Indentation rules shared by Enter, Tab / Shift-Tab, snippet insertion and table rendering.
public enum Indent {
    /// The blanks at the start of the line holding `location`, cut off at `location` itself.
    public static func lineIndent(in text: String, before location: Int) -> String {
        let ns = text as NSString
        let location = min(max(location, 0), ns.length)
        let start = ns.lineRange(for: NSRange(location: location, length: 0)).location
        return leadingBlanks(ns, from: start, to: location)
    }

    static func leadingBlanks(_ ns: NSString, from start: Int, to end: Int) -> String {
        var i = start
        while i < end, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        return ns.substring(with: NSRange(location: start, length: i - start))
    }

    static func isListLine(_ line: String) -> Bool {
        line.firstMatch(of: /^\s*(?:[-+]|\d+\.|\/)(?:\s|$)/) != nil
    }

    // MARK: Enter

    /// Enter: the new line keeps the indentation of the current one, one level deeper after an opening bracket.
    /// Between a bracket and its closer the closer moves to a line of its own. Text-like modes (strings, raw, comments)
    /// only keep the indentation, and so does every mode when "indent when typing" is off.
    public static func newline(in text: String, selection sel: NSRange, mode: SyntaxMode, settings: IndentSettings = .standard) -> TextEdit {
        let ns = text as NSString
        let sel = NSRange(location: min(sel.location, ns.length), length: min(sel.length, ns.length - min(sel.location, ns.length)))
        let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
        let indent = leadingBlanks(ns, from: lineStart, to: sel.location)
        // Only blanks before the caret: they are replaced rather than left behind as trailing whitespace.
        let blankBefore = indent.utf16.count == sel.location - lineStart
        let start = blankBefore ? lineStart : sel.location
        let end = NSMaxRange(sel)

        let before = sel.location > lineStart ? ns.character(at: sel.location - 1) : 0
        let after = end < ns.length ? ns.character(at: end) : 0
        let closers: [unichar: unichar] = [0x5B: 0x5D, 0x28: 0x29, 0x7B: 0x7D]
        guard settings.indentWhenTyping, mode != .text, let closer = closers[before] else {
            let r = "\n" + indent
            return TextEdit(range: NSRange(location: start, length: end - start), replacement: r,
                            selection: NSRange(location: start + r.utf16.count, length: 0))
        }
        // `before` is a bracket, so the caret is not in the line's leading blanks: `start` is the caret.
        let inner = "\n" + indent + settings.unit(for: indent)
        let split = after == closer ? "\n" + indent : ""
        return TextEdit(range: NSRange(location: start, length: end - start), replacement: inner + split,
                        selection: NSRange(location: start + inner.utf16.count, length: 0))
    }

    // MARK: Backspace

    /// Backspace in space indentation: removes back to the previous level (indent width), the counterpart of Tab.
    /// Nil elsewhere (a selection, text before the caret, a tab before it): the normal single-character delete.
    public static func backspace(in text: String, selection sel: NSRange, settings: IndentSettings = .standard) -> TextEdit? {
        let ns = text as NSString
        guard sel.length == 0, sel.location > 0, sel.location <= ns.length else { return nil }
        let lineStart = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
        let col = sel.location - lineStart
        guard col > 0, ns.substring(with: NSRange(location: lineStart, length: col)).allSatisfy({ $0 == " " }) else { return nil }
        let w = settings.indentWidth
        let n = col % w == 0 ? w : col % w
        return TextEdit(range: NSRange(location: sel.location - n, length: n), replacement: "",
                        selection: NSRange(location: sel.location - n, length: 0))
    }

    // MARK: Tab and Shift-Tab

    /// Line starts a Tab / Shift-Tab reaches: every line of the selection, without a last line the selection only touches.
    static func lineStarts(_ ns: NSString, _ sel: NSRange) -> [Int] {
        var end = NSMaxRange(sel)
        if sel.length > 0, end > sel.location, ns.character(at: end - 1) == 10 || ns.character(at: end - 1) == 13 { end -= 1 }
        var starts: [Int] = []
        var pos = ns.lineRange(for: NSRange(location: sel.location, length: 0)).location
        while true {
            starts.append(pos)
            let next = NSMaxRange(ns.lineRange(for: NSRange(location: pos, length: 0)))
            if next > end || next >= ns.length || next == pos { break }
            pos = next
        }
        return starts
    }

    /// True when Tab / Shift-Tab changes indentation instead of jumping: a multi-line selection, a caret in the
    /// indentation (including column 0) or a list item, whose Tab nests it from anywhere on the line.
    static func shifts(_ ns: NSString, _ sel: NSRange) -> Bool {
        guard sel.location <= ns.length else { return false }
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        if lineStarts(ns, sel).count > 1 { return true }
        let col = sel.location - line.location
        if leadingBlanks(ns, from: line.location, to: sel.location).utf16.count == col { return true }
        return isListLine(ns.substring(with: line))
    }

    /// Where a position moves when `edits` (start, inserted length) are applied; a caret at an insertion follows it.
    private static func mapped(_ p: Int, _ edits: [(start: Int, delta: Int)], deleting: Bool) -> Int {
        edits.reduce(p) { acc, e in
            if deleting { return acc + (e.start < p ? -min(-e.delta, p - e.start) : 0) }
            return acc + (e.start <= p ? e.delta : 0)
        }
    }

    /// Tab after snippet stops and argument jumps declined, by the Tab key setting. Nil leaves the key to the text
    /// view (a literal tab). Shift-Tab is the same in every mode (see `outdent`), so jumping back keeps its priority.
    static func tab(in text: String, from sel: NSRange, settings: IndentSettings) -> (edits: [Replacement], selection: NSRange)? {
        let ns = text as NSString
        switch settings.tabKey {
        case .leadingWhitespace: return indent(in: text, from: sel, settings: settings)
        case .always: return indent(in: text, from: sel, settings: settings, anywhere: true)
        case .insertsTab:
            if sel.location <= ns.length, lineStarts(ns, sel).count > 1 { return indent(in: text, from: sel, settings: settings) }
            let lineStart = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0)).location
            let col = settings.columns(ns.substring(with: NSRange(location: lineStart, length: min(sel.location, ns.length) - lineStart)))
            let s = settings.useTabs ? "\t" : String(repeating: " ", count: settings.indentWidth - col % settings.indentWidth)
            return ([Replacement(range: sel, text: s)], NSRange(location: sel.location + s.utf16.count, length: 0))
        }
    }

    /// Tab where it nests: one level in front of every line reached. Nil when Tab should do something else.
    /// `anywhere` nests the caret's line wherever the caret is ("Indents always").
    static func indent(in text: String, from sel: NSRange, settings: IndentSettings = .standard, anywhere: Bool = false) -> (edits: [Replacement], selection: NSRange)? {
        let ns = text as NSString
        guard sel.location <= ns.length, anywhere || shifts(ns, sel) else { return nil }
        let starts = lineStarts(ns, sel)
        var edits: [Replacement] = [], deltas: [(start: Int, delta: Int)] = []
        for s in starts {
            let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: s, length: 0)))
            let blank = ns.substring(with: NSRange(location: s, length: lineEnd - s)).allSatisfy(\.isWhitespace)
            if blank && starts.count > 1 { continue }               // no trailing blanks on empty lines of a block
            let unit = settings.unit(for: leadingBlanks(ns, from: s, to: lineEnd))
            edits.append(Replacement(range: NSRange(location: s, length: 0), text: unit))
            deltas.append((s, unit.utf16.count))
        }
        guard !edits.isEmpty else { return nil }
        // A selection starts before the indentation added at its first line; a caret follows it.
        let a = mapped(sel.location, sel.length == 0 ? deltas : deltas.filter { $0.start < sel.location }, deleting: false)
        let b = mapped(NSMaxRange(sel), deltas.filter { sel.length == 0 || $0.start < NSMaxRange(sel) }, deleting: false)
        return (edits, NSRange(location: a, length: b - a))
    }

    /// Shift-Tab: removes one level (a tab, or up to indent-width spaces) from every line reached. Nil when nothing
    /// applies. `anywhere` is the "Indents always" fallback once a jump back declined.
    static func outdent(in text: String, from sel: NSRange, settings: IndentSettings = .standard, anywhere: Bool = false) -> (edits: [Replacement], selection: NSRange)? {
        let ns = text as NSString
        guard sel.location <= ns.length, anywhere || shifts(ns, sel) else { return nil }
        var edits: [Replacement] = [], deltas: [(start: Int, delta: Int)] = []
        for s in lineStarts(ns, sel) where s < ns.length {
            let n: Int
            if ns.character(at: s) == 0x09 { n = 1 }
            else { n = (0..<settings.indentWidth).prefix { s + $0 < ns.length && ns.character(at: s + $0) == 0x20 }.count }
            guard n > 0 else { continue }
            edits.append(Replacement(range: NSRange(location: s, length: n), text: ""))
            deltas.append((s, -n))
        }
        guard !edits.isEmpty else { return nil }
        let a = mapped(sel.location, deltas, deleting: true)
        let b = mapped(NSMaxRange(sel), deltas, deleting: true)
        return (edits, NSRange(location: a, length: b - a))
    }
}

extension Snippet {
    /// The snippet for a line indented by `indent`: every line after the first gets the indentation, so a multi-line
    /// snippet keeps its shape wherever it is inserted. Empty lines stay empty.
    public func indented(by indent: String) -> Snippet {
        guard !indent.isEmpty, text.contains("\n") else { return self }
        let units = Array(text.utf16), add = Array(indent.utf16)
        var out: [UInt16] = [], map = [Int](repeating: 0, count: units.count + 1)
        for (i, u) in units.enumerated() {
            map[i] = out.count
            out.append(u)
            if u == 10, i + 1 < units.count, units[i + 1] != 10 { out += add }
        }
        map[units.count] = out.count
        let stops = placeholders.map { NSRange(location: map[$0.location], length: map[$0.location + $0.length] - map[$0.location]) }
        return Snippet(text: String(decoding: out, as: UTF16.self), placeholders: stops, groups: groups)
    }
}
