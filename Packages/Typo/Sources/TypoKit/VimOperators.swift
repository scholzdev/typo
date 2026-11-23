import Foundation

extension VimState {
    // MARK: Operators

    mutating func runOperator(_ op: Character, _ target: VTarget, count: Int?, keys: [Character]) {
        let c = cur
        var s = c, e = c, linewise = false, backward = false
        switch target {
        case .line:
            let starts = d.lineStarts(), l = lineIndex(starts, c), last = max(d.lastLine, l)
            let l2 = min(l + (count ?? 1) - 1, last)
            s = starts[l]; e = min(d.n, d.lineEnd(starts[l2]) + 1); linewise = true
        case .motion(.obj(let inner, let ch)):
            guard let o = object(inner, ch, at: c, count: count ?? 1) else { return }
            (s, e, linewise) = o
            backward = true
        case .motion(let m):
            guard let r = evalMotion(m, count: count, from: c, op: op) else { return }
            (s, e, linewise) = range(for: r, from: c)
            backward = r.target < c
        }
        if op == ">" || op == "<" { shiftLines(s, e, right: op == ">", times: 1); return }
        applyOperator(op, s, e, linewise: linewise, backward: backward, cursor: c)
    }

    func object(_ inner: Bool, _ ch: Character, at c: Int, count: Int = 1) -> VimDoc.Obj? {
        switch ch {
        case "w": return d.wordObject(c, inner: inner, big: false)
        case "W": return d.wordObject(c, inner: inner, big: true)
        case "p": return d.paragraphObject(c, inner: inner)
        case "b", "(", ")": return d.bracketObject(c, open: 40, close: 41, inner: inner, count: count)
        case "B", "{", "}": return d.bracketObject(c, open: 123, close: 125, inner: inner, count: count)
        case "[", "]": return d.bracketObject(c, open: 91, close: 93, inner: inner, count: count)
        case "<", ">": return d.bracketObject(c, open: 60, close: 62, inner: inner, count: count)
        case "\"", "'", "`": return d.quoteObject(c, quote: Array(String(ch).utf16)[0], inner: inner)
        default: return nil
        }
    }

    /// The text a motion covers, with Vim's rule that an exclusive motion ending in column 0 stops at the end of the
    /// line before (and becomes linewise when it also starts at or before the first non-blank).
    func range(for r: MRes, from c: Int) -> (Int, Int, Bool) {
        let a = min(c, r.target)
        var b = max(c, r.target)
        if r.linewise { return (d.lineStart(a), min(d.n, d.lineEnd(b) + 1), true) }
        if r.inclusive {
            if b < d.n, d.u[b] != VimDoc.nl {
                b += 1
                if (0xD800...0xDBFF).contains(d.u[b - 1]), b < d.n { b += 1 }
            }
            return (a, b, false)
        }
        if b > a, b == d.lineStart(b), d.lineStart(a) < b {
            b -= 1
            let ls = d.lineStart(a)
            var f = ls
            while f < d.lineEnd(ls), d.isBlank(d.u[f]) { f += 1 }
            if a <= f { return (ls, min(d.n, b + 1), true) }
        }
        return (a, b, false)
    }

    mutating func applyOperator(_ op: Character, _ s: Int, _ e: Int, linewise: Bool, backward: Bool, cursor c: Int) {
        switch op {
        case "y":
            guard e > s || linewise else { return }
            var text = d.str(s, e)
            if linewise, !text.hasSuffix("\n") { text += "\n" }
            setRegister(text, yank: true)
            cur = linewise ? (backward && s < c ? s + min(d.col(c), max(d.lineEnd(s) - s - 1, 0)) : c) : s
        case "d":
            guard e > s else { return }
            deleteRange(s, e, linewise: linewise)
            isChange = true
        case "u", "U", "~":
            guard e > s else { return }
            splice(s, e, Array(Self.toggleCase(d.str(s, e), op).utf16))
            cur = linewise ? c : s
            isChange = true
        case "c":
            if e > s {
                var text = d.str(s, e)
                if linewise, !text.hasSuffix("\n") { text += "\n" }
                setRegister(text)
            }
            if linewise {
                let ind = indentOf(line: s)
                let hadNL = e > s && d.u[e - 1] == VimDoc.nl
                splice(s, e, ind + (hadNL ? [VimDoc.nl] : []))
                enterInsert(at: s + ind.count)
            } else {
                splice(s, e, [])
                enterInsert(at: s)
            }
        default: break
        }
    }

