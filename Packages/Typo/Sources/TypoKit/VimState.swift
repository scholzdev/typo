import Foundation
import TypstEngine

public enum VimMode: Equatable, Sendable {
    case normal, insert, visual, visualLine, visualBlock, operatorPending
    /// Typing a `/`, `?` or `:` line; `VimState.status` shows it.
    case commandLine
}

/// A key press as the editor sees it: characters carry their case and shift state.
public enum VimKey: Equatable, Sendable {
    case char(Character)
    /// Ctrl with a lowercase letter, or `[` (Esc).
    case ctrl(Character)
    case escape, left, right, up, down, returnKey, backspace, tab

    static let esc: Character = "\u{1B}"
    static let leftToken: Character = "\u{F702}", rightToken: Character = "\u{F703}"
    static let upToken: Character = "\u{F700}", downToken: Character = "\u{F701}"

    var token: Character {
        switch self {
        case .char(let c): return c
        case .ctrl(let c):
            if c == "[" { return Self.esc }
            guard let a = c.asciiValue, (97...122).contains(a) else { return "\u{0}" }
            return Character(Unicode.Scalar(a & 0x1F))
        case .escape: return Self.esc
        case .left: return Self.leftToken
        case .right: return Self.rightToken
        case .up: return Self.upToken
        case .down: return Self.downToken
        case .returnKey: return "\r"
        case .backspace: return "\u{7F}"
        case .tab: return "\t"
        }
    }
}

/// `line(n)`: Ctrl-e (n > 0, the text moves up) or Ctrl-y (n < 0), by n lines.
public enum VimScroll: Equatable, Sendable { case center, top, bottom, line(Int) }

/// The size of a Visual selection, for `.` to redo a Visual operation on the same amount of text.
struct VShape: Equatable, Sendable { var mode: VimMode; var lines: Int; var cols: Int }

/// What the app has to do that the text and selection cannot say.
/// How the line-number ruler counts: Vim's `relativenumber`, and with `number` also `hybrid`.
public enum RelativeNumbers: String, CaseIterable, Sendable { case off, relative, hybrid }

public enum VimCommand: Equatable, Sendable {
    case undo(Int), redo(Int)
    case lineNumbers(RelativeNumbers)
    case save, close, saveAndClose
    case scroll(VimScroll)
}

public struct VimResult: Equatable, Sendable {
    /// False when the key is not Vim's (typing in Insert mode): the editor should process it itself.
    public var handled: Bool
    /// The selection after `edits`.
    public var selection: NSRange
    /// At most one replacement, against the text that was passed in.
    public var edits: [Replacement]
    public var mode: VimMode
    public var commands: [VimCommand]
    /// The unnamed register's new content, when this key changed it; linewise content ends in a newline.
    public var register: String?
    public var message: String?
    /// All matches of the active search (empty: highlighting is off); nil when unchanged since the last result.
    public var searchRanges: [NSRange]? = nil
}

/// A Vim emulation without any UI: feed it keys and the text; it returns the selection, one replacement and
/// commands for the app. The unnamed register is a plain string (linewise when it ends in a newline), so the
/// app can share it with the pasteboard.
public struct VimState: Sendable {
    public internal(set) var mode = VimMode.normal
    /// The keys of an unfinished command (`2d`, `f`, `"`).
    public internal(set) var pending = ""
    public var register = ""

