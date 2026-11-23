import Foundation

enum VMotion: Equatable {
    case key(Character), gg, find(Character, Character), obj(inner: Bool, Character)
    /// `ge gE gj gk`.
    case g(Character)
    /// `` `a `` (exact) or `'a` (linewise).
    case mark(Character, Character)
    /// A position found by the command line (`d/foo`).
    case at(Int)
}
enum VTarget: Equatable { case line, motion(VMotion) }
enum VCmd: Equatable {
    case motion(VMotion, Int?)
    case op(Character, VTarget, Int?)
    case simple(Character, Int?, Character?)
    case cmdline(Character)
    /// An operator waiting for a `/` or `?` search as its motion.
    case opSearch(Character, Int?)
}
enum VParse { case incomplete, invalid, done(VCmd) }
enum VMotionParse { case incomplete, invalid, done(VMotion) }

/// Where a motion lands and how an operator treats the text up to it.
struct MRes {
    var target: Int
    var linewise = false
    var inclusive = false
    var keepGoal = false
    var goal: Int?
}

extension VimState {
    static let motionKeys: Set<Character> = Set("hjklwbeWBE0^$G%{}nN*#;, +-\u{7F}\r\u{4}\u{15}\u{6}\u{2}HML")
        .union([VimKey.leftToken, VimKey.rightToken, VimKey.upToken, VimKey.downToken])
    static let objectKeys: Set<Character> = Set("wWpbB()[]{}<>\"'`")
    static let normalSimple: Set<Character> = Set("xXsSDCYJ~pPuiaIAoOvV.&\u{12}\u{16}\u{5}\u{19}")
    static let visualSimple: Set<Character> = Set("dxXDcsSCRyY<>J~uUpPovVIA\u{16}\u{5}\u{19}")

    // MARK: Parsing

    static func parse(_ s: [Character], visual: Bool) -> VParse {
        var i = 0
        func count() -> Int? {
            guard i < s.count, s[i].isASCII, s[i].isNumber, s[i] != "0" else { return nil }
            var v = 0
            while i < s.count, s[i].isASCII, let n = s[i].wholeNumberValue { v = min(v * 10 + n, 99_999); i += 1 }
            return v
        }
        let c1 = count()
        guard i < s.count else { return .incomplete }
        let k = s[i]
        if k == "g", i + 1 == s.count { return .incomplete }
        // An operator: `d`, or `g` with `u` `U` `~` (a `g` operator's own letter doubles: `guu`, `gUU`, `g~~`).
        var opName: Character?, opLen = 1
        if !visual { if "dcy<>".contains(k) { opName = k } else if k == "g", "uU~".contains(s[i + 1]) { opName = s[i + 1]; opLen = 2 } }
        if let op = opName {
            i += opLen
            let c2 = count()
            guard i < s.count else { return .incomplete }
            let total = c1 == nil && c2 == nil ? nil : (c1 ?? 1) * (c2 ?? 1)
            if opLen == 1 && s[i] == k || opLen == 2 && s[i] == op { return i == s.count - 1 ? .done(.op(op, .line, total)) : .invalid }
            if opLen == 2, s[i] == "g", i + 1 < s.count, s[i + 1] == op { return i + 1 == s.count - 1 ? .done(.op(op, .line, total)) : .invalid }
            if opLen == 2, s[i] == "g", i + 1 == s.count { return .incomplete }
            if "/?".contains(s[i]) { return i == s.count - 1 ? .done(.opSearch(op, total)) : .invalid }
            switch parseMotion(s, &i, objects: true) {
            case .incomplete: return .incomplete
            case .invalid: return .invalid
            case .done(let m): return i == s.count ? .done(.op(op, .motion(m), total)) : .invalid
            }
        }
        if k == "g", i + 1 < s.count, s[i + 1] == "v" || visual && "uU~".contains(s[i + 1]) {
            return i + 2 == s.count ? .done(.simple("g", c1, s[i + 1])) : .invalid
        }
        if "gfFtT'`".contains(k) || visual && "ia".contains(k) {
            switch parseMotion(s, &i, objects: visual) {
            case .incomplete: return .incomplete
            case .invalid: return .invalid
            case .done(let m): return i == s.count ? .done(.motion(m, c1)) : .invalid
            }
        }
        let argKeys = visual ? "rz" : "rzqm@"
        guard i == s.count - 1 || argKeys.contains(k) else { return .invalid }
        if motionKeys.contains(k) { return .done(.motion(.key(k), c1)) }
        if "/?:".contains(k) { return .done(.cmdline(k)) }
        if argKeys.contains(k) {
            guard i + 1 < s.count else { return .incomplete }
            guard i + 2 == s.count else { return .invalid }
            let a = s[i + 1]
            switch k {
            case "z": return "ztb.-".contains(a) ? .done(.simple("z", c1, a)) : .invalid
            case "q", "m": return a.isASCII && a.isLetter ? .done(.simple(k, c1, a)) : .invalid
            case "@": return a == "@" || a.isASCII && a.isLetter ? .done(.simple(k, c1, a)) : .invalid
            default: return a == VimKey.esc ? .invalid : .done(.simple("r", c1, a))
            }
        }
        return (visual ? visualSimple : normalSimple).contains(k) ? .done(.simple(k, c1, nil)) : .invalid
    }