    mutating func deleteRange(_ s: Int, _ e: Int, linewise: Bool) {
        var text = d.str(s, e)
        if linewise, !text.hasSuffix("\n") { text += "\n" }
        setRegister(text)
        guard linewise else { splice(s, e, []); cur = s; return }
        var ds = s
        if e >= d.n, s > 0, d.n == 0 || d.u[d.n - 1] != VimDoc.nl { ds = s - 1 }   // the last line has no newline of its own
        splice(ds, e, [])
        if ds < s { cur = d.firstNonBlank(d.lineStart(d.n)) }
        else if s >= d.n, d.n > 0 { cur = d.firstNonBlank(d.lineStart(d.n - 1)) }
        else { cur = d.firstNonBlank(d.lineStart(s)) }
    }

    mutating func shiftLines(_ s: Int, _ e: Int, right: Bool, times: Int) {
        let starts = d.lineStarts()
        let l1 = lineIndex(starts, s), l2 = lineIndex(starts, max(s, e > s ? e - 1 : s))
        let unit = Array(indent.unit(for: "").utf16)
        for l in stride(from: l2, through: l1, by: -1) {
            let ls = starts[l]
            guard d.lineEnd(ls) > ls else { continue }
            if right {
                splice(ls, ls, Array(repeating: unit, count: max(times, 1)).flatMap { $0 })
                continue
            }
            for _ in 0..<max(times, 1) {
                if d.u[ls] == 9 { splice(ls, ls + 1, []); continue }
                var k = 0
                while k < indent.levelWidth, ls + k < d.lineEnd(ls), d.u[ls + k] == 32 { k += 1 }
                splice(ls, ls + k, [])
            }
        }
        cur = d.firstNonBlank(starts[l1])
        isChange = true
    }

    // MARK: Normal-mode commands

    mutating func simple(_ k: Character, count: Int?, arg: Character?, keys: [Character]) {
        let cnt = count ?? 1
        switch k {
        case "x": runOperator("d", .motion(.key("l")), count: count, keys: keys)
        case "X": runOperator("d", .motion(.key("h")), count: count, keys: keys)
        case "s": runOperator("c", .motion(.key("l")), count: count, keys: keys)
        case "S": runOperator("c", .line, count: count, keys: keys)
        case "D": runOperator("d", .motion(.key("$")), count: count, keys: keys)
        case "C": runOperator("c", .motion(.key("$")), count: count, keys: keys)
        case "Y": runOperator("y", .line, count: count, keys: keys)
        case "J": join(lines: max(cnt, 2))
        case "~": toggle(count: cnt)
        case "p", "P": paste(before: k == "P", count: cnt)
        case "u": cmds.append(.undo(cnt))
        case "\u{12}": cmds.append(.redo(cnt))
        case ".": repeatLastChange(count: count)
        case "i": enterInsert(at: cur, count: cnt)
        case "a":
            enterInsert(at: cur < d.lineEnd(cur) ? d.next(cur) : cur, count: cnt)
        case "I":
            var p = d.lineStart(cur)
            while p < d.lineEnd(cur), d.isBlank(d.u[p]) { p += 1 }
            enterInsert(at: p, count: cnt)
        case "A": enterInsert(at: d.lineEnd(cur), count: cnt)
        case "o":
            let le = d.lineEnd(cur), ind = indentOf(line: cur)
            splice(le, le, [VimDoc.nl] + ind)
            enterInsert(at: le + 1 + ind.count, count: cnt, newline: true)
        case "O":
            let ls = d.lineStart(cur), ind = indentOf(line: cur)
            splice(ls, ls, ind + [VimDoc.nl])
            enterInsert(at: ls + ind.count, count: cnt, newline: true)
        case "v": anchor = cur; mode = .visual
        case "V": anchor = cur; mode = .visualLine
        case "r": replaceChars(count: cnt, with: arg)
        case "z": cmds.append(.scroll(arg == "t" ? .top : arg == "b" || arg == "-" ? .bottom : .center))
        case "\u{16}": anchor = cur; mode = .visualBlock
        case "\u{5}", "\u{19}": scrollLines(k == "\u{5}" ? cnt : -cnt)
        case "g": gv()
        case "m": if let arg { marks[arg] = cur }
        case "q": if let arg { recording = (arg, []) }
        case "@": playMacro(arg, count: cnt)
        case "&": substitute("", range: nil, keepFlags: false)
        default: break
        }
    }