    // Cursor model: in Normal mode the caret sits on a character; Visual keeps anchor and cursor, both inclusive.
    var cur = 0
    var anchor = 0
    var goal = 0
    var lastSel: NSRange?
    var lastFind: (kind: Character, ch: Character)?
    var lastSearch: (pat: String, forward: Bool)?
    var lastSub: (pat: String, rep: String, flags: String)?
    var lastChange: (keys: [Character], inserted: String?)?
    var lastChangeVis: VShape?
    var insertVis: VShape?
    var insert: (start: Int, count: Int, newline: Bool, keys: [Character])?
    /// `Ctrl-o` in Insert mode: one Normal command, then back; `eol`: the caret was after the last character.
    var ctrlO: (eol: Bool, start: Int)?
    /// Visual-block `I`, `A` and `c`: the lines the typed text is copied to on Esc, at `col` (nil: line ends).
    var blockIns: (l1: Int, l2: Int, col: Int?)?
    var marks: [Character: Int] = [:]
    var jumpPrev: Int?
    var visualMode = VimMode.visual
    var lastText: [UInt16]?
    var regSel: Character?
    var named: [Character: String] = [:]
    var yank0 = "", small = ""
    var numbered: [String] = []
    var recording: (reg: Character, keys: [VimKey])?
    var macros: [Character: [VimKey]] = [:]
    var lastMacro: Character?
    var macroDepth = 0
    var motionFailed = false
    var hlOn = false, hlDirty = false
    var hlText: [UInt16] = []
    var opSearch: (op: Character, count: Int?, keys: [Character], reg: Character?)?
    var cmdPrefix: Character = ":"
    var cmdText = ""
    var cmdBack = VimMode.normal

    // Per call.
    var d = VimDoc(u: [])
    var cmds: [VimCommand] = []
    var regChanged = false
    var message: String?
    var indent = IndentSettings.standard
    var pageLines = 30
    var visible: Range<Int>?
    var replaying = false
    var keepGoal = false
    var goalOverride: Int?
    var isChange = false

    public init() {}

    /// The cursor's offset; in Visual mode the end of the selection that moves.
    public var cursor: Int { cur }

    var isVisual: Bool { mode == .visual || mode == .visualLine || mode == .visualBlock }

    /// The mode line: `-- INSERT --`, `-- VISUAL --`, the command line being typed, or the pending keys.
    public var status: String {
        let p = String(pending.map { Self.display($0) }.joined())
        let rec = recording.map { " recording @" + String($0.reg) } ?? ""
        switch mode {
        case .insert: return "-- INSERT --" + rec
        case .visualBlock: return "-- VISUAL BLOCK --" + (p.isEmpty ? "" : " " + p) + rec
        case .visual: return "-- VISUAL --" + (p.isEmpty ? "" : " " + p) + rec
        case .visualLine: return "-- VISUAL LINE --" + (p.isEmpty ? "" : " " + p) + rec
        case .commandLine: return String(cmdPrefix) + cmdText
        case .normal, .operatorPending: return p.isEmpty ? "-- NORMAL --" + rec : p
        }
    }

    static func display(_ c: Character) -> String {
        guard let v = c.unicodeScalars.first?.value, v < 32 else { return String(c) }
        return "^" + String(Unicode.Scalar(v + 64)!)
    }

    // MARK: Entry point

    public mutating func handle(key: VimKey, in text: String, selection: NSRange, indent: IndentSettings = .standard, pageLines: Int = 30, visibleLines: Range<Int>? = nil) -> VimResult {
        d = VimDoc(u: Array(text.utf16))
        let before = d.u
        cmds = []; regChanged = false; message = nil
        self.indent = indent; self.pageLines = pageLines; visible = visibleLines
        if let lt = lastText, lt != before {                 // the editor changed the text itself (typing, undo)
            let r = Self.diff(lt, before)
            shiftMarks(at: r.range.location, removed: r.range.length, added: r.text.utf16.count)
        }
        let loc = max(0, min(selection.location, d.n))
        let sel = NSRange(location: loc, length: max(0, min(selection.length, d.n - loc)))
        let insertKeys: Set<Character> = [VimKey.esc, "\u{F}", "\u{17}", "\u{15}"]
        // Typing in Insert mode belongs to the editor, and so does an Esc with nothing to cancel.
        if (mode == .insert && !insertKeys.contains(key.token)) || (mode == .normal && pending.isEmpty && ctrlO == nil && key.token == VimKey.esc) {
            d = VimDoc(u: [])
            lastText = before
            if mode == .insert, recording != nil { recording!.keys.append(key) }
            return VimResult(handled: false, selection: sel, edits: [], mode: mode, commands: [], register: nil, message: nil)
        }
        if recording != nil { recording!.keys.append(key) }
        step(key, sel: sel)
        let out = finalSelection()
        lastSel = out
        var edits: [Replacement] = []
        if d.u != before { edits = [Self.diff(before, d.u)] }
        var ranges: [NSRange]?
        if hlOn {
            if hlDirty || d.u != hlText { ranges = highlightRanges(); hlText = d.u }
        } else if hlDirty { ranges = [] }
        hlDirty = false
        lastText = d.u
        d = VimDoc(u: [])
        return VimResult(handled: true, selection: out, edits: edits, mode: mode, commands: cmds, register: regChanged ? register : nil, message: message, searchRanges: ranges)
    }

