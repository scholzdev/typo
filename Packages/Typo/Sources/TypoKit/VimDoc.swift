import Foundation

/// The text a Vim command works on: UTF-16 units, like the editor's own ranges.
struct VimDoc {
    var u: [UInt16]
    var n: Int { u.count }
    static let nl: UInt16 = 10

    func lineStart(_ i: Int) -> Int {
        var j = max(0, min(i, n))
        while j > 0, u[j - 1] != Self.nl { j -= 1 }
        return j
    }
    /// The index of the line's newline, or `n` on the last line.
    func lineEnd(_ i: Int) -> Int {
        var j = max(0, min(i, n))
        while j < n, u[j] != Self.nl { j += 1 }
        return j
    }
    func col(_ i: Int) -> Int { i - lineStart(i) }
    func line(of i: Int) -> Int {
        var c = 0
        for j in 0..<max(0, min(i, n)) where u[j] == Self.nl { c += 1 }
        return c
    }
    /// Start offsets of every line (a text ending in a newline has an empty last one).
    func lineStarts() -> [Int] {
        var s = [0]
        for j in 0..<n where u[j] == Self.nl { s.append(j + 1) }
        return s
    }
    /// The last line a command may reach: an empty line after a final newline is not one.
    var lastLine: Int {
        let c = lineStarts().count
        return n > 0 && u[n - 1] == Self.nl ? max(0, c - 2) : c - 1
    }
    func isEmptyLine(at i: Int) -> Bool { lineStart(i) == lineEnd(i) }
    func isBlankLine(at i: Int) -> Bool {
        let s = lineStart(i), e = lineEnd(i)
        return (s..<e).allSatisfy { u[$0] == 32 || u[$0] == 9 }
    }

    func isBlank(_ c: UInt16) -> Bool { c == 32 || c == 9 }
    static func isWordChar(_ c: UInt16) -> Bool {
        if c == 95 { return true }
        if (0xD800...0xDFFF).contains(c) { return true }
        guard let s = Unicode.Scalar(c) else { return false }
        return CharacterSet.alphanumerics.contains(s)
    }
    /// 0 blank or newline, 1 word (or any non-blank when `big`), 2 punctuation.
    func cls(_ i: Int, big: Bool) -> Int {
        let c = u[i]
        if c == 32 || c == 9 || c == Self.nl { return 0 }
        return big || Self.isWordChar(c) ? 1 : 2
    }

    /// First non-blank of the line starting at `ls`; the last character of an all-blank line.
    func firstNonBlank(_ ls: Int) -> Int {
        let e = lineEnd(ls)
        var j = ls
        while j < e, isBlank(u[j]) { j += 1 }
        return j == e ? max(ls, e - 1) : j
    }

    /// A cursor position Normal mode can rest on: on a character, except on an empty line.
    func norm(_ i: Int) -> Int {
        var j = max(0, min(i, n))
        if j == n { return n > 0 && u[n - 1] != Self.nl ? n - 1 : n }
        if u[j] == Self.nl, j > lineStart(j) { return j - 1 }
        if (0xDC00...0xDFFF).contains(u[j]), j > 0, (0xD800...0xDBFF).contains(u[j - 1]) { j -= 1 }
        return j
    }

    /// The index after the character at `i` (a surrogate pair is one character).
    func next(_ i: Int) -> Int { i < n ? i + ((0xD800...0xDBFF).contains(u[i]) && i + 1 < n ? 2 : 1) : n }
    func prev(_ i: Int) -> Int {
        guard i > 0 else { return 0 }
        return (0xDC00...0xDFFF).contains(u[i - 1]) && i > 1 ? i - 2 : i - 1
    }

    func str(_ a: Int, _ b: Int) -> String {
        let a = max(0, min(a, n)), b = max(a, min(b, n))
        return String(decoding: u[a..<b], as: UTF16.self)
    }

    // MARK: Words

    func nextWordStart(_ p: Int, big: Bool) -> Int {
        guard p < n else { return n }
        var i = p
        let c = cls(i, big: big)
        if u[i] == Self.nl { i += 1 } else if c != 0 { while i < n, cls(i, big: big) == c { i += 1 } }
        while i < n {
            if u[i] == Self.nl {
                if i > 0, u[i - 1] == Self.nl { break }       // an empty line is a word
                i += 1
            } else if isBlank(u[i]) { i += 1 } else { break }
        }
        return i
    }

    func wordEnd(_ p: Int, big: Bool) -> Int {
        var i = p + 1
        while i < n, cls(i, big: big) == 0 { i += 1 }
        if i >= n { return max(0, n - 1) }
        let c = cls(i, big: big)
        while i + 1 < n, cls(i + 1, big: big) == c { i += 1 }
        return i
    }

    /// The end of the word before `p` (`ge`); an empty line counts as a word.
    func prevWordEnd(_ p: Int, big: Bool) -> Int {
        guard n > 0 else { return 0 }
        var i = min(p, n - 1)
        if cls(i, big: big) != 0 { let c = cls(i, big: big); while i > 0, cls(i - 1, big: big) == c { i -= 1 } }
        while i > 0 {
            i -= 1
            if cls(i, big: big) != 0 || u[i] == Self.nl && lineStart(i) == i { return i }
        }
        return 0
    }

    func prevWordStart(_ p: Int, big: Bool) -> Int {
        guard p > 0 else { return 0 }
        var i = p - 1
        while i > 0, cls(i, big: big) == 0 {
            if u[i] == Self.nl, u[i - 1] == Self.nl { return i }
            i -= 1
        }
        if cls(i, big: big) == 0 { return i }
        let c = cls(i, big: big)
        while i > 0, cls(i - 1, big: big) == c { i -= 1 }
        return i
    }