    /// `gv`: selects the last Visual area again.
    mutating func gv() {
        guard let a = marks["<"], let b = marks[">"] else { return }
        anchor = max(0, min(a, d.n)); cur = max(0, min(b, d.n))
        mode = visualMode
        if mode == .visualBlock { goal = d.col(cur) }
    }

    /// Ctrl-e and Ctrl-y: the app scrolls; the cursor stays on a visible line.
    mutating func scrollLines(_ n: Int) {
        cmds.append(.scroll(.line(n)))
        guard let v = visible else { return }
        let l = lineIndex(d.lineStarts(), cur)
        let nl = max(0, min(max(v.lowerBound + n, min(l, v.upperBound - 1 + n)), d.lastLine))
        if nl != l, let r = verticalMove(nl - l, from: cur) { cur = d.norm(r.target); keepGoal = true }
    }

    /// `@a`, `@@`, `3@a`: replays the recorded keys, stopping at the first failing motion or error.
    mutating func playMacro(_ arg: Character?, count: Int) {
        guard let arg else { return }
        let name = arg == "@" ? lastMacro : Character(arg.lowercased())
        guard let name, let keys = macros[name] else { message = "E748: No previously used register"; return }
        lastMacro = name
        guard macroDepth < 8 else { return }
        macroDepth += 1
        defer { macroDepth -= 1; isChange = false }
        for _ in 0..<min(count, 10_000) {
            for k in keys {
                step(k, sel: nil)
                if motionFailed || message != nil { return }
            }
        }
    }

    mutating func replaceChars(count: Int, with arg: Character?) {
        guard let arg, cur + count <= d.lineEnd(cur) else { return }
        if arg == "\r" {
            splice(cur, cur + count, [VimDoc.nl])
            cur += 1
        } else {
            let one = Array(String(arg).utf16)
            splice(cur, cur + count, Array(repeating: one, count: count).flatMap { $0 })
            cur += (count - 1) * one.count
        }
        isChange = true
    }

    mutating func toggle(count: Int) {
        let le = d.lineEnd(cur), k = min(count, le - cur)
        guard k > 0 else { return }
        let t = Array(Self.toggleCase(d.str(cur, cur + k), "~").utf16)
        splice(cur, cur + k, t)
        cur = min(cur + t.count, d.lineEnd(cur))
        isChange = true
    }

    /// Joins `lines` lines starting at the cursor's, as `J` does.
    mutating func join(lines: Int) {
        let ls = d.lineStart(cur)
        var last: Int?
        for _ in 0..<(lines - 1) {
            let le = d.lineEnd(ls)
            guard le + 1 < d.n else { break }
            var j = le + 1
            while j < d.n, d.isBlank(d.u[j]) { j += 1 }
            let nextEmpty = j >= d.n || d.u[j] == VimDoc.nl
            let tight = nextEmpty || d.u[j] == 41 || le == ls || d.isBlank(d.u[le - 1])
            splice(le, j, tight ? [] : [32])
            last = le
        }
        guard let last else { return }
        cur = last
        isChange = true
    }