    /// One key: from the editor (`sel` is its selection) or replayed from a macro (`sel` is nil).
    mutating func step(_ key: VimKey, sel: NSRange?) {
        motionFailed = false
        let startedInsert = mode == .insert
        switch mode {
        case .insert: insertKey(key, at: sel?.location ?? cur)
        case .commandLine: commandLineKey(key)
        default:
            if let sel { sync(sel) }
            keepGoal = false; goalOverride = nil; isChange = false
            if isVisual { marks["<"] = min(anchor, cur); marks[">"] = max(anchor, cur); visualMode = mode }
            feed(key.token)
            if mode != .insert, !keepGoal { goal = goalOverride ?? d.col(cur) }
        }
        if let o = ctrlO, !startedInsert, mode == .insert || mode == .normal && pending.isEmpty {
            ctrlO = nil
            if mode == .normal {
                let p = o.eol && cur == o.start ? d.lineEnd(cur) : cur
                mode = .insert; cur = p
                insert = (p, 1, false, [])
            }
        }
    }

    mutating func insertKey(_ key: VimKey, at loc: Int) {
        cur = max(0, min(loc, d.n))
        switch key.token {
        case VimKey.esc: leaveInsert(at: cur)
        case "\u{F}":
            ctrlO = (cur == d.lineEnd(cur), d.norm(cur))
            mode = .normal; pending = ""
        case "\u{17}", "\u{15}":                         // Ctrl-w, Ctrl-u
            let ls = d.lineStart(cur)
            var i = cur
            if key.token == "\u{15}" { i = ls } else {
                while i > ls, d.isBlank(d.u[i - 1]) { i -= 1 }
                if i > ls { let c = d.cls(i - 1, big: false); while i > ls, d.cls(i - 1, big: false) == c { i -= 1 } }
            }
            if i == cur, key.token == "\u{17}", cur > 0 { i = cur - 1 }
            guard i < cur else { return }
            splice(i, cur, [])
            cur = i
            if var ins = insert, ins.start > i { ins.start = i; insert = ins }
        default:                                            // only a replayed macro gets here
            switch key {
            case .char(let c): let u = Array(String(c).utf16); splice(cur, cur, u); cur += u.count
            case .returnKey: splice(cur, cur, [VimDoc.nl]); cur += 1
            case .tab: splice(cur, cur, [9]); cur += 1
            case .backspace: if cur > 0 { let p = d.prev(cur); splice(p, cur, []); cur = p }
            case .left: cur = d.prev(cur)
            case .right: cur = d.next(cur)
            default: break
            }
        }
    }

    /// Moves every mark behind an edit of `removed` units at `a` that inserted `added`.
    mutating func shiftMarks(at a: Int, removed: Int, added: Int) {
        func f(_ p: Int) -> Int { p >= a + removed ? p + added - removed : p <= a ? p : a + min(p - a, added) }
        for (k, v) in marks { marks[k] = f(v) }
        if let j = jumpPrev { jumpPrev = f(j) }
    }

    /// The smallest replacement turning `a` into `b`, kept clear of surrogate pairs.
    static func diff(_ a: [UInt16], _ b: [UInt16]) -> Replacement {
        let mn = min(a.count, b.count)
        var p = 0
        while p < mn, a[p] == b[p] { p += 1 }
        if p > 0, p < b.count, (0xDC00...0xDFFF).contains(b[p]) { p -= 1 }
        var s = 0
        while s < mn - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        if s > 0, (0xDC00...0xDFFF).contains(b[b.count - s]) { s -= 1 }
        return Replacement(range: NSRange(location: p, length: a.count - p - s), text: String(decoding: b[p..<(b.count - s)], as: UTF16.self))
    }