    // MARK: Brackets and quotes

    static let pairs: [(open: UInt16, close: UInt16)] = [(40, 41), (91, 93), (123, 125)]

    /// The bracket matching the first bracket at or after `c` on its line.
    func matchBracket(from c: Int) -> Int? {
        let le = lineEnd(c)
        var j = c
        while j < le, !Self.pairs.contains(where: { $0.open == u[j] || $0.close == u[j] }) { j += 1 }
        guard j < le, let p = Self.pairs.first(where: { $0.open == u[j] || $0.close == u[j] }) else { return nil }
        if u[j] == p.open { return closer(of: j, p.open, p.close) }
        return opener(of: j, p.open, p.close)
    }
    func closer(of o: Int, _ open: UInt16, _ close: UInt16) -> Int? {
        var depth = 0, i = o + 1
        while i < n {
            if u[i] == open { depth += 1 } else if u[i] == close { if depth == 0 { return i }; depth -= 1 }
            i += 1
        }
        return nil
    }
    func opener(of cl: Int, _ open: UInt16, _ close: UInt16) -> Int? {
        var depth = 0, i = cl - 1
        while i >= 0 {
            if u[i] == close { depth += 1 } else if u[i] == open { if depth == 0 { return i }; depth -= 1 }
            i -= 1
        }
        return nil
    }

    // MARK: Text objects (start, exclusive end, linewise)

    typealias Obj = (start: Int, end: Int, linewise: Bool)

    func wordObject(_ c: Int, inner: Bool, big: Bool) -> Obj? {
        guard c < n else { return nil }
        if u[c] == Self.nl { return (c, c, false) }
        let ls = lineStart(c), le = lineEnd(c), k = cls(c, big: big)
        var s = c, e = c + 1
        while s > ls, cls(s - 1, big: big) == k { s -= 1 }
        while e < le, cls(e, big: big) == k { e += 1 }
        if inner { return (s, e, false) }
        if k == 0 {
            var e2 = e
            if e2 < le { let k2 = cls(e2, big: big); while e2 < le, cls(e2, big: big) == k2 { e2 += 1 } }
            return (s, e2, false)
        }
        var e2 = e
        while e2 < le, cls(e2, big: big) == 0 { e2 += 1 }
        if e2 > e { return (s, e2, false) }
        var s2 = s
        while s2 > ls, cls(s2 - 1, big: big) == 0 { s2 -= 1 }
        return (s2, e, false)
    }

    func bracketObject(_ c: Int, open: UInt16, close: UInt16, inner: Bool, count: Int = 1) -> Obj? {
        guard c < n else { return nil }
        var o: Int?
        if u[c] == open { o = c } else {
            var depth = 0, i = u[c] == close ? c - 1 : c
            while i >= 0 {
                if u[i] == close { depth += 1 } else if u[i] == open { if depth == 0 { o = i; break }; depth -= 1 }
                i -= 1
            }
        }
        for _ in 1..<max(count, 1) { guard let outer = o.flatMap({ opener(of: $0, open, close) }) else { return nil }; o = outer }
        guard let o, let cl = closer(of: o, open, close) else { return nil }
        if !inner { return (o, cl + 1, false) }
        // `{` ending its line and `}` after only blanks: the inner part is the lines in between.
        if o + 1 < n, u[o + 1] == Self.nl, lineStart(cl) > o, (lineStart(cl)..<cl).allSatisfy({ isBlank(u[$0]) }) {
            let a = o + 2, b = lineStart(cl)
            return a >= b ? (a, a, false) : (a, b, true)
        }
        return (o + 1, cl, false)
    }

    func quoteObject(_ c: Int, quote q: UInt16, inner: Bool) -> Obj? {
        guard c <= n else { return nil }
        let ls = lineStart(c), le = lineEnd(c)
        var qs: [Int] = []
        var i = ls
        while i < le {
            if u[i] == 92 { i += 2; continue }
            if u[i] == q { qs.append(i) }
            i += 1
        }
        var k = 0
        var found: (Int, Int)?
        while k + 1 < qs.count {
            if c <= qs[k + 1] { found = (qs[k], qs[k + 1]); break }   // containing the cursor, else the next pair
            k += 2
        }
        guard let (a, b) = found else { return nil }
        if inner { return (a + 1, b, false) }
        var e = b + 1
        while e < le, isBlank(u[e]) { e += 1 }
        if e > b + 1 { return (a, e, false) }
        var s = a
        while s > ls, isBlank(u[s - 1]) { s -= 1 }
        return (s, b + 1, false)
    }

    func paragraphObject(_ c: Int, inner: Bool) -> Obj? {
        let starts = lineStarts()
        guard !starts.isEmpty else { return nil }
        let l = max(0, starts.lastIndex { $0 <= c } ?? 0)
        let last = lastLine
        guard l <= last else { return nil }
        func blank(_ i: Int) -> Bool { isBlankLine(at: starts[i]) }
        let kind = blank(l)
        var s = l, e = l
        while s > 0, blank(s - 1) == kind { s -= 1 }
        while e < last, blank(e + 1) == kind { e += 1 }
        if !inner {
            if e < last {
                let k2 = blank(e + 1)
                e += 1
                while e < last, blank(e + 1) == k2 { e += 1 }
            } else if !kind {
                while s > 0, blank(s - 1) { s -= 1 }
            }
        }
        return (starts[s], min(n, lineEnd(starts[e]) + 1), true)
    }
}