    mutating func paste(before: Bool, count: Int) {
        let content = readRegister()
        guard !content.isEmpty else { return }
        let reg = Array(content.utf16)
        let text = Array(repeating: reg, count: count).flatMap { $0 }
        if content.hasSuffix("\n") {
            if before {
                let ls = d.lineStart(cur)
                splice(ls, ls, text)
                cur = d.firstNonBlank(ls)
            } else {
                let le = d.lineEnd(cur)
                if le < d.n {
                    splice(le + 1, le + 1, text)
                    cur = d.firstNonBlank(le + 1)
                } else if d.n == 0 || d.u[d.n - 1] == VimDoc.nl {
                    splice(le, le, text)
                    cur = d.firstNonBlank(le)
                } else {
                    splice(le, le, [VimDoc.nl] + text.dropLast())
                    cur = d.firstNonBlank(le + 1)
                }
            }
        } else {
            let idx = before ? cur : (cur < d.lineEnd(cur) ? d.next(cur) : cur)
            splice(idx, idx, text)
            cur = text.contains(VimDoc.nl) ? idx : idx + max(text.count - 1, 0)
        }
        isChange = true
    }

    // MARK: Visual-mode commands

    struct Block { var l1: Int, l2: Int, c1: Int, c2: Int, eol: Bool }

    /// The rectangle of a blockwise Visual selection: lines and columns (UTF-16 units); `$` extends it to every line end.
    func block() -> Block {
        let starts = d.lineStarts()
        let la = lineIndex(starts, anchor), lc = lineIndex(starts, cur)
        let ca = anchor - starts[la], cc = cur - starts[lc]
        return Block(l1: min(la, lc), l2: max(la, lc), c1: min(ca, cc), c2: max(ca, cc), eol: goal == Int.max)
    }

    func blockRanges(_ b: Block) -> [(Int, Int)] {
        let starts = d.lineStarts()
        return (b.l1...b.l2).map { l in
            let ls = starts[l], le = d.lineEnd(ls)
            let s = min(ls + b.c1, le)
            return (s, max(s, b.eol ? le : min(ls + b.c2 + 1, le)))
        }
    }

    /// Visual-block commands that work on the rectangle; false for the ones that treat it as a plain selection.
    mutating func blockCommand(_ k: Character, count: Int?, arg: Character?) -> Bool {
        let b = block(), rs = blockRanges(b), starts = d.lineStarts()
        let tl = rs[0].0
        func each(_ f: (Int, Int) -> [UInt16]) { for (s, e) in rs.reversed() { splice(s, e, f(s, e)) } }
        switch k {
        case "d", "x", "c", "y":
            mode = .normal
            let text = rs.map { d.str($0.0, $0.1) }.joined(separator: "\n")
            if k == "y" { setRegister(text, yank: true); cur = tl; return true }
            setRegister(text)
            each { _, _ in [] }
            cur = tl
            isChange = true
            if k == "c" { blockIns = (b.l1, b.l2, b.c1); enterInsert(at: tl) }
        case "I":
            mode = .normal
            blockIns = (b.l1, b.l2, b.c1)
            enterInsert(at: tl)
        case "A":
            mode = .normal
            if b.eol { blockIns = (b.l1, b.l2, nil); enterInsert(at: d.lineEnd(starts[b.l1])); return true }
            for l in stride(from: b.l2, through: b.l1, by: -1) {
                let le = d.lineEnd(starts[l]), need = starts[l] + b.c2 + 1
                if le < need { splice(le, le, Array(repeating: 32, count: need - le)) }
            }
            blockIns = (b.l1, b.l2, b.c2 + 1)
            enterInsert(at: starts[b.l1] + b.c2 + 1)
        case "r":
            mode = .normal
            if let arg, arg != "\r" {
                let one = Array(String(arg).utf16)
                each { s, e in Array(repeating: one, count: e - s).flatMap { $0 } }
                isChange = true
            }
            cur = tl
        case "~", "u", "U":
            mode = .normal
            each { s, e in Array(Self.toggleCase(d.str(s, e), k).utf16) }
            cur = tl
            isChange = true
        case ">", "<":
            mode = .normal
            shiftLines(starts[b.l1], min(d.n, d.lineEnd(starts[b.l2]) + 1), right: k == ">", times: count ?? 1)
        default: return false
        }
        return true
    }