    static func parseMotion(_ s: [Character], _ i: inout Int, objects: Bool) -> VMotionParse {
        let k = s[i]
        switch k {
        case "g":
            guard i + 1 < s.count else { return .incomplete }
            i += 2
            switch s[i - 1] {
            case "g": return .done(.gg)
            case "e", "E", "j", "k": return .done(.g(s[i - 1]))
            default: return .invalid
            }
        case "'", "`":
            guard i + 1 < s.count else { return .incomplete }
            i += 2
            let a = s[i - 1]
            return a.isASCII && a.isLetter || "'`<>".contains(a) ? .done(.mark(k, a)) : .invalid
        case "f", "F", "t", "T":
            guard i + 1 < s.count else { return .incomplete }
            i += 2
            return s[i - 1] == VimKey.esc ? .invalid : .done(.find(k, s[i - 1]))
        case "i" where objects, "a" where objects:
            guard i + 1 < s.count else { return .incomplete }
            i += 2
            return objectKeys.contains(s[i - 1]) ? .done(.obj(inner: k == "i", s[i - 1])) : .invalid
        default:
            guard motionKeys.contains(k) else { return .invalid }
            i += 1
            return .done(.key(k))
        }
    }

    // MARK: Motions

    /// Evaluates a motion; a jump (`G`, `gg`, `%`, a search, a mark, `H M L`) remembers where it started for `''`.
    mutating func evalMotion(_ m: VMotion, count: Int?, from c: Int, op: Character?) -> MRes? {
        let r = evalMotion0(m, count: count, from: c, op: op)
        guard r != nil else { motionFailed = true; return nil }
        switch m {
        case .gg, .mark, .at: jumpPrev = c
        case .key(let k) where "G%nN*#{}HML".contains(k): jumpPrev = c
        default: break
        }
        return r
    }