    /// Takes the editor's selection when something other than this engine moved it (a click, an undo).
    mutating func sync(_ sel: NSRange) {
        let moved = sel != lastSel
        if isVisual {
            if moved {
                anchor = sel.location
                cur = sel.length > 0 ? NSMaxRange(sel) - 1 : sel.location
                goal = d.col(cur)
            }
        } else if sel.length > 0 && moved {
            mode = .visual; pending = ""
            anchor = sel.location; cur = NSMaxRange(sel) - 1; goal = d.col(cur)
        } else {
            cur = d.norm(sel.location)
            if moved { goal = d.col(cur); pending = ""; mode = .normal }
        }
    }

    func finalSelection() -> NSRange {
        switch mode {
        case .insert: return NSRange(location: max(0, min(cur, d.n)), length: 0)
        case .visual, .visualBlock:
            let lo = max(0, min(min(anchor, cur), d.n)), hi = max(0, min(max(anchor, cur), d.n))
            var e = min(hi + 1, d.n)
            if e < d.n, (0xDC00...0xDFFF).contains(d.u[e]) { e += 1 }
            return NSRange(location: lo, length: max(0, e - lo))
        case .visualLine:
            let lo = d.lineStart(min(anchor, cur)), e = min(d.n, d.lineEnd(max(anchor, cur)) + 1)
            return NSRange(location: lo, length: max(0, e - lo))
        default: return NSRange(location: d.norm(cur), length: 0)
        }
    }

    // MARK: Keys

    mutating func feed(_ t: Character) {
        if t == VimKey.esc {
            pending = ""; regSel = nil
            if isVisual { mode = .normal; cur = d.norm(cur) } else { mode = .normal }
            return
        }
        if t == "q", pending.isEmpty, let rec = recording {      // `q` ends the recording (its own key is not part of it)
            let keys = Array(rec.keys.dropLast())
            let key = Character(rec.reg.lowercased())
            macros[key] = rec.reg.isUppercase ? (macros[key] ?? []) + keys : keys
            recording = nil
            return
        }
        pending.append(t)
        let prefixed = pending.first == "\""
        if prefixed, pending.count == 1 { return }
        if prefixed, pending.count == 2 {
            guard Self.registerNames.contains(t) else { pending = ""; if !isVisual { mode = .normal }; return }
            return
        }
        let body = prefixed ? Array(pending.dropFirst(2)) : Array(pending)
        switch Self.parse(body, visual: isVisual) {
        case .incomplete:
            if !isVisual { mode = Self.startsWithOperator(String(body)) ? .operatorPending : .normal }
        case .invalid:
            pending = ""; regSel = nil
            if !isVisual { mode = .normal }
        case .done(let cmd):
            let keys = Array(pending)
            regSel = prefixed ? pending[pending.index(after: pending.startIndex)] : nil
            pending = ""
            if !isVisual { mode = .normal }
            run(cmd, keys: keys)
        }
    }

