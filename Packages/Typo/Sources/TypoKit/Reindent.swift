import Foundation
import TypstEngine

/// Re-Indent and re-indent on paste: indentation from bracket depth, counted on real syntax tokens.
public enum Reindent {
    private static let openers: Set<unichar> = [0x28, 0x5B, 0x7B]          // ( [ {
    private static let closers: Set<unichar> = [0x29, 0x5D, 0x7D]

    private struct Line {
        var start = 0, first = 0, end = 0        // line start, first non-blank, end before the line break
        var old = 0                              // columns of the current indentation
        var scope = -1                           // offset of the innermost open bracket, -1 at the top level
        var markup = true                        // inside `[` or at the top level: indentation is meaningful to Typst
        var closer = false, solo = false, keep = false
        var comment: NSRange?                    // a comment starting on this line after its first character
    }

    /// Re-indents the lines `sel` reaches: one level per open bracket (one per line, however many it opens), a line
    /// starting with a closer back at its opener's line. Code lines get exactly that; markup lines (top level and
    /// inside `[`) move as a group and keep their offsets, because list nesting and continuations depend on them.
    /// Lines inside raw blocks, strings and block comments, and blank lines, are never touched. Nil when nothing changes.
    static func edits(in text: String, selection sel: NSRange, spans: [SyntaxSpan], settings: IndentSettings) -> (edits: [Replacement], selection: NSRange)? {
        let ns = text as NSString
        guard sel.location <= ns.length else { return nil }
        var brackets: [Int] = []
        var opaque: [(range: NSRange, tag: SyntaxTag)] = []
        for s in spans {
            switch s.tag {
            case .punctuation, .mathGroupingParens:
                for i in s.range.location..<NSMaxRange(s.range) where openers.contains(ns.character(at: i)) || closers.contains(ns.character(at: i)) {
                    brackets.append(i)
                }
            case .raw, .string, .comment:
                // A raw block arrives as one leaf per line: merge touching leaves so its inner line starts lie inside.
                if let last = opaque.last, last.tag == s.tag, NSMaxRange(last.range) == s.range.location {
                    opaque[opaque.count - 1].range.length += s.range.length
                } else { opaque.append((s.range, s.tag)) }
            default: break
            }
        }

        var lines: [Line] = [], openerLine: [Int: Int] = [:], stack: [Int] = []
        var bi = 0, oi = 0, pos = 0
        while true {
            let lr = ns.lineRange(for: NSRange(location: pos, length: 0))
            var l = Line(start: pos)
            l.end = NSMaxRange(lr)
            while l.end > pos, ns.character(at: l.end - 1) == 10 || ns.character(at: l.end - 1) == 13 { l.end -= 1 }
            let lead = Indent.leadingBlanks(ns, from: pos, to: l.end)
            l.first = pos + lead.utf16.count
            l.old = settings.columns(lead)
            l.scope = stack.last ?? -1
            l.markup = l.scope < 0 || ns.character(at: l.scope) == 0x5B
            while oi < opaque.count, NSMaxRange(opaque[oi].range) <= pos { oi += 1 }
            let inside = oi < opaque.count && opaque[oi].range.location < pos
            l.comment = opaque[oi...].prefix { $0.range.location < l.end }.first { $0.tag == .comment && $0.range.location >= l.first }?.range
            let commentOnly = l.comment?.location == l.first
            if commentOnly { l.comment = nil }
            l.keep = l.first == l.end || inside || (commentOnly && !settings.indentComments)
            let lineBrackets = brackets[bi...].prefix { $0 < l.end }
            l.closer = lineBrackets.first == l.first && closers.contains(ns.character(at: l.first))
            l.solo = l.end - l.first == 1 && lineBrackets.first == l.first && openers.contains(ns.character(at: l.first))
            for b in lineBrackets {
                if openers.contains(ns.character(at: b)) { stack.append(b); openerLine[b] = lines.count }
                else if !stack.isEmpty { stack.removeLast() }
            }
            bi += lineBrackets.count
            lines.append(l)
            let next = NSMaxRange(lr)
            if next == pos || (next == ns.length && ns.character(at: next - 1) != 10) { break }   // a final empty line still counts
            pos = next
        }

        let targets = Set(Indent.lineStarts(ns, sel))
        var base: [Int: Int] = [:]                              // least indented markup line per scope
        for l in lines where l.markup && !l.keep && !l.closer { base[l.scope] = min(base[l.scope] ?? .max, l.old) }
        var cols: [Int] = [], edits: [Replacement] = []
        for l in lines {
            guard targets.contains(l.start), !l.keep else { cols.append(l.old); continue }
            let open = l.scope < 0 ? nil : openerLine[l.scope].map { cols[$0] }
            var c: Int
            if l.closer { c = open ?? 0 } else {
                c = open.map { $0 + settings.levelWidth } ?? 0
                if l.markup { c += l.old - (base[l.scope] ?? l.old) }
                if l.solo { c += settings.soloBraceIndent }
            }
            cols.append(c)
            let new = settings.blanks(c), range = NSRange(location: l.start, length: l.first - l.start)
            if ns.substring(with: range) != new { edits.append(Replacement(range: range, text: new)) }
        }
        if settings.alignComments { edits += alignedComments(ns, lines, cols, targets, settings) }
        guard !edits.isEmpty else { return nil }
        edits.sort { $0.range.location < $1.range.location }
        func map(_ p: Int) -> Int {
            var d = 0
            for e in edits {
                if NSMaxRange(e.range) <= p { d += e.text.utf16.count - e.range.length }
                else if e.range.location < p { return e.range.location + d + min(p - e.range.location, e.text.utf16.count) }
                else { break }
            }
            return p + d
        }
        let a = map(sel.location)
        return (edits, NSRange(location: a, length: map(NSMaxRange(sel)) - a))
    }