    mutating func evalMotion0(_ m: VMotion, count: Int?, from c: Int, op: Character?) -> MRes? {
        let cnt = count ?? 1
        switch m {
        case .obj: return nil
        case .at(let p): return MRes(target: p)
        case .gg: return lineMotion(to: (count ?? 1) - 1)
        case .g(let k):
            switch k {
            case "j": return evalMotion0(.key("j"), count: count, from: c, op: op)
            case "k": return evalMotion0(.key("k"), count: count, from: c, op: op)
            default:
                var p = c
                for _ in 0..<cnt { p = d.prevWordEnd(p, big: k == "E") }
                return MRes(target: p, inclusive: true)
            }
        case .mark(let kind, let ch):
            let pos = ch == "'" || ch == "`" ? jumpPrev ?? 0 : marks[ch]
            guard let pos else { message = "E20: Mark not set"; return nil }
            let p = max(0, min(pos, d.n))
            return kind == "'" ? lineMotion(to: lineIndex(d.lineStarts(), p)) : MRes(target: p)
        case .find(let kind, let ch):
            lastFind = (kind, ch)
            return findChar(kind, ch, count: cnt, from: c, repeating: false)
        case .key(let k0):
            let k: Character
            switch k0 {
            case VimKey.leftToken, "\u{7F}": k = "h"
            case VimKey.rightToken, " ": k = "l"
            case VimKey.upToken: k = "k"
            case VimKey.downToken: k = "j"
            default: k = k0
            }
            let ls = d.lineStart(c), le = d.lineEnd(c)
            switch k {
            case "h":
                var p = c
                for _ in 0..<cnt where p > ls { p = d.prev(p) }
                return MRes(target: p)
            case "l":
                var p = c
                for _ in 0..<cnt where p < le { p = min(d.next(p), le) }
                return MRes(target: p)
            case "j", "k": return verticalMove(k == "j" ? cnt : -cnt, from: c)
            case "\u{4}": return verticalMove(count ?? max(1, pageLines / 2), from: c)
            case "\u{15}": return verticalMove(-(count ?? max(1, pageLines / 2)), from: c)
            case "\u{6}": return verticalMove(count ?? max(1, pageLines - 2), from: c)
            case "\u{2}": return verticalMove(-(count ?? max(1, pageLines - 2)), from: c)
            case "+", "\r": return lineMotion(to: lineIndex(d.lineStarts(), c) + cnt)
            case "-": return lineMotion(to: lineIndex(d.lineStarts(), c) - cnt)
            case "0": return MRes(target: ls)
            case "^": return MRes(target: d.firstNonBlank(ls))
            case "$":
                let starts = d.lineStarts()
                let l2 = min(lineIndex(starts, c) + cnt - 1, max(starts.count - 1, 0))
                let a = starts[l2], b = d.lineEnd(a)
                return MRes(target: b > a ? b - 1 : a, inclusive: true, goal: Int.max)
            case "G": return lineMotion(to: count.map { $0 - 1 } ?? d.lastLine)
            case "w", "W":
                let big = k == "W"
                var p = c
                if op == "c", d.n > c, d.cls(c, big: big) != 0 {          // `cw` changes to the end of the word, like `ce`
                    var e = c
                    while e + 1 < le, d.cls(e + 1, big: big) == d.cls(c, big: big) { e += 1 }
                    p = e
                    for _ in 1..<max(cnt, 1) { p = d.wordEnd(p, big: big) }
                    return MRes(target: p, inclusive: true)
                }
                for step in 1...max(cnt, 1) {
                    var q = d.nextWordStart(p, big: big)
                    if op != nil, step == cnt, d.lineStart(q) != d.lineStart(p) || q >= d.n && d.lineEnd(p) < d.n { q = min(q, d.lineEnd(p)) }
                    if q == p { break }
                    p = q
                }
                return MRes(target: p)
            case "e", "E":
                var p = c
                for _ in 0..<cnt { p = d.wordEnd(p, big: k == "E") }
                return MRes(target: p, inclusive: true)
            case "b", "B":
                var p = c
                for _ in 0..<cnt { p = d.prevWordStart(p, big: k == "B") }
                return MRes(target: p)
            case "}":
                let starts = d.lineStarts(), last = d.lastLine
                var i = lineIndex(starts, c)
                for _ in 0..<cnt {
                    while i <= last, d.isEmptyLine(at: starts[i]) { i += 1 }
                    while i <= last, !d.isEmptyLine(at: starts[i]) { i += 1 }
                }
                return MRes(target: i > last ? d.n : starts[i])
            case "{":
                let starts = d.lineStarts()
                var i = lineIndex(starts, c)
                for _ in 0..<cnt {
                    while i >= 0, d.isEmptyLine(at: starts[i]) { i -= 1 }
                    while i >= 0, !d.isEmptyLine(at: starts[i]) { i -= 1 }
                }
                return MRes(target: i < 0 ? 0 : starts[i])
            case "%":
                guard let j = d.matchBracket(from: c) else { return nil }
                return MRes(target: j, inclusive: true)
            case ";", ",":
                guard let f = lastFind else { return nil }
                let kind: Character = k == "," ? (f.kind.isLowercase ? Character(f.kind.uppercased()) : Character(f.kind.lowercased())) : f.kind
                return findChar(kind, f.ch, count: cnt, from: c, repeating: true)
            case "H", "M", "L":
                let last = max(d.lastLine, 0), v = visible ?? 0..<(last + 1)
                let top = max(0, min(v.lowerBound, last)), bottom = max(top, min(v.upperBound - 1, last))
                let l = k == "H" ? min(top + cnt - 1, bottom) : k == "L" ? max(bottom - cnt + 1, top) : (top + bottom) / 2
                return lineMotion(to: l)
            case "n", "N":
                guard let s = lastSearch else { message = "No previous search"; return nil }
                hlOn = true; hlDirty = true
                return searchMotion(s.pat, forward: k == "n" ? s.forward : !s.forward, count: cnt, from: c)
            case "*", "#":
                var a = c
                while a < le, !VimDoc.isWordChar(d.u[a]) { a += 1 }
                guard a < le else { return nil }
                var b = a
                while a > ls, VimDoc.isWordChar(d.u[a - 1]) { a -= 1 }
                while b < le, VimDoc.isWordChar(d.u[b]) { b += 1 }
                let pat = "\\<" + d.str(a, b) + "\\>"
                lastSearch = (pat, k == "*"); hlOn = true; hlDirty = true
                return searchMotion(pat, forward: k == "*", count: cnt, from: k == "*" ? c : a)
            default: return nil
            }
        }
    }

