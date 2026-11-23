import Foundation
import TypstEngine

/// One replacement and the selection to set after it.
public struct TextEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
}

/// The editor's bottom-bar formatting as pure edits; the app applies one as a single undoable replacement.
public enum Formatting {
    public enum Command: Sendable { case bold, italic, underline, bulletList, numberedList, math }

    /// Nil when there is nothing to do.
    static func edit(_ c: Command, in text: String, selection: NSRange, syntax: SyntaxMirror) -> TextEdit? {
        switch c {
        case .bold: wrap(text, selection, syntax, kind: 0, markup: ("*", "*"), math: ("bold(", ")"), code: ("strong[", "]"))
        case .italic: wrap(text, selection, syntax, kind: 1, markup: ("_", "_"), math: ("italic(", ")"), code: ("emph[", "]"))
        case .underline: wrap(text, selection, syntax, kind: 2, markup: ("#underline[", "]"), math: ("underline(", ")"), code: ("underline[", "]"))
        case .bulletList: list(text, selection, marker: "-")
        case .numberedList: list(text, selection, marker: "+")
        case .math: math(text, selection)
        }
    }

    // MARK: Wrap

    /// The delimiters follow the mode at the selection start. Unwraps when the selection or caret is already
    /// inside that markup (found in the syntax tree; markup mode only, math and code just nest),
    /// otherwise wraps the selection, or inserts an empty pair with the caret inside.
    private static func wrap(_ text: String, _ sel: NSRange, _ syntax: SyntaxMirror, kind: UInt8,
                             markup: (String, String), math: (String, String), code: (String, String)) -> TextEdit? {
        let ns = text as NSString
        guard sel.location >= 0, NSMaxRange(sel) <= ns.length else { return nil }
        let mode = syntax.mode(at: sel.location)
        let (open, close) = mode == .math ? math : mode == .code ? code : markup
        let o = open.utf16.count, c = close.utf16.count
        if mode == .markup, let r = syntax.enclosing(kind: kind, sel) {
            let inner = NSRange(location: r.location + o, length: r.length - o - c)
            func clamp(_ p: Int) -> Int { r.location + min(max(p - r.location - o, 0), inner.length) }
            return TextEdit(range: r, replacement: ns.substring(with: inner),
                            selection: NSRange(location: clamp(sel.location), length: clamp(NSMaxRange(sel)) - clamp(sel.location)))
        }
        // Delimiters hug the text: markup does not bold a span that starts or ends with a space.
        var s = sel
        while s.length > 0, isSpace(ns.character(at: s.location)) { s.location += 1; s.length -= 1 }
        while s.length > 0, isSpace(ns.character(at: NSMaxRange(s) - 1)) { s.length -= 1 }
        if s.length == 0 {
            return TextEdit(range: NSRange(location: sel.location, length: 0), replacement: open + close,
                            selection: NSRange(location: sel.location + o, length: 0))
        }
        return TextEdit(range: s, replacement: open + ns.substring(with: s) + close, selection: NSRange(location: s.location + o, length: s.length))
    }

    private static func isSpace(_ u: unichar) -> Bool {
        u == 0x20 || u == 0x09 || u == 0x0A || u == 0x0D || u == 0xA0
    }

    // MARK: Lists

    private enum Marker { case none, bullet, numbered }

    /// Toggles `- ` (bullet) or `+ ` (numbered) on every selected non-blank line: all already that marker removes
    /// it, otherwise every line gets it, converting the other marker. A selection ending at a line start excludes that line.
    private static func list(_ text: String, _ sel: NSRange, marker: Character) -> TextEdit? {
        let ns = text as NSString
        guard sel.location >= 0, NSMaxRange(sel) <= ns.length else { return nil }
        let target: Marker = marker == "-" ? .bullet : .numbered
        var end = NSMaxRange(sel)
        if sel.length > 0, ns.character(at: end - 1) == 10 { end -= 1 }
        let block = ns.lineRange(for: NSRange(location: sel.location, length: end - sel.location))
        var body = ns.substring(with: block)
        let trailing = body.hasSuffix("\n")
        if trailing { body.removeLast() }

        struct Line { var indent: Int; var oldMarker: Int; var newMarker: Int; var oldStart: Int; var newStart: Int }
        var lines: [Line] = []
        var parts: [(indent: String, kind: Marker, rest: String)] = []
        for raw in body.components(separatedBy: "\n") {
            let indent = String(raw.prefix { $0 == " " || $0 == "\t" })
            let rest = String(raw.dropFirst(indent.count))
            let kind: Marker = rest == "-" || rest.hasPrefix("- ") ? .bullet : rest == "+" || rest.hasPrefix("+ ") ? .numbered : .none
            parts.append((indent, kind, rest))
        }
        let considered = parts.filter { !$0.rest.isEmpty }
        let remove = !considered.isEmpty && considered.allSatisfy { $0.kind == target }
        var out: [String] = []
        var oldStart = 0, newStart = 0
        for p in parts {
            var rest = p.rest
            var oldM = 0, newM = 0
            if p.kind != .none { oldM = rest.hasPrefix("- ") || rest.hasPrefix("+ ") ? 2 : 1 }
            if p.rest.isEmpty && parts.count > 1 {
                oldM = 0
            } else if remove {
                rest = String(rest.dropFirst(oldM))
            } else {
                rest = "\(marker) " + rest.dropFirst(oldM)
                newM = 2
            }
            let line = p.indent + rest
            lines.append(Line(indent: p.indent.utf16.count, oldMarker: oldM, newMarker: newM, oldStart: oldStart, newStart: newStart))
            out.append(line)
            oldStart += p.indent.utf16.count + p.rest.utf16.count + 1
            newStart += line.utf16.count + 1
        }
        func map(_ pos: Int) -> Int {
            let rel = min(max(pos - block.location, 0), body.utf16.count)
            let l = lines.last { $0.oldStart <= rel } ?? lines[0]
            let col = rel - l.oldStart
            if col < l.indent { return block.location + l.newStart + col }
            return block.location + l.newStart + l.indent + l.newMarker + max(0, col - l.indent - l.oldMarker)
        }
        let replacement = out.joined(separator: "\n") + (trailing ? "\n" : "")
        let a = map(sel.location), b = map(NSMaxRange(sel))
        return TextEdit(range: block, replacement: replacement, selection: NSRange(location: a, length: b - a))
    }

    // MARK: Math

    /// `$sel$`; an empty selection inserts `$|$`, or display-style `$ | $` on an empty line.
    private static func math(_ text: String, _ sel: NSRange) -> TextEdit? {
        let ns = text as NSString
        guard sel.location >= 0, NSMaxRange(sel) <= ns.length else { return nil }
        if sel.length > 0 {
            return TextEdit(range: sel, replacement: "$" + ns.substring(with: sel) + "$", selection: NSRange(location: sel.location + 1, length: sel.length))
        }
        let line = ns.substring(with: ns.lineRange(for: sel)).trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty
            ? TextEdit(range: sel, replacement: "$  $", selection: NSRange(location: sel.location + 2, length: 0))
            : TextEdit(range: sel, replacement: "$$", selection: NSRange(location: sel.location + 1, length: 0))
    }
}
