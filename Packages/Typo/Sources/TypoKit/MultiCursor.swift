import Foundation
import TypstEngine

/// Multiple cursors as pure logic over UTF-16 ranges: merging, next-occurrence search, column selections,
/// per-cursor movement and the edit fan-out. The editor keeps the ranges and applies the results.
public enum MultiCursor {
    /// A selection that remembers its anchor, so Shift-extend keeps going the way it was going.
    public struct Sel: Equatable, Sendable {
        public var anchor: Int
        public var head: Int
        public init(anchor: Int, head: Int) { self.anchor = anchor; self.head = head }
        public init(_ r: NSRange) { anchor = r.location; head = NSMaxRange(r) }
        public var range: NSRange { NSRange(location: min(anchor, head), length: abs(head - anchor)) }
    }

    // MARK: Merging

    /// Sorted, with overlapping ranges and ranges starting at the same place joined (identical carets become one).
    public static func merge(_ ranges: [NSRange]) -> [NSRange] {
        var out: [NSRange] = []
        for r in ranges.sorted(by: { ($0.location, $0.length) < ($1.location, $1.length) }) {
            if let last = out.last, r.location < NSMaxRange(last) || r.location == last.location {
                out[out.count - 1] = NSRange(location: last.location, length: max(NSMaxRange(last), NSMaxRange(r)) - last.location)
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// `merge` for selections; a joined group becomes one selection over the union, a lone one keeps its anchor.
    public static func merge(_ sels: [Sel]) -> [Sel] {
        var out: [Sel] = []
        for s in sels.sorted(by: { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }) {
            if let last = out.last, s.range.location < NSMaxRange(last.range) || s.range.location == last.range.location {
                let r = merge([last.range, s.range])[0]
                out[out.count - 1] = Sel(r)
            } else {
                out.append(s)
            }
        }
        return out
    }

    // MARK: Occurrences

    static func isWord(_ c: unichar) -> Bool {
        c == 0x5F || (Unicode.Scalar(c).map { CharacterSet.alphanumerics.contains($0) } ?? false)
    }

    /// The identifier-like word touching `offset`.
    public static func wordRange(in text: NSString, at offset: Int) -> NSRange? {
        var lo = min(offset, text.length), hi = lo
        while lo > 0, isWord(text.character(at: lo - 1)) { lo -= 1 }
        while hi < text.length, isWord(text.character(at: hi)) { hi += 1 }
        return hi > lo ? NSRange(location: lo, length: hi - lo) : nil
    }

    static func occurrences(of needle: String, in text: NSString) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        var out: [NSRange] = []
        var from = 0
        while from < text.length {
            let r = text.range(of: needle, range: NSRange(location: from, length: text.length - from))
            if r.location == NSNotFound { break }
            out.append(r)
            from = NSMaxRange(r)
        }
        return out
    }

    /// Cmd-D. With a caret in a word, selects that word; with a selection, adds the next match after the primary
    /// (wrapping), skipping matches already selected. Nil when there is nothing to add.
    public static func selectNext(in text: NSString, selected: [NSRange], primary: NSRange) -> (ranges: [NSRange], primary: NSRange)? {
        if primary.length == 0 {
            guard let w = wordRange(in: text, at: primary.location) else { return nil }
            return (merge(selected.filter { $0 != primary } + [w]), w)
        }
        let hits = occurrences(of: text.substring(with: primary), in: text).filter { h in
            !selected.contains { NSIntersectionRange($0, h).length > 0 || $0 == h }
        }
        guard let hit = hits.first(where: { $0.location >= NSMaxRange(primary) }) ?? hits.first else { return nil }
        return (merge(selected + [hit]), hit)
    }

    /// Ctrl-Cmd-G: every match of the primary selection (or of the word at the caret) becomes a selection.
    public static func selectAll(in text: NSString, selected: [NSRange], primary: NSRange) -> (ranges: [NSRange], primary: NSRange)? {
        guard let target = primary.length > 0 ? primary : wordRange(in: text, at: primary.location) else { return nil }
        let hits = occurrences(of: text.substring(with: target), in: text)
        guard !hits.isEmpty else { return nil }
        return (merge(selected.filter { $0.length > 0 } + hits), hits.first { $0.location >= target.location } ?? hits[0])
    }

    // MARK: Lines and columns

    /// The line holding `offset`: its start, where its text ends (before the newline) and where the next line starts.
    static func line(_ text: NSString, _ offset: Int) -> (start: Int, end: Int, next: Int) {
        var s = 0, e = 0, ce = 0
        text.getLineStart(&s, end: &e, contentsEnd: &ce, for: NSRange(location: min(offset, text.length), length: 0))
        return (s, ce, e)
    }

    /// Option-drag: one range per line between the two offsets, between their columns (clamped to short lines).
    public static func column(in text: NSString, from a: Int, to b: Int) -> [NSRange] {
        let la = line(text, a), lb = line(text, b)
        let c0 = min(a - la.start, b - lb.start), c1 = max(a - la.start, b - lb.start)
        var out: [NSRange] = []
        var l = line(text, min(a, b))
        let last = max(la.start, lb.start)
        while true {
            let len = l.end - l.start
            out.append(NSRange(location: l.start + min(c0, len), length: min(c1, len) - min(c0, len)))
            if l.start >= last || l.next >= text.length && l.next == l.end { break }
            if l.next == l.start { break }
            l = line(text, l.next)
        }
        return out
    }

    /// Ctrl-Shift-Up/Down: the offset on the neighbouring line at the same column, if there is such a line.
    public static func caretOnAdjacentLine(in text: NSString, from head: Int, up: Bool) -> Int? {
        let l = line(text, head)
        let col = head - l.start
        let target: (start: Int, end: Int, next: Int)
        if up {
            guard l.start > 0 else { return nil }
            target = line(text, l.start - 1)
        } else {
            guard l.next > l.end else { return nil }       // no newline: last line
            target = line(text, l.next)
        }
        return target.start + min(col, target.end - target.start)
    }

    // MARK: Movement

    public enum Move: Sendable { case left, right, up, down, wordLeft, wordRight, lineStart, lineEnd, docStart, docEnd }

    static func target(_ m: Move, from head: Int, in text: NSString) -> Int {
        switch m {
        case .left: return head > 0 ? text.rangeOfComposedCharacterSequence(at: head - 1).location : 0
        case .right: return head < text.length ? NSMaxRange(text.rangeOfComposedCharacterSequence(at: head)) : text.length
        case .up:
            let l = line(text, head)
            return caretOnAdjacentLine(in: text, from: head, up: true) ?? (l.start == 0 ? 0 : head)
        case .down:
            return caretOnAdjacentLine(in: text, from: head, up: false) ?? text.length
        case .wordLeft:
            var i = head
            while i > 0, !isWord(text.character(at: i - 1)) { i -= 1 }
            while i > 0, isWord(text.character(at: i - 1)) { i -= 1 }
            return i
        case .wordRight:
            var i = head
            while i < text.length, !isWord(text.character(at: i)) { i += 1 }
            while i < text.length, isWord(text.character(at: i)) { i += 1 }
            return i
        case .lineStart: return line(text, head).start
        case .lineEnd: return line(text, head).end
        case .docStart: return 0
        case .docEnd: return text.length
        }
    }

    /// Moves every selection by `m`; with `extend` the anchors stay. A plain Left/Right over a selection collapses to its edge.
    public static func move(_ sels: [Sel], in text: NSString, _ m: Move, extend: Bool) -> [Sel] {
        merge(sels.map { s in
            if !extend, s.anchor != s.head, m == .left || m == .right {
                let p = m == .left ? s.range.location : NSMaxRange(s.range)
                return Sel(anchor: p, head: p)
            }
            let h = target(m, from: min(s.head, text.length), in: text)
            return Sel(anchor: extend ? min(s.anchor, text.length) : h, head: h)
        })
    }

    // MARK: Edits

    /// One cursor's edit: replace `range` with `text`; `caret` is where the cursor ends, in the text after this edit alone.
    public struct Edit: Sendable {
        public var range: NSRange, text: String, caret: NSRange
        public init(range: NSRange, text: String, caret: NSRange) { self.range = range; self.text = text; self.caret = caret }
    }

    /// Asks `make` for each range (ascending; nil leaves it alone) and returns the replacements for
    /// `Buffer.apply` with the cursors after all of them. An edit that reaches into the previous one is dropped.
    public static func fanOut(_ ranges: [NSRange], _ make: (NSRange) -> Edit?) -> (edits: [Replacement], ranges: [NSRange]) {
        var edits: [Replacement] = [], out: [NSRange] = []
        var shift = 0, lastEnd = 0
        for r in merge(ranges) {
            guard let e = make(r), e.range.location >= lastEnd else { out.append(NSRange(location: r.location + shift, length: r.length)); continue }
            edits.append(Replacement(range: e.range, text: e.text))
            out.append(NSRange(location: e.caret.location + shift, length: e.caret.length))
            shift += (e.text as NSString).length - e.range.length
            lastEnd = NSMaxRange(e.range)
        }
        return (edits, merge(out))
    }

    /// Typing: `s` replaces every selection and the cursors land after it.
    public static func insert(_ s: String, at ranges: [NSRange]) -> (edits: [Replacement], ranges: [NSRange]) {
        let n = (s as NSString).length
        return fanOut(ranges) { Edit(range: $0, text: s, caret: NSRange(location: $0.location + n, length: 0)) }
    }

    /// Delete: a selection goes whole; a caret takes the character (or word) before or after it.
    public static func delete(in text: NSString, at ranges: [NSRange], forward: Bool, word: Bool = false,
                              backspace: (NSRange) -> Edit? = { _ in nil }) -> (edits: [Replacement], ranges: [NSRange]) {
        fanOut(ranges) { r in
            if r.length == 0, !forward, !word, let e = backspace(r) { return e }
            var d = r
            if r.length == 0 {
                let lo = forward ? r.location : target(word ? .wordLeft : .left, from: r.location, in: text)
                let hi = forward ? target(word ? .wordRight : .right, from: r.location, in: text) : r.location
                d = NSRange(location: lo, length: hi - lo)
            }
            return Edit(range: d, text: "", caret: NSRange(location: d.location, length: 0))
        }
    }

    /// Cmd-Backspace / Ctrl-K: a selection goes whole; a caret takes everything to its line's start (`forward` false) or
    /// end. Ctrl-K at a line's end takes the newline, as in the text view.
    public static func deleteToLineEdge(in text: NSString, at ranges: [NSRange], forward: Bool) -> (edits: [Replacement], ranges: [NSRange]) {
        fanOut(ranges) { r in
            var d = r
            if r.length == 0 {
                var to = target(forward ? .lineEnd : .lineStart, from: r.location, in: text)
                if forward, to == r.location { to = target(.right, from: r.location, in: text) }
                d = NSRange(location: min(r.location, to), length: abs(to - r.location))
            }
            return Edit(range: d, text: "", caret: NSRange(location: d.location, length: 0))
        }
    }

    /// Ctrl-T: swaps the characters around each caret (the two before it at a line's end). Selections and carets at a
    /// line's start are left alone.
    public static func transpose(in text: NSString, at ranges: [NSRange]) -> (edits: [Replacement], ranges: [NSRange]) {
        fanOut(ranges) { r in
            guard r.length == 0 else { return nil }
            let l = line(text, r.location)
            guard r.location > l.start else { return nil }
            let atEnd = r.location >= l.end
            let mid = atEnd ? text.rangeOfComposedCharacterSequence(at: r.location - 1).location : r.location
            guard mid > l.start, mid < text.length else { return nil }
            let a = text.rangeOfComposedCharacterSequence(at: mid - 1), b = text.rangeOfComposedCharacterSequence(at: mid)
            let all = NSRange(location: a.location, length: NSMaxRange(b) - a.location)
            let swapped = text.substring(with: b) + text.substring(with: a)
            return Edit(range: all, text: swapped, caret: NSRange(location: NSMaxRange(all), length: 0))
        }
    }

    /// Shift-Tab: removes one level (a tab, or up to `width` spaces) from every line any cursor reaches, once per line.
    public static func outdent(in text: NSString, at ranges: [NSRange], width: Int) -> (edits: [Replacement], ranges: [NSRange]) {
        var starts: [Int] = []
        for r in merge(ranges) {
            var l = line(text, r.location)
            let last = line(text, r.length > 0 ? NSMaxRange(r) - 1 : r.location).start
            while true {
                if starts.last != l.start { starts.append(l.start) }
                if l.start >= last || l.next >= text.length { break }
                l = line(text, l.next)
            }
        }
        var cuts: [(start: Int, n: Int)] = []
        for s in starts where s < text.length {
            let n = text.character(at: s) == 0x09 ? 1 : (0..<width).prefix { s + $0 < text.length && text.character(at: s + $0) == 0x20 }.count
            if n > 0 { cuts.append((s, n)) }
        }
        func mapped(_ p: Int) -> Int { p - cuts.reduce(0) { $0 + min($1.n, max(0, p - $1.start)) } }
        let out = merge(ranges).map { r in NSRange(location: mapped(r.location), length: mapped(NSMaxRange(r)) - mapped(r.location)) }
        return (cuts.map { Replacement(range: NSRange(location: $0.start, length: $0.n), text: "") }, out)
    }

    /// Typing `s` at every cursor, each deciding for itself (`decide` is the editor's single-caret pairing decision,
    /// run against the text as it is now): wrapping a selection, closing a pair, stepping over a closer, or plain
    /// insertion. `closers` are the final locations of the closers this inserted on its own.
    public static func typed(_ s: String, at ranges: [NSRange], decide: (NSRange) -> PairAction) -> (edits: [Replacement], ranges: [NSRange], closers: [Int]) {
        var autoIndex: [Int] = [], i = 0
        let n = (s as NSString).length
        let r = fanOut(ranges) { r in
            defer { i += 1 }
            switch decide(r) {
            case .none: return Edit(range: r, text: s, caret: NSRange(location: r.location + n, length: 0))
            case .stepOver: return Edit(range: NSRange(location: r.location, length: 0), text: "", caret: NSRange(location: r.location + 1, length: 0))
            case .edit(let range, let text, let sel, let closer):
                if closer != nil { autoIndex.append(i) }
                return Edit(range: range, text: text, caret: sel)
            }
        }
        let closers = r.ranges.count == i ? autoIndex.map { r.ranges[$0].location } : []
        return (r.edits, r.ranges, closers)
    }

    /// Paste: one pasteboard line per cursor when the counts match, else all of it at each cursor.
    public static func pieces(of s: String, count: Int) -> [String] {
        var lines = s.components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines.count == count && count > 1 ? lines : Array(repeating: s, count: count)
    }

    public static func paste(_ s: String, at ranges: [NSRange]) -> (edits: [Replacement], ranges: [NSRange]) {
        let ranges = merge(ranges)
        let parts = pieces(of: s, count: ranges.count)
        var i = 0
        return fanOut(ranges) { r in
            defer { i += 1 }
            return Edit(range: r, text: parts[i], caret: NSRange(location: r.location + (parts[i] as NSString).length, length: 0))
        }
    }

    /// Copy: the selected texts, in document order, joined by newlines (empty selections count as empty lines).
    public static func copied(_ text: NSString, _ ranges: [NSRange]) -> String {
        merge(ranges).map { text.substring(with: $0) }.joined(separator: "\n")
    }
}