    func lineMotion(to l: Int) -> MRes {
        let starts = d.lineStarts()
        let tl = max(0, min(l, max(d.lastLine, 0)))
        return MRes(target: d.firstNonBlank(starts[tl]), linewise: true)
    }

    func verticalMove(_ delta: Int, from c: Int) -> MRes? {
        var ls = d.lineStart(c), moved = 0
        while moved < abs(delta) {
            if delta > 0 {
                let le = d.lineEnd(ls)
                guard le + 1 < d.n else { break }             // no next line (an empty one after a final newline is none)
                ls = le + 1
            } else {
                guard ls > 0 else { break }
                ls = d.lineStart(ls - 1)
            }
            moved += 1
        }
        guard moved > 0 else { return nil }
        let le = d.lineEnd(ls)
        let col = goal == Int.max ? max(le - ls - 1, 0) : min(goal, max(le - ls - 1, 0))
        return MRes(target: ls + col, linewise: true, keepGoal: true)
    }

    func findChar(_ kind: Character, _ ch: Character, count: Int, from c: Int, repeating: Bool) -> MRes? {
        let units = Array(String(ch).utf16)
        guard units.count == 1 else { return nil }
        let unit = units[0], ls = d.lineStart(c), le = d.lineEnd(c)
        var left = count
        if kind == "f" || kind == "t" {
            var j = c + (kind == "t" && repeating ? 2 : 1)
            while j < le {
                if d.u[j] == unit { left -= 1; if left == 0 { return MRes(target: kind == "f" ? j : j - 1, inclusive: true) } }
                j += 1
            }
        } else {
            var j = c - (kind == "T" && repeating ? 2 : 1)
            while j >= ls {
                if d.u[j] == unit { left -= 1; if left == 0 { return MRes(target: kind == "F" ? j : j + 1) } }
                j -= 1
            }
        }
        return nil
    }

    // MARK: Search

    /// A Vim pattern as ICU: `\<` `\>` word boundaries, `\c` ignores case, and `\( \) \| \+ \? \{` are the special ones.
    static func regex(_ pat: String, ignoreCase: Bool = false) -> NSRegularExpression? {
        var out = "", ic = ignoreCase, i = 0
        let cs = Array(pat)
        while i < cs.count {
            let c = cs[i]
            if c == "\\", i + 1 < cs.count {
                let n = cs[i + 1]
                i += 2
                switch n {
                case "<": out += "\\b(?=\\w)"
                case ">": out += "(?<=\\w)\\b"
                case "c": ic = true
                case "C": ic = false
                case "(", ")", "|", "+", "?", "{", "}": out.append(n)
                case "=": out += "?"
                default: out += "\\" + String(n)
                }
                continue
            }
            if c == "[" {
                var j = i + 1
                if j < cs.count, cs[j] == "^" { j += 1 }
                if j < cs.count, cs[j] == "]" { j += 1 }
                while j < cs.count, cs[j] != "]" { j += 1 }
                if j < cs.count { out += String(cs[i...j]); i = j + 1; continue }
            }
            out += "()|+?{}".contains(c) ? "\\" + String(c) : String(c)
            i += 1
        }
        return try? NSRegularExpression(pattern: out, options: ic ? [.caseInsensitive, .anchorsMatchLines] : [.anchorsMatchLines])
    }

    static func matches(_ re: NSRegularExpression, in d: VimDoc) -> [NSRange] {
        re.matches(in: String(decoding: d.u, as: UTF16.self), range: NSRange(location: 0, length: d.n)).map(\.range)
    }

    /// Every match of the active search, for the app to highlight.
    func highlightRanges() -> [NSRange] {
        guard hlOn, let p = lastSearch?.pat, let re = Self.regex(p) else { return [] }
        return Array(Self.matches(re, in: d).filter { $0.length > 0 }.prefix(5000))
    }

    mutating func searchMotion(_ pat: String, forward: Bool, count: Int, from c: Int) -> MRes? {
        guard let re = Self.regex(pat) else { message = "Invalid pattern: " + pat; return nil }
        let ms = Self.matches(re, in: d).map(\.location)
        guard !ms.isEmpty else { message = "Pattern not found: " + pat; return nil }
        var p = c
        for _ in 0..<count { p = forward ? ms.first { $0 > p } ?? ms[0] : ms.last { $0 < p } ?? ms[ms.count - 1] }
        return MRes(target: p)
    }