    /// Trailing `//` comments on consecutive re-indented lines move to one column: one space after the longest code.
    private static func alignedComments(_ ns: NSString, _ lines: [Line], _ cols: [Int], _ targets: Set<Int>, _ settings: IndentSettings) -> [Replacement] {
        var out: [Replacement] = [], run: [(code: Int, col: Int, comment: Int)] = []
        func flush() {
            if run.count > 1, let to = run.map({ $0.col + 1 }).max() {
                for r in run {
                    let range = NSRange(location: r.code, length: r.comment - r.code), new = String(repeating: " ", count: to - r.col)
                    if ns.substring(with: range) != new { out.append(Replacement(range: range, text: new)) }
                }
            }
            run = []
        }
        for (i, l) in lines.enumerated() {
            guard targets.contains(l.start), !l.keep, let c = l.comment, ns.substring(with: c).hasPrefix("//") else { flush(); continue }
            var code = c.location
            while code > l.first, ns.character(at: code - 1) == 0x20 || ns.character(at: code - 1) == 0x09 { code -= 1 }
            run.append((code, cols[i] + settings.columns(ns.substring(with: NSRange(location: l.first, length: code - l.first))), c.location))
        }
        flush()
        return out
    }

    /// The text to paste instead of `pasted` at `range` so its lines sit at the insertion point's indentation, with
    /// their relative indentation kept. The first line lands after the caret and keeps its place; nil for a single line.
    public static func pasted(_ pasted: String, into text: String, at range: NSRange, settings: IndentSettings) -> String? {
        let lines = pasted.components(separatedBy: "\n")
        guard lines.count > 1 else { return nil }
        let ns = text as NSString
        let base = Indent.lineIndent(in: text, before: range.location)
        let lineStart = ns.lineRange(for: NSRange(location: min(range.location, ns.length), length: 0)).location
        let caretInLead = base.utf16.count == range.location - lineStart
        func lead(_ s: String) -> Substring { s.prefix { $0 == " " || $0 == "\t" } }
        func blank(_ s: String) -> Bool { s.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" } }
        // A first line copied with its indentation is part of the shape; one copied from mid-line is not.
        let shaped = lines.dropFirst().filter { !blank($0) } + (lead(lines[0]).isEmpty ? [] : [lines[0]])
        guard let least = shaped.map({ settings.columns(lead($0)) }).min() else { return nil }
        // Same rule as `IndentSettings.unit(for:)`: the insertion line's own style wins.
        var style = settings
        if !settings.explicitStyle, !base.isEmpty { style.useTabs = base.hasPrefix("\t") }
        let baseCols = settings.columns(base)
        let first = caretInLead ? String(lines[0].dropFirst(lead(lines[0]).count)) : lines[0]
        let rest = lines.dropFirst().map { l -> String in
            if blank(l) { return l.hasSuffix("\r") ? "\r" : "" }
            let l0 = lead(l)
            return style.blanks(baseCols + settings.columns(l0) - least) + l.dropFirst(l0.count)
        }
        return ([first] + rest).joined(separator: "\n")
    }
}