    static let registerNames: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_+*\"")

    static func startsWithOperator(_ s: String) -> Bool {
        guard let f = s.first(where: { !($0.isASCII && $0.isNumber) }) else { return false }
        if f == "g" { return s.drop { !($0 == "g") }.dropFirst().first.map { "uU~".contains($0) } ?? false }
        return "dcy<>".contains(f)
    }

    mutating func run(_ cmd: VCmd, keys: [Character]) {
        defer { regSel = nil }
        let wasInsert = mode == .insert, wasVisual = isVisual
        let shape = wasVisual ? visShape() : nil
        switch cmd {
        case .motion(.obj(let inner, let ch), let count):
            if isVisual, let o = object(inner, ch, at: cur, count: count ?? 1), o.end > o.start {
                if o.linewise { mode = .visualLine }
                anchor = o.start; cur = o.end - 1
            }
        case .motion(let m, let count):
            if let r = evalMotion(m, count: count, from: cur, op: nil) {
                cur = d.norm(r.target)
                keepGoal = r.keepGoal; goalOverride = r.goal
            }
        case .op(let op, let target, let count): runOperator(op, target, count: count, keys: keys)
        case .opSearch(let op, let count):
            opSearch = (op, count, keys, regSel)
            cmdBack = .normal; cmdPrefix = keys.last!; cmdText = ""; mode = .commandLine
        case .simple(let k, let count, let arg):
            if isVisual { visualCommand(k, count: count, arg: arg) } else { simple(k, count: count, arg: arg, keys: keys) }
        case .cmdline(let p):
            if isVisual { mode = .normal; cur = d.norm(cur) }
            cmdBack = .normal; cmdPrefix = p; cmdText = wasVisual && p == ":" ? "'<,'>" : ""; mode = .commandLine
        }
        finishChange(keys: keys, wasInsert: wasInsert, shape: shape)
    }

    /// Remembers what `.` repeats once a command has changed the text.
    mutating func finishChange(keys: [Character], wasInsert: Bool, shape: VShape?) {
        guard isChange, !replaying else { return }
        if mode == .insert, !wasInsert {
            if insert != nil { insert!.keys = keys; insertVis = shape }
        } else if mode != .insert {
            lastChange = (keys, nil); lastChangeVis = shape
        }
    }

    func visShape() -> VShape {
        let starts = d.lineStarts()
        let la = lineIndex(starts, anchor), lc = lineIndex(starts, cur)
        let lines = abs(la - lc) + 1
        let lo = min(anchor, cur), hi = max(anchor, cur)
        switch mode {
        case .visualLine: return VShape(mode: mode, lines: lines, cols: 0)
        case .visualBlock:
            let b = block()
            return VShape(mode: mode, lines: lines, cols: b.eol ? Int.max : b.c2 - b.c1 + 1)
        default: return VShape(mode: .visual, lines: lines, cols: lines == 1 ? hi - lo + 1 : d.col(hi) + 1)
        }
    }

    /// Selects the same amount of text from the cursor as `v` described.
    mutating func restore(_ v: VShape) {
        let starts = d.lineStarts()
        let l = lineIndex(starts, cur), l2 = min(l + v.lines - 1, max(d.lastLine, l))
        let col = d.col(cur)
        anchor = cur; mode = v.mode
        let le2 = d.lineEnd(starts[l2])
        switch v.mode {
        case .visualLine: cur = starts[l2]
        case .visualBlock:
            if v.cols == Int.max { goal = Int.max; cur = max(starts[l2], le2 - 1) }
            else { cur = min(starts[l2] + col + v.cols - 1, max(starts[l2], le2 - 1)) }
        default:
            if v.lines == 1 { cur = min(cur + v.cols - 1, max(cur, d.lineEnd(cur) - 1)) }
            else { cur = min(starts[l2] + v.cols - 1, max(starts[l2], le2 - 1)) }
        }
    }

    // MARK: Insert

    mutating func enterInsert(at p: Int, count: Int = 1, newline: Bool = false) {
        mode = .insert
        cur = max(0, min(p, d.n))
        insert = (cur, count, newline, [])
        isChange = true
    }

    mutating func leaveInsert(at loc: Int) {
        var p = max(0, min(loc, d.n))
        if let ins = insert {
            let typed = p >= ins.start ? d.str(ins.start, p) : ""
            if ins.count > 1, !typed.isEmpty {
                let extra = String(repeating: (ins.newline ? "\n" : "") + typed, count: ins.count - 1)
                splice(p, p, Array(extra.utf16))
                p += extra.utf16.count
            }
            if !replaying, !ins.keys.isEmpty { lastChange = (ins.keys, typed); lastChangeVis = insertVis }
            if let b = blockIns {
                blockIns = nil
                if !typed.isEmpty, !typed.contains("\n") {
                    let starts = d.lineStarts(), t = Array(typed.utf16)
                    for l in stride(from: min(b.l2, starts.count - 1), to: b.l1, by: -1) {
                        let ls = starts[l], le = d.lineEnd(ls)
                        if let c = b.col { if ls + c <= le { splice(ls + c, ls + c, t) } } else { splice(le, le, t) }
                    }
                }
                insert = nil; mode = .normal
                cur = d.norm(ins.start)
                return
            }
        }
        insert = nil
        mode = .normal
        cur = d.norm(p > d.lineStart(p) ? p - 1 : p)
    }

    mutating func repeatLastChange(count: Int?) {
        guard let ch = lastChange else { return }
        var keys = ch.keys
        var prefix: [Character] = []
        if keys.first == "\"", keys.count >= 2 { prefix = Array(keys[0..<2]); keys.removeFirst(2) }
        if let c = count, lastChangeVis == nil {
            while let f = keys.first, f.isASCII, f.isNumber { keys.removeFirst() }
            keys = Array(String(c)) + keys
        }
        keys = prefix + keys
        replaying = true
        defer { replaying = false; isChange = false }
        if let v = lastChangeVis { restore(v) }
        for k in keys {
            if mode == .commandLine { commandLineKey(k == "\r" ? .returnKey : .char(k)) } else { feed(k) }
        }
        guard mode == .insert else { return }
        let text = Array((ch.inserted ?? "").utf16)
        splice(cur, cur, text)
        leaveInsert(at: cur + text.count)
        isChange = true
    }

    // MARK: Editing helpers

    mutating func splice(_ a: Int, _ b: Int, _ text: [UInt16]) {
        let a = max(0, a), b = max(a, min(b, d.n))
        d.u.replaceSubrange(a..<b, with: text)
        shiftMarks(at: a, removed: b - a, added: text.count)
    }

    /// Stores yanked or deleted text where the `"x` prefix says (the unnamed register, which is the pasteboard, follows).
    mutating func setRegister(_ s: String, yank: Bool = false, ignoreSel: Bool = false) {
        let sel = ignoreSel ? nil : regSel
        if sel == "_" { return }
        regChanged = true
        if let r = sel, r.isASCII, r.isLetter {
            let key = Character(r.lowercased())
            var v = s
            if r.isUppercase, let old = named[key], !old.isEmpty {
                v = old.hasSuffix("\n") && !s.hasSuffix("\n") ? old + s + "\n" : !old.hasSuffix("\n") && s.hasSuffix("\n") ? old + "\n" + s : old + s
            }
            named[key] = v; register = v
            return
        }
        register = s
        guard sel == nil || sel == "0" || sel == "-" || sel?.isNumber == true else { return }   // "+ and "* are the unnamed register
        if yank { yank0 = s }
        else if s.contains("\n") { numbered.insert(s, at: 0); if numbered.count > 9 { numbered.removeLast() } }
        else { small = s }
    }

    /// What `"x` before a paste names.
    func readRegister() -> String {
        guard let r = regSel else { return register }
        switch r {
        case "_": return ""
        case "0": return yank0
        case "-": return small
        case "1"..."9": let i = Int(String(r))! - 1; return i < numbered.count ? numbered[i] : ""
        default:
            if r.isASCII, r.isLetter { return named[Character(r.lowercased())] ?? "" }
            return register
        }
    }

    /// The `:reg` listing, on one line.
    func registerListing() -> String {
        func show(_ v: String) -> String {
            let t = v.replacingOccurrences(of: "\n", with: "^J").replacingOccurrences(of: "\t", with: "^I")
            return t.count > 24 ? String(t.prefix(24)) + "…" : t
        }
        var out: [String] = []
        func add(_ name: String, _ v: String) { if !v.isEmpty { out.append("\"" + name + " " + show(v)) } }
        add("\"", register); add("0", yank0)
        for (i, v) in numbered.enumerated() { add(String(i + 1), v) }
        add("-", small)
        for k in named.keys.sorted() { add(String(k), named[k]!) }
        return out.isEmpty ? "No registers" : out.joined(separator: "   ")
    }

    func lineIndex(_ starts: [Int], _ i: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= i { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    func indentOf(line i: Int) -> [UInt16] {
        let ls = d.lineStart(i), le = d.lineEnd(i)
        var j = ls
        while j < le, d.isBlank(d.u[j]) { j += 1 }
        return Array(d.u[ls..<j])
    }

    static func toggleCase(_ s: String, _ mode: Character) -> String {
        String(s.map { c -> String in
            let lo = c.lowercased(), up = c.uppercased()
            switch mode {
            case "u": return lo
            case "U": return up
            default: return String(c) == up ? lo : up
            }
        }.joined())
    }
}