    // MARK: Command line

    mutating func commandLineKey(_ key: VimKey) {
        switch key {
        case .escape, .ctrl("["): mode = cmdBack; cmdText = ""
        case .ctrl("u"): cmdText = ""
        case .backspace:
            if cmdText.isEmpty { mode = cmdBack } else { cmdText.removeLast() }
        case .returnKey: executeCommandLine()
        case .char(let c): if c != "\u{0}" { cmdText.append(c) }
        default: break
        }
    }

    mutating func executeCommandLine() {
        mode = .normal
        let text = cmdText
        cmdText = ""
        if cmdPrefix == ":" { return ex(text.trimmingCharacters(in: .whitespaces)) }
        let forward = cmdPrefix == "/"
        let pat = text.isEmpty ? lastSearch?.pat ?? "" : text
        let os = opSearch
        opSearch = nil
        guard !pat.isEmpty else { message = "No previous search"; return }
        lastSearch = (pat, forward); hlOn = true; hlDirty = true
        guard let r = searchMotion(pat, forward: forward, count: os?.count ?? 1, from: cur) else { return }
        jumpPrev = cur
        guard let os else { cur = d.norm(r.target); return }
        regSel = os.reg
        defer { regSel = nil }
        isChange = false
        runOperator(os.op, .motion(.at(r.target)), count: nil, keys: os.keys)
        finishChange(keys: os.keys + Array(text) + ["\r"], wasInsert: false, shape: nil)
    }

    /// An `:` address: `.`, `$`, a number, `'x`, with `+N`/`-N` after; 0-based line, or nil.
    mutating func exAddress(_ t: [Character], _ i: inout Int) -> Int? {
        var base: Int?
        let starts = d.lineStarts()
        if i < t.count {
            switch t[i] {
            case ".": base = lineIndex(starts, cur); i += 1
            case "$": base = d.lastLine; i += 1
            case "'":
                guard i + 1 < t.count, let m = t[i + 1] == "'" ? jumpPrev : marks[t[i + 1]] else { return nil }
                base = lineIndex(starts, min(m, d.n)); i += 2
            default:
                var v = 0, any = false
                while i < t.count, t[i].isASCII, let n = t[i].wholeNumberValue { v = min(v * 10 + n, 99_999_999); i += 1; any = true }
                if any { base = v - 1 }
            }
        }
        while i < t.count, t[i] == "+" || t[i] == "-" {
            let sign = t[i] == "+" ? 1 : -1
            i += 1
            var v = 0, any = false
            while i < t.count, t[i].isASCII, let n = t[i].wholeNumberValue { v = min(v * 10 + n, 99_999_999); i += 1; any = true }
            base = (base ?? lineIndex(starts, cur)) + sign * (any ? v : 1)
        }
        return base
    }

    mutating func ex(_ text0: String) {
        let t = Array(text0)
        var i = 0
        var range: (lo: Int, hi: Int)?
        if t.first == "%" { range = (0, d.lastLine); i = 1 } else if let a1 = exAddress(t, &i) {
            var a2 = a1
            if i < t.count, t[i] == "," { i += 1; a2 = exAddress(t, &i) ?? lineIndex(d.lineStarts(), cur) }
            range = (a1, a2)
        } else if i < t.count, t[i] == "," {
            i += 1
            range = (lineIndex(d.lineStarts(), cur), exAddress(t, &i) ?? lineIndex(d.lineStarts(), cur))
        }
        if var r = range {
            let last = max(d.lastLine, 0)
            r = (max(0, min(r.lo, last)), max(0, min(r.hi, last)))
            range = r.lo <= r.hi ? r : (r.hi, r.lo)
        }
        let text = String(t[i...]).trimmingCharacters(in: .whitespaces)
        switch text {
        case "w", "write": cmds.append(.save)
        case "q", "quit", "q!", "quit!": cmds.append(.close)
        case "wq", "x", "xit", "wq!", "exit": cmds.append(.saveAndClose)
        case "noh", "nohlsearch": hlOn = false; hlDirty = true
        case "reg", "registers", "di", "display": message = registerListing()
        case "":
            if let r = range { jumpPrev = cur; cur = lineMotion(to: r.hi).target }
        default:
            let cs = Array(text)
            let words = text.split(separator: " ").map(String.init)
            if words.first == "set" || words.first == "se", let mode = Self.numbering(Array(words.dropFirst())) { cmds.append(.lineNumbers(mode)) }
            else if cs[0] == "&" { substitute("", range: range, keepFlags: text.hasPrefix("&&")) }
            else if cs[0] == "s", cs.count == 1 || !cs[1].isLetter { substitute(String(cs.dropFirst()), range: range, keepFlags: false) }
            else { message = "Not an editor command: " + text0 }
        }
    }