    mutating func visualCommand(_ k: Character, count: Int?, arg: Character?) {
        if k == "g" {
            guard let a = arg else { return }
            if a == "v" { gv() } else { visualCommand(a, count: count, arg: nil) }
            return
        }
        if k == "\u{5}" || k == "\u{19}" { return scrollLines(k == "\u{5}" ? count ?? 1 : -(count ?? 1)) }
        if mode == .visualBlock, blockCommand(k, count: count, arg: arg) { return }
        let linewise = mode == .visualLine
        let lo = min(anchor, cur), hi = max(anchor, cur)
        var s = lo, e = min(d.n, hi + 1)
        if e < d.n, (0xDC00...0xDFFF).contains(d.u[e]) { e += 1 }
        if linewise { s = d.lineStart(lo); e = min(d.n, d.lineEnd(hi) + 1) }
        func lines(_ s: Int, _ e: Int) -> (Int, Int) { (d.lineStart(s), min(d.n, d.lineEnd(max(s, e - 1)) + 1)) }
        switch k {
        case "v":
            if mode == .visual { mode = .normal; cur = d.norm(cur) } else { mode = .visual }
        case "V":
            if mode == .visualLine { mode = .normal; cur = d.norm(cur) } else { mode = .visualLine }
        case "\u{16}":
            if mode == .visualBlock { mode = .normal; cur = d.norm(cur) } else { mode = .visualBlock }
        case "I":
            mode = .normal
            enterInsert(at: linewise ? d.lineStart(lo) : s)
        case "A":
            mode = .normal
            enterInsert(at: linewise ? d.lineEnd(hi) : e)
        case "o": swap(&anchor, &cur)
        case "d", "x", "X", "D":
            mode = .normal
            if k == "X" || k == "D" { let l = lines(s, e); applyOperator("d", l.0, l.1, linewise: true, backward: true, cursor: cur) }
            else { applyOperator("d", s, e, linewise: linewise, backward: true, cursor: cur) }
        case "y", "Y":
            mode = .normal
            let l = lines(s, e)
            applyOperator("y", k == "Y" ? l.0 : s, k == "Y" ? l.1 : e, linewise: linewise || k == "Y", backward: true, cursor: lo)
            cur = lo
        case "c", "s", "S", "C", "R":
            mode = .normal
            if k == "c" || k == "s" { applyOperator("c", s, e, linewise: linewise, backward: true, cursor: cur) }
            else { let l = lines(s, e); applyOperator("c", l.0, l.1, linewise: true, backward: true, cursor: cur) }
        case ">", "<":
            mode = .normal
            shiftLines(s, e, right: k == ">", times: count ?? 1)
        case "J":
            mode = .normal
            let starts = d.lineStarts()
            let n = lineIndex(starts, max(s, e > s ? e - 1 : s)) - lineIndex(starts, s) + 1
            cur = d.lineStart(s)
            join(lines: max(n, 2))
        case "~", "u", "U":
            mode = .normal
            splice(s, e, Array(Self.toggleCase(d.str(s, e), k).utf16))
            cur = s
            isChange = true
        case "p", "P":
            mode = .normal
            let old = d.str(s, e)
            var ins = readRegister()
            if linewise, !ins.hasSuffix("\n") { ins += "\n" }
            else if !linewise, ins.hasSuffix("\n") { ins = "\n" + ins }
            splice(s, e, Array(ins.utf16))
            if k == "p" { setRegister(linewise && !old.hasSuffix("\n") ? old + "\n" : old, ignoreSel: true) }
            isChange = true
            cur = linewise || ins.hasPrefix("\n") ? d.firstNonBlank(s + (ins.hasPrefix("\n") ? 1 : 0)) : s + max(ins.utf16.count - 1, 0)
        case "r":
            mode = .normal
            guard let arg, arg != "\r" else { return }
            let one = Array(String(arg).utf16)
            var out: [UInt16] = []
            for u in d.u[s..<e] { out += u == VimDoc.nl ? [u] : one }
            splice(s, e, out)
            cur = s
            isChange = true
        default: break
        }
    }
}