    /// `:set` arguments about line numbers; nil when there are none (`nu` alone is plain absolute numbers).
    static func numbering(_ args: [String]) -> RelativeNumbers? {
        if args.contains("rnu") || args.contains("relativenumber") {
            return args.contains("nu") || args.contains("number") ? .hybrid : .relative
        }
        return args.contains(where: ["nornu", "norelativenumber", "nu", "number"].contains) ? .off : nil
    }

    /// `:s/pat/rep/[gi]` over `range` (the cursor's line when nil); `args` empty repeats the last one.
    mutating func substitute(_ args: String, range: (lo: Int, hi: Int)?, keepFlags: Bool) {
        let cs = Array(args)
        var pat: String, rep: String, flags: String
        if let delim = cs.first, !delim.isLetter, !delim.isNumber, delim != " ", delim != "&" {
            var parts = [""]
            var j = 1
            while j < cs.count {
                if cs[j] == "\\", j + 1 < cs.count { parts[parts.count - 1] += String([cs[j], cs[j + 1]]); j += 2; continue }
                if cs[j] == delim, parts.count < 3 { parts.append(""); j += 1; continue }
                parts[parts.count - 1].append(cs[j]); j += 1
            }
            pat = parts[0]; rep = parts.count > 1 ? parts[1] : ""; flags = parts.count > 2 ? parts[2] : ""
            if pat.isEmpty { pat = lastSearch?.pat ?? "" }
        } else {
            guard let l = lastSub else { message = "No previous substitute"; return }
            (pat, rep, flags) = (l.pat, l.rep, keepFlags ? l.flags : "")
        }
        guard !pat.isEmpty, let re = Self.regex(pat, ignoreCase: flags.contains("i")) else { message = "Invalid pattern: " + pat; return }
        lastSub = (pat, rep, flags); lastSearch = (pat, true); hlOn = true; hlDirty = true
        let starts = d.lineStarts(), r = range ?? (lineIndex(starts, cur), lineIndex(starts, cur))
        var subs = 0, lines = 0, lastLine = -1
        for l in stride(from: min(r.hi, starts.count - 1), through: r.lo, by: -1) {
            let ls = starts[l], le = d.lineEnd(ls)
            let line = d.str(ls, le) as NSString
            let ms = re.matches(in: line as String, range: NSRange(location: 0, length: line.length))
            let used = flags.contains("g") ? ms : Array(ms.prefix(1))
            guard !used.isEmpty else { continue }
            let out = NSMutableString(string: line)
            for m in used.reversed() { out.replaceCharacters(in: m.range, with: Self.expand(rep, m, line)) }
            splice(ls, le, Array((out as String).utf16))
            subs += used.count; lines += 1; lastLine = max(lastLine, l)
        }
        guard lines > 0 else { message = "Pattern not found: " + pat; return }
        let st = d.lineStarts()
        cur = d.firstNonBlank(st[min(lastLine, st.count - 1)])
        isChange = true
        if lines > 2 { message = "\(subs) substitutions on \(lines) lines" }
    }

    /// The replacement text: `&` the match, `\1`..`\9` groups, `\r` a newline, `\t` a tab, `\&` and `\\` themselves.
    static func expand(_ rep: String, _ m: NSTextCheckingResult, _ line: NSString) -> String {
        var out = ""
        let cs = Array(rep)
        var i = 0
        func group(_ n: Int) -> String { n < m.numberOfRanges && m.range(at: n).location != NSNotFound ? line.substring(with: m.range(at: n)) : "" }
        while i < cs.count {
            let c = cs[i]
            i += 1
            if c == "&" { out += group(0); continue }
            guard c == "\\", i < cs.count else { out.append(c); continue }
            let n = cs[i]
            i += 1
            if let v = n.wholeNumberValue, n.isASCII { out += group(v) }
            else if n == "r" || n == "n" { out += "\n" }
            else if n == "t" { out += "\t" }
            else { out.append(n) }
        }
        return out
    }
}
