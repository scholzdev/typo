import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

/// Types keys into a `VimState` over a text, doing in Insert mode what the editor would.
struct VimHarness {
    var text: NSString
    var sel: NSRange
    var state = VimState()
    var commands: [VimCommand] = []
    var message: String?
    var indent = IndentSettings.standard
    var visible: Range<Int>?
    var handledLast = true
    var highlights: [NSRange] = []

    /// `|` marks the caret.
    init(_ s: String) {
        let ns = s as NSString
        let bar = ns.range(of: "|")
        if bar.location == NSNotFound { text = ns; sel = NSRange(location: 0, length: 0) } else {
            text = ns.replacingCharacters(in: bar, with: "") as NSString
            sel = NSRange(location: bar.location, length: 0)
        }
    }

    @discardableResult
    mutating func keys(_ s: String) -> VimHarness {
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "<", let close = s[i...].firstIndex(of: ">"), close > s.index(after: i) {
                let name = String(s[s.index(after: i)..<close])
                let special: VimKey? = switch name {
                case "Esc": .escape
                case "CR": .returnKey
                case "BS": .backspace
                case "Left": .left
                case "Right": .right
                case "Up": .up
                case "Down": .down
                case "lt": .char("<")
                default: name.hasPrefix("C-") ? .ctrl(name.last!) : nil
                }
                if let special { press(special); i = s.index(after: close); continue }
            }
            press(.char(s[i]))
            i = s.index(after: i)
        }
        return self
    }

    mutating func press(_ key: VimKey) {
        let r = state.handle(key: key, in: text as String, selection: sel, indent: indent, visibleLines: visible)
        handledLast = r.handled
        if let h = r.searchRanges { highlights = h }
        if !r.handled {
            switch key {
            case .char(let c): type(String(c))
            case .returnKey: type("\n")
            case .backspace: if sel.location > 0 { text = text.replacingCharacters(in: NSRange(location: sel.location - 1, length: 1), with: "") as NSString; sel = NSRange(location: sel.location - 1, length: 0) }
            default: break
            }
            return
        }
        for e in r.edits { text = text.replacingCharacters(in: e.range, with: e.text) as NSString }
        sel = r.selection
        commands += r.commands
        message = r.message
        // Commands the app runs on the text.
        for c in r.commands { if case .undo = c { sel = NSRange(location: sel.location, length: 0) } }
    }

    mutating func type(_ s: String) {
        text = text.replacingCharacters(in: sel, with: s) as NSString
        sel = NSRange(location: sel.location + (s as NSString).length, length: 0)
    }

    /// The text with `|` at the caret, or `[…]` around a selection.
    var shown: String {
        if sel.length == 0 { return text.replacingCharacters(in: sel, with: "|") }
        let closed = text.replacingCharacters(in: NSRange(location: NSMaxRange(sel), length: 0), with: "]") as NSString
        return closed.replacingCharacters(in: NSRange(location: sel.location, length: 0), with: "[")
    }
}

@Suite struct VimTests {
    func run(_ start: String, _ keys: String) -> String {
        var h = VimHarness(start)
        h.keys(keys)
        return h.shown
    }

    // MARK: Motions

    @Test func charAndLineMotions() {
        #expect(run("|abc", "l") == "a|bc")
        #expect(run("|abc", "3l") == "ab|c")
        #expect(run("ab|c", "h") == "a|bc")
        #expect(run("|abc", "<Right><Right><Left>") == "a|bc")
        #expect(run("|ab\ncd\nef", "j") == "ab\n|cd\nef")
        #expect(run("|ab\ncd\nef", "2j") == "ab\ncd\n|ef")
        #expect(run("|ab\ncd\nef", "5j") == "ab\ncd\n|ef")
        #expect(run("ab\ncd\n|ef", "k") == "ab\n|cd\nef")
        #expect(run("ab\ncd\n|ef", "<Up><Up>") == "|ab\ncd\nef")
        #expect(run("ab\ncd|\nef", "<Down>") == "ab\ncd\ne|f")
        // The wanted column survives a short line.
        #expect(run("abcd|\nx\nabcd", "jj") == "abcd\nx\nabc|d")
        #expect(run("a|bcd\nx\nabcd", "jj") == "abcd\nx\na|bcd")
        #expect(run("|abc\n", "l$") == "ab|c\n")
    }

    @Test func wordMotions() {
        #expect(run("|foo bar baz", "w") == "foo |bar baz")
        #expect(run("|foo bar baz", "2w") == "foo bar |baz")
        #expect(run("|foo.bar baz", "w") == "foo|.bar baz")
        #expect(run("|foo.bar baz", "W") == "foo.bar |baz")
        #expect(run("|foo bar", "e") == "fo|o bar")
        #expect(run("fo|o bar", "e") == "foo ba|r")
        #expect(run("foo.ba|r", "b") == "foo.|bar")
        #expect(run("foo.bar| baz", "B") == "|foo.bar baz")
        #expect(run("foo bar|", "b") == "foo |bar")
        #expect(run("|foo\nbar", "w") == "foo\n|bar")
        #expect(run("|foo\n\nbar", "w") == "foo\n|\nbar")
        #expect(run("|foo bar", "E") == "fo|o bar")
        #expect(run("|foo bar baz", "$b") == "foo bar |baz")
    }

    @Test func lineEdges() {
        #expect(run("  fo|o bar", "0") == "|  foo bar")
        #expect(run("  fo|o bar", "^") == "  |foo bar")
        #expect(run("|foo bar", "$") == "foo ba|r")
        #expect(run("|a\nb\nc", "2$") == "a\n|b\nc")
        #expect(run("a\nb\n|c", "gg") == "|a\nb\nc")
        #expect(run("a\n  b\n|c", "2gg") == "a\n  |b\nc")
        #expect(run("|a\nb\n  c", "G") == "a\nb\n  |c")
        #expect(run("|a\n  b\nc", "2G") == "a\n  |b\nc")
        #expect(run("|a\nb\n", "G") == "a\n|b\n")
    }

    @Test func findMotions() {
        #expect(run("|a,b,c", "f,") == "a|,b,c")
        #expect(run("|a,b,c", "2f,") == "a,b|,c")
        #expect(run("a,b,|c", "F,") == "a,b|,c")
        #expect(run("|a,b,c", "t,") == "|a,b,c")
        #expect(run("|ab,c", "t,") == "a|b,c")
        #expect(run("ab,|c", "T,") == "ab,|c")
        #expect(run("a,bc|d", "T,") == "a,|bcd")
        #expect(run("|a,b,c,d", "f,;") == "a,b|,c,d")
        #expect(run("|a,b,c,d", "f,;,") == "a|,b,c,d")
        #expect(run("|a,b,c,d", "t,;") == "a,|b,c,d")
        #expect(run("|abc", "fz") == "|abc")
    }

    @Test func matchAndParagraph() {
        #expect(run("|(a [b] c)", "%") == "(a [b] c|)")
        #expect(run("(a [b] c|)", "%") == "|(a [b] c)")
        #expect(run("(a |[b] c)", "%") == "(a [b|] c)")
        #expect(run("f|oo (a)", "%") == "foo (a|)")
        #expect(run("a\nb\n\nc\nd", "}") == "a\nb\n|\nc\nd")
        #expect(run("a\nb\n\nc\nd", "}}") == "a\nb\n\nc\n|d")
        #expect(run("a\n\nb\nc|", "{") == "a\n|\nb\nc")
        #expect(run("a\n\nb\nc|", "{{") == "|a\n\nb\nc")
    }

    // MARK: Operators

    @Test func deleteWithMotions() {
        #expect(run("|foo bar baz", "dw") == "|bar baz")
        #expect(run("|foo bar baz", "2dw") == "|baz")
        #expect(run("|foo bar baz", "d2w") == "|baz")
        #expect(run("foo |bar baz", "db") == "|bar baz")
        #expect(run("|foo bar", "de") == "| bar")
        #expect(run("foo |bar", "d$") == "foo| ")
        #expect(run("foo |bar", "D") == "foo| ")
        #expect(run("foo |bar", "d0") == "|bar")
        #expect(run("  foo |bar", "d^") == "  |bar")
        #expect(run("|a,b,c", "df,") == "|b,c")
        #expect(run("|a,b,c", "dt,") == "|,b,c")
        #expect(run("a,b,|c", "dF,") == "a,b|c")
        #expect(run("|foo\nbar", "dw") == "|\nbar")
        #expect(run("foo |bar\nbaz", "dw") == "foo| \nbaz")
        #expect(run("|(a b)", "d%") == "|")
        #expect(run("a|bc", "dh") == "|bc")
        #expect(run("a|bc", "dl") == "a|c")
        #expect(run("a|bc", "x") == "a|c")
        #expect(run("a|bc", "2x") == "|a")
        #expect(run("ab|c", "X") == "a|c")
        #expect(run("|", "x") == "|")
    }

    @Test func deleteLines() {
        #expect(run("a\n|b\nc", "dd") == "a\n|c")
        #expect(run("a\nb\n|c", "dd") == "a\n|b")
        #expect(run("|a", "dd") == "|")
        #expect(run("a\n|b\nc\nd", "2dd") == "a\n|d")
        #expect(run("a\n|b\nc\nd", "d2d") == "a\n|d")
        #expect(run("a\n|b\nc\nd", "dj") == "a\n|d")
        #expect(run("a\nb\n|c\nd", "dk") == "a\n|d")
        #expect(run("a\n|b\nc\nd", "9dd") == "|a") // clamped at the end; the last newline stays
        #expect(run("  a\n  |b\n  c", "dd") == "  a\n  |c")
        #expect(run("|a\nb\n\nc", "d}") == "|\nc")
        #expect(run("a\n|b\n\nc", "dG") == "|a")
        #expect(run("a\n|b\n\nc", "dgg") == "|\nc")
        #expect(run("a\nb|\n", "dd") == "|a\n")
    }

    @Test func changeAndYank() {
        #expect(run("|foo bar", "cwxy<Esc>") == "x|y bar")
        #expect(run("foo |bar baz", "cwX<Esc>") == "foo |X baz")
        #expect(run("fo|o bar", "cwX<Esc>") == "fo|X bar")
        #expect(run("|foo bar", "2cwX<Esc>") == "|X")
        #expect(run("|foo bar", "ceX<Esc>") == "|X bar")
        #expect(run("foo |bar", "C!<Esc>") == "foo |!")
        #expect(run("a\n  |b\nc", "ccX<Esc>") == "a\n  |X\nc")
        #expect(run("a\n|b\nc", "SX<Esc>") == "a\n|X\nc")
        #expect(run("a|bc", "sX<Esc>") == "a|Xc")
        #expect(run("a|bc", "3sX<Esc>") == "a|X")
        #expect(run("|foo bar", "yw$p") == "foo barfoo| ")
        #expect(run("|foo bar", "ywP") == "foo| foo bar")
        #expect(run("foo |bar", "yb$p") == "foo barfoo| ")
        #expect(run("|a\nb", "yyp") == "a\n|a\nb")
        #expect(run("|a\nb", "yyP") == "|a\na\nb")
        #expect(run("|a\nb", "Yjp") == "a\nb\n|a")
        #expect(run("|a\nb", "yy2p") == "a\n|a\na\nb")
        #expect(run("|a\nb", "yjGp") == "a\nb\n|a\nb")
        #expect(run("a\nb|", "ddP") == "|b\na")
        #expect(run("|abc", "ylp") == "a|abc")
        #expect(run("|abc", "yl3p") == "aaa|abc")
        #expect(run("|ab", "xp") == "b|a")
    }

    @Test func registerIsPlainString() {
        var h = VimHarness("|foo bar")
        var r = h.state.handle(key: .char("y"), in: "foo bar", selection: h.sel)
        #expect(r.register == nil)
        r = h.state.handle(key: .char("w"), in: "foo bar", selection: h.sel)
        #expect(r.register == "foo ")
        h.state.register = "from clipboard"
        h.keys("P")
        #expect(h.shown == "from clipboar|dfoo bar")
        h.state.register = "x\ny\n"
        h.keys("p")
        #expect(h.text as String == "from clipboardfoo bar\nx\ny")
        var l = VimHarness("a|b")
        l.keys("dd")
        #expect(l.state.register == "ab\n")
    }

    @Test func replaceJoinCase() {
        #expect(run("|abc", "rx") == "|xbc")
        #expect(run("|abc", "3rx") == "xx|x")
        #expect(run("|abc", "4rx") == "|abc")
        #expect(run("|ab", "r<CR>") == "\n|b")
        #expect(run("|a\n  b\nc", "J") == "a| b\nc")
        #expect(run("|a\nb\nc\nd", "3J") == "a b| c\nd")
        #expect(run("|a\n)b", "J") == "a|)b")
        #expect(run("a \n|b", "kJ") == "a |b")
        #expect(run("|abc", "~") == "A|bc")
        #expect(run("|abc", "5~") == "AB|C")
        #expect(run("|aBc", "3~") == "Ab|C")
        #expect(run("a|b\ncd", "j~") == "ab\nc|D")
    }

    // MARK: Text objects

    @Test func wordObjects() {
        #expect(run("foo b|ar baz", "diw") == "foo | baz")
        #expect(run("foo b|ar baz", "daw") == "foo |baz")
        #expect(run("foo bar b|az", "daw") == "foo ba|r")
        #expect(run("foo b|ar baz", "ciwX<Esc>") == "foo |X baz")
        #expect(run("foo.b|ar", "diw") == "foo|.")
        #expect(run("foo b|ar", "yiwP") == "foo ba|rbar")
        #expect(run("foo|  bar", "diw") == "foo|bar")
        #expect(run("a|.b c", "diW") == "| c")
    }

    @Test func bracketObjects() {
        #expect(run("f(a, |b)", "di(") == "f(|)")
        #expect(run("f(a, |b)", "da(") == "|f")
        #expect(run("f(a, |b)", "dib") == "f(|)")
        #expect(run("f(a, b|)", "di)") == "f(|)")
        #expect(run("|f(a)", "di(") == "|f(a)")
        #expect(run("f(|(a), b)", "di(") == "f((|), b)")
        #expect(run("f((a), |b)", "di(") == "f(|)")
        #expect(run("[a, |b]", "di[") == "[|]")
        #expect(run("[a, |b]", "da]") == "|")
        #expect(run("{a |b}", "di{") == "{|}")
        #expect(run("{a |b}", "ciBx<Esc>") == "{|x}")
        #expect(run("f(a, |b)", "ci(X<Esc>") == "f(|X)")
        #expect(run("x = (1 + (2 |* 3))", "da(") == "x = (1 + |)")
        #expect(run("f {\n  a\n  |b\n}", "di{") == "f {\n|}")
        #expect(run("f {\n  a\n  |b\n}", "ci{X<Esc>") == "f {\n  |X\n}")
        #expect(run("f {\n  a\n  |b\n}", "da{") == "f| ")
    }

    @Test func quoteObjects() {
        #expect(run("say \"he|llo\" now", "di\"") == "say \"|\" now")
        #expect(run("say \"he|llo\" now", "da\"") == "say |now")
        #expect(run("say |\"hello\" now", "di\"") == "say \"|\" now")
        #expect(run("|say \"hello\" now", "di\"") == "say \"|\" now")
        #expect(run("\"a\" \"|b\"", "di\"") == "\"a\" \"|\"")
        #expect(run("\"a\" |\"b\" \"c\"", "ci\"X<Esc>") == "\"a\" \"|X\" \"c\"")
        #expect(run("x = \"a\\\"b|c\"", "di\"") == "x = \"|\"")
        #expect(run("'a|b'", "di'") == "'|'")
        #expect(run("say \"hello\" |now", "di\"") == "say \"hello\" |now")
        #expect(run("a \"b|\"", "da\"") == "|a")
    }

    @Test func paragraphObjects() {
        #expect(run("a\nb|\n\nc", "dip") == "|\nc")
        #expect(run("a\nb|\n\nc", "dap") == "|c")
        #expect(run("a\n\nb|\nc", "dap") == "|a")
        #expect(run("a\n|\nb", "dip") == "a\n|b")
        #expect(run("a\nb|\n\nc", "yipP") == "|a\nb\na\nb\n\nc")
    }

    // MARK: Insert

    @Test func insertEntries() {
        #expect(run("a|bc", "iX<Esc>") == "a|Xbc")
        #expect(run("a|bc", "aX<Esc>") == "ab|Xc")
        #expect(run("  a|bc", "IX<Esc>") == "  |Xabc")
        #expect(run("a|bc", "AX<Esc>") == "abc|X")
        #expect(run("  a|bc\nd", "oX<Esc>") == "  abc\n  |X\nd")
        #expect(run("  a|bc\nd", "OX<Esc>") == "  |X\n  abc\nd")
        #expect(run("a|bc", "3iX<Esc>") == "aXX|Xbc")
        #expect(run("a|bc", "2oX<Esc>") == "abc\nX\n|X")
        #expect(run("|", "iab<Esc>") == "a|b")
        #expect(run("abc|", "a<Esc>") == "ab|c")
        #expect(run("|abc", "i<Esc>") == "|abc")
        #expect(run("a\n|b", "i<Esc>") == "a\n|b")
        // Normal mode swallows keys it does not know.
        #expect(run("|abc", "Qz") == "|abc")
        var h = VimHarness("|abc")
        h.keys("i")
        #expect(h.state.mode == .insert)
        h.keys("<Esc>")
        #expect(h.state.mode == .normal)
        h.keys("v<Esc>")
        #expect(h.state.mode == .normal)
        h.keys("v")
        #expect(h.state.mode == .visual)
        h.keys("<C-[>")
        #expect(h.state.mode == .normal)
    }

    @Test func insertModeKeysAreNotHandled() {
        var s = VimState()
        _ = s.handle(key: .char("i"), in: "abc", selection: NSRange(location: 0, length: 0))
        let r = s.handle(key: .char("x"), in: "abc", selection: NSRange(location: 0, length: 0))
        #expect(!r.handled && r.edits.isEmpty && r.mode == .insert)
    }

    @Test func pendingAndModes() {
        var h = VimHarness("|abc")
        h.keys("2d")
        #expect(h.state.mode == .operatorPending)
        #expect(h.state.status == "2d")
        h.keys("<Esc>")
        #expect(h.state.mode == .normal && h.state.pending.isEmpty)
        h.keys("f")
        #expect(h.state.status == "f")
        h.keys("x")
        #expect(h.state.status == "-- NORMAL --")
        h.keys("i")
        #expect(h.state.status == "-- INSERT --")
        h.keys("<Esc>V")
        #expect(h.state.status == "-- VISUAL LINE --")
        // A bad key drops the pending command instead of wedging.
        h.keys("<Esc>dq")
        #expect(h.state.mode == .normal && h.state.pending.isEmpty)
    }

    // MARK: Dot, undo, commands

    @Test func dotRepeat() {
        #expect(run("|a b c d", "dw.") == "|c d")
        #expect(run("|a b c d e", "2dw.") == "|e")
        #expect(run("|a b c d e", "dw3.") == "|e")
        #expect(run("|foo bar baz", "ciwX<Esc>w.") == "X |X baz")
        #expect(run("|abc", "x.") == "|c")
        #expect(run("|a\nb\nc\nd", "dd.") == "|c\nd")
        #expect(run("|ab", "iX<Esc>j.") == "|XXab")
        #expect(run("|a\nb", "AX<Esc>j.") == "aX\nb|X")
        #expect(run("|a\nb", "oY<Esc>.") == "a\nY\n|Y\nb")
        #expect(run("|abcdef", "rxl.") == "x|xcdef")
        #expect(run("|ab", "~.") == "A|B")
        #expect(run("|a\nb\nc", "J.") == "a b| c")
        #expect(run("  |a\nb", ">>.") == "      |a\nb")
        // Yank does not count as a change.
        #expect(run("|a b c", "dwyw.") == "|c")
    }

    @Test func undoRedoAreCommands() {
        var h = VimHarness("|abc")
        h.keys("3u")
        #expect(h.commands == [.undo(3)])
        h.commands = []
        h.keys("<C-r>")
        #expect(h.commands == [.redo(1)])
    }

    @Test func exCommands() {
        var h = VimHarness("a\nb\nc\nd|")
        h.keys(":w<CR>")
        #expect(h.commands == [.save] && h.state.mode == .normal)
        h.commands = []
        h.keys(":q<CR>:wq<CR>:x<CR>")
        #expect(h.commands == [.close, .saveAndClose, .saveAndClose])
        h.commands = []
        h.keys(":2<CR>")
        #expect(h.shown == "a\n|b\nc\nd")
        h.keys(":$<CR>")
        #expect(h.shown == "a\nb\nc\n|d")
        h.keys(":99<CR>")
        #expect(h.shown == "a\nb\nc\n|d")
        h.keys(":1<CR>")
        #expect(h.shown == "|a\nb\nc\nd")
        h.keys(":bogus<CR>")
        #expect(h.message == "Not an editor command: bogus")
        h.keys(":wx<BS><BS><BS><Esc>")
        #expect(h.state.mode == .normal && h.commands.isEmpty)
        h.keys(":")
        #expect(h.state.status == ":")
        h.keys("w")
        #expect(h.state.status == ":w" && h.state.mode == .commandLine)
        h.keys("<Esc>")
        #expect(h.commands.isEmpty)
    }

    @Test func scrollCommands() {
        var h = VimHarness("|a")
        h.keys("zzztzb")
        #expect(h.commands == [.scroll(.center), .scroll(.top), .scroll(.bottom)])
    }

    // MARK: Search

    @Test func search() {
        #expect(run("|a b a c a", "/a<CR>") == "a b |a c a")
        #expect(run("|a b a c a", "/a<CR>n") == "a b a c |a")
        #expect(run("|a b a c a", "/a<CR>nn") == "|a b a c a")
        #expect(run("|a b a c a", "/a<CR>N") == "|a b a c a")
        #expect(run("a b a c |a", "?a<CR>") == "a b |a c a")
        #expect(run("a b a c |a", "?a<CR>n") == "|a b a c a")
        #expect(run("a b a c |a", "?a<CR>N") == "a b a c |a")
        #expect(run("|foo x foobar foo", "*") == "foo x foobar |foo")
        #expect(run("foo x foobar |foo", "*") == "|foo x foobar foo")
        #expect(run("foo x foobar |foo", "#") == "|foo x foobar foo")
        #expect(run("|abc abd", "/ab<CR>") == "abc |abd")
        var h = VimHarness("|abc")
        h.keys("/zzz<CR>")
        #expect(h.message?.hasPrefix("Pattern not found") == true)
        #expect(h.shown == "|abc")
        h.keys("/<BS>")
        #expect(h.state.mode == .normal)
        // `/<CR>` reuses the last pattern.
        var g = VimHarness("|a b a c a")
        g.keys("/a<CR>/<CR>")
        #expect(g.shown == "a b a c |a")
        // `dn` deletes up to the next match.
        #expect(run("|a b a", "/a<CR>gg") == "|a b a")
        #expect(run("|x a b a", "/a<CR>0dn") == "|a b a")
    }

    // MARK: Visual

    @Test func visualCharwise() {
        #expect(run("|abc def", "vl") == "[ab]c def")
        #expect(run("|abc def", "vld") == "|c def")
        #expect(run("|abc def", "vey$p") == "abc defab|c")
        #expect(run("|abc def", "vwd") == "|ef")
        #expect(run("abc |def", "vbd") == "|ef")
        #expect(run("|abc def", "vly") == "|abc def")
        #expect(run("|abc def", "vlyP") == "a|babc def")
        #expect(run("|abc def", "vlcX<Esc>") == "|Xc def")
        #expect(run("|abc def", "viwd") == "| def")
        #expect(run("abc d|ef", "vawd") == "ab|c")
        #expect(run("f(a|b)", "vi(d") == "f(|)")
        #expect(run("|abc", "vlo") == "[ab]c")
        #expect(run("|abc", "vlld") == "|")
        #expect(run("|abc", "vlv") == "a|bc")
        #expect(run("|abc", "vlx") == "|c")
        #expect(run("|abc", "vl~") == "|ABc")
        #expect(run("|aBc", "vlu") == "|abc")
        #expect(run("|abc", "vlU") == "|ABc")
        #expect(run("|abcd", "vlrx") == "|xxcd")
        #expect(run("|ab\ncd", "vjd") == "|d")
        #expect(run("|ab\ncd", "vJ") == "ab| cd")
        #expect(run("|abc", "vl<Esc>l") == "ab|c")
    }

    @Test func visualPaste() {
        var h = VimHarness("|abc def")
        h.state.register = "XY"
        h.keys("vep")
        #expect(h.shown == "X|Y def")
        #expect(h.state.register == "abc")
    }

    @Test func visualLine() {
        #expect(run("a\n|b\nc", "Vd") == "a\n|c")
        #expect(run("a\n|b\nc\nd", "Vjd") == "a\n|d")
        #expect(run("a\nb|\nc\nd", "Vkd") == "|c\nd")
        #expect(run("a\n|b\nc", "Vy") == "a\n|b\nc")
        #expect(run("a\n|b\nc", "VyGp") == "a\nb\nc\n|b")
        #expect(run("a\n|b\nc", "Vcx<Esc>") == "a\n|x\nc")
        #expect(run("|a\nb", "V") == "[a\n]b")
        #expect(run("|a\nb", "Vj") == "[a\nb]")
        #expect(run("|a\nb\nc", "VjJ") == "a| b\nc")
        #expect(run("|ab\nc", "vVd") == "|c")
        #expect(run("|ab\nc", "Vvd") == "|b\nc")
    }

    @Test func indentOperators() {
        var h = VimHarness("|a\nb\n\nc")
        h.keys(">>")
        #expect(h.text as String == "  a\nb\n\nc")
        h.keys("<<")
        #expect(h.text as String == "a\nb\n\nc")
        h.keys("2>>")
        #expect(h.text as String == "  a\n  b\n\nc")
        h.keys("G")
        h.keys("<lt><lt>")
        #expect(h.text as String == "  a\n  b\n\nc")
        h.keys("ggVj>")
        #expect(h.text as String == "    a\n    b\n\nc")
        h.keys("Vj2<lt>")
        #expect(h.text as String == "a\nb\n\nc")
        h.keys(">j")
        #expect(h.text as String == "  a\n  b\n\nc")
        h.keys("g>")   // unknown: ignored
        // The buffer's indent settings decide the unit.
        var t = VimHarness("|a")
        t.indent.useTabs = true
        t.keys(">>")
        #expect(t.text as String == "\ta")
        t.keys("<lt><lt>")
        #expect(t.text as String == "a")
        var w = VimHarness("|a")
        w.indent.indentWidth = 4
        w.keys(">>>>")
        #expect(w.text as String == "        a")
        w.keys("<lt><lt>")
        #expect(w.text as String == "    a")
    }

    // MARK: Editor interplay

    @Test func externalSelectionMovesResync() {
        var s = VimState()
        let text = "abc def"
        // A drag selection in Normal mode starts Visual mode on it.
        var r = s.handle(key: .char("l"), in: text, selection: NSRange(location: 2, length: 3))
        #expect(r.mode == .visual)
        #expect(r.selection == NSRange(location: 2, length: 4))
        // A click while in Visual mode re-anchors.
        r = s.handle(key: .char("l"), in: text, selection: NSRange(location: 5, length: 0))
        #expect(r.selection == NSRange(location: 5, length: 2))
    }

    @Test func insertedTextIsRepeatedWithTheCount() {
        var h = VimHarness("|")
        h.keys("3iab<Esc>")
        #expect(h.shown == "ababa|b")
        var o = VimHarness("|x")
        o.keys("3oa<Esc>")
        #expect(o.shown == "x\na\na\n|a")
    }

    @Test func edgeCases() {
        #expect(run("|", "dd") == "|")
        #expect(run("|", "w") == "|")
        #expect(run("|", "$") == "|")
        #expect(run("|", "p") == "|")
        #expect(run("|", "J") == "|")
        #expect(run("|a", "dw") == "|")
        #expect(run("|a", "d}") == "|")
        #expect(run("|", "yyp") == "|\n")
        #expect(run("|😀a", "x") == "|a")
        #expect(run("|😀a", "l") == "😀|a")
        #expect(run("😀|a", "h") == "|😀a")
        #expect(run("|a😀", "xp") == "😀|a")
        #expect(run("|foo", "d99w") == "|")
        #expect(run("|abc", "99l") == "ab|c")
        #expect(run("|abc", "0") == "|abc")
    }

    @Test func largeDocumentKeepsUp() {
        let text = String(repeating: "word another line here\n", count: 20_000)
        var s = VimState()
        let t0 = Date()
        for _ in 0..<20 { _ = s.handle(key: .char("j"), in: text, selection: NSRange(location: 0, length: 0)) }
        #expect(Date().timeIntervalSince(t0) < 3)
    }
}

@Suite struct VimBadgeTests {
    private func badge(after keys: String, text: String = "one (two) three\n") -> VimBadge {
        var s = VimState()
        var sel = NSRange(location: 0, length: 0)
        for k in keys { sel = s.handle(key: .char(k), in: text, selection: sel).selection }
        return s.badge()
    }

    @Test func modesAndPendingCommands() {
        #expect(badge(after: "") == VimBadge(title: "Vim", tone: .normal, hints: []))
        #expect(badge(after: "i").title == "Insert")
        #expect(badge(after: "v").title == "Visual" && badge(after: "V").title == "Visual Line")
        #expect(badge(after: "d").title == "Delete…" && badge(after: "d").hints.first?.key == "w")
        #expect(badge(after: "2d").title == "Delete…")
        let ci = badge(after: "ci")
        #expect(ci.title == "Change inside…" && ci.tone == .change && ci.hints.map(\.key).contains("("))
        #expect(badge(after: "f").title == "Find…")
        #expect(VimState().badge(message: "Not an editor command: x").tone == .error)
    }
}

@Suite struct VimGapTests {
    func run(_ start: String, _ keys: String) -> String {
        var h = VimHarness(start)
        h.keys(keys)
        return h.shown
    }

    func text(_ start: String, _ keys: String) -> String {
        var h = VimHarness(start)
        h.keys(keys)
        return h.text as String
    }

    @Test func gMotionsAndScreenMotions() {
        #expect(run("foo bar| baz", "ge") == "foo ba|r baz")
        #expect(run("foo ba|r baz", "ge") == "fo|o bar baz")
        #expect(run("ab.c|d", "ge") == "ab|.cd")
        #expect(run("ab.c|d", "gE") == "|ab.cd")
        #expect(run("ab\ncd|\nef", "gk") == "a|b\ncd\nef")
        #expect(run("ab|\ncd\nef", "gj") == "ab\nc|d\nef")
        var h = VimHarness("l0\nl1\nl2\nl3\nl4\nl5\nl6|")
        h.visible = 2..<6
        h.keys("H"); #expect(h.shown == "l0\nl1\n|l2\nl3\nl4\nl5\nl6")
        h.keys("L"); #expect(h.shown == "l0\nl1\nl2\nl3\nl4\n|l5\nl6")
        h.keys("M"); #expect(h.shown == "l0\nl1\nl2\n|l3\nl4\nl5\nl6")
        h.keys("2H"); #expect(h.shown == "l0\nl1\nl2\n|l3\nl4\nl5\nl6")
        h.keys("dL"); #expect(h.text as String == "l0\nl1\nl2\nl6")
    }

    @Test func ctrlEY() {
        var h = VimHarness("|a\nb\nc\nd\ne\nf")
        h.visible = 0..<4
        h.keys("<C-e>")
        #expect(h.commands.last == .scroll(.line(1)))
        #expect(h.shown == "a\n|b\nc\nd\ne\nf")           // the cursor line scrolled out of the window
        h.keys("2<C-e>")
        #expect(h.commands.last == .scroll(.line(2)))
        var g = VimHarness("a\nb\nc\nd|\ne")
        g.visible = 1..<4
        g.keys("<C-y>")
        #expect(g.commands.last == .scroll(.line(-1)))
        #expect(g.shown == "a\nb\n|c\nd\ne")
    }

    @Test func marks() {
        #expect(run("a\n  b|c\nd", "majgg`a") == "a\n  b|c\nd")
        #expect(run("a\n  b|c\nd", "magg'a") == "a\n  |bc\nd")
        #expect(run("a|\nbc\nd", "jmakgg0d'a") == "|d")
        #expect(run("one\nt|wo\nthree", "majd`a") == "one\nt|hree")
        // A mark follows the text when lines are added above it.
        #expect(run("a\nb|\nc", "majggOnew<Esc>`a") == "new\na\n|b\nc")
        // `''` goes back to where the last jump started.
        #expect(run("a\nb\nc|", "gg''") == "a\nb\n|c")
        #expect(run("a\nb\nc|", "ggG''") == "|a\nb\nc")
        var h = VimHarness("a|\nb")
        h.keys("'z")
        #expect(h.shown == "|a\nb" && h.message == "E20: Mark not set")
    }

    @Test func registers() {
        var h = VimHarness("|one\ntwo\nthree")
        h.keys("\"ayy"); #expect(h.state.register == "one\n")
        h.keys("j\"Ayy")
        h.keys("G\"ap"); #expect(h.text as String == "one\ntwo\nthree\none\ntwo")
        var y = VimHarness("|one\ntwo\nthree")
        y.keys("yyjdd"); #expect(y.state.register == "two\n")
        y.keys("\"0p"); #expect(y.text as String == "one\nthree\none")
        y.keys("gg\"1P"); #expect(y.text as String == "two\none\nthree\none")
        var n = VimHarness("|a\nb\nc")
        n.keys("dddd\"1p\"2p")
        #expect(n.text as String == "c\nb\na")
        #expect(text("|abc def", "yiwwdiw\"-P") == "abcdef ")
        #expect(text("|abc def", "yiw\"_dwP") == "abcdef")
        var c = VimHarness("|abc def")
        c.keys("\"+yiww\"+P"); #expect(c.text as String == "abc abcdef")
        #expect(c.state.register == "abc")
        // The unnamed register is overwritten by "ay as well, and `"_` leaves it alone.
        var u = VimHarness("|one two")
        u.keys("yiww\"adiw"); #expect(u.state.register == "two")
        u.keys("\"_x"); #expect(u.state.register == "two")
    }

    @Test func registerListing() {
        var h = VimHarness("|one\ntwo")
        h.keys("\"ayy:reg<CR>")
        #expect(h.message?.contains("\"a one^J") == true)
        #expect(h.message?.contains("\"0") == false)
        h.keys("yy:reg<CR>")
        #expect(h.message?.contains("\"0 one^J") == true)
    }

    @Test func macros() {
        var h = VimHarness("|a\nb\nc\nd")
        h.keys("qaA!<Esc>jq")
        #expect(h.state.recording == nil && h.text as String == "a!\nb\nc\nd")
        h.keys("@a"); #expect(h.text as String == "a!\nb!\nc\nd")
        h.keys("@@"); #expect(h.text as String == "a!\nb!\nc!\nd")
        var g = VimHarness("|1\n2\n3\n4\n5")
        g.keys("qqI-<Esc>jq3@q"); #expect(g.text as String == "-1\n-2\n-3\n-4\n5")
        var f = VimHarness("|x\nx\nx")                      // stops at the first failing motion
        f.keys("qqrYjq10@q"); #expect(f.text as String == "Y\nY\nY")
        var r = VimHarness("|a")
        r.keys("qa")
        #expect(r.state.badge().title == "Recording @a")
        r.keys("i")
        #expect(r.state.badge().title.contains("Recording @a"))
        var u = VimHarness("|a b c")
        u.keys("qaxq"); u.keys("qAxq"); #expect(u.text as String == "b c")
        u.keys("@a"); #expect(u.text as String == "c")
        #expect(VimHarness("|a").state.status == "-- NORMAL --")
    }

    @Test func blockVisual() {
        #expect(run("|abc\ndef\nghi", "l<C-v>jld") == "|a\nd\nghi")
        #expect(run("|abc\ndef\nghi", "<C-v>jld") == "|c\nf\nghi")
        var y = VimHarness("a|bc\nde\nghi")
        y.keys("<C-v>jjy"); #expect(y.state.register == "b\ne\nh" && y.shown == "a|bc\nde\nghi")
        #expect(run("|abc\ndef\nghi", "<C-v>jjIX<Esc>") == "|Xabc\nXdef\nXghi")
        #expect(run("|abc\ndef\nghi", "<C-v>jjAX<Esc>") == "a|Xbc\ndXef\ngXhi")
        #expect(run("|abc\nd\nghi", "<C-v>jj$AX<Esc>") == "abc|X\ndX\nghiX")
        #expect(run("|abc\ndef\nghi", "<C-v>jlcZ<Esc>") == "|Zc\nZf\nghi")
        #expect(run("|abc\ndef\nghi", "<C-v>jlrx") == "|xxc\nxxf\nghi")
        #expect(run("|abc\ndef\nghi", "<C-v>jl~") == "|ABc\nDEf\nghi")
        #expect(run("|abc\nde\nghi", "l<C-v>jjd") == "a|c\nd\ngi")
        #expect(run("|abc\nde\nghi", "<C-v>jj$d") == "|\n\n")
        let shifted = run("|abc\ndef", "<C-v>j>")
        #expect(shifted.hasPrefix(" ") && shifted.contains("\n ") && shifted.contains("def"))
        #expect(run("|abc\ndef\nghi", "<C-v>j<Esc>") == "abc\n|def\nghi")
        #expect(VimHarness("|a").state.status == "-- NORMAL --")
        var h = VimHarness("|abc\ndef")
        h.keys("<C-v>")
        #expect(h.state.mode == .visualBlock && h.state.status == "-- VISUAL BLOCK --")
        h.keys("<C-v>"); #expect(h.state.mode == .normal)
    }

    @Test func visualReselectAndInsert() {
        #expect(run("|abc def", "vl<Esc>wgv") == "[ab]c def")
        #expect(run("|abc def", "vlIX<Esc>") == "|Xabc def")
        #expect(run("|abc def", "vlAX<Esc>") == "ab|Xc def")
        #expect(run("a\n|b\nc", "VAX<Esc>") == "a\nb|X\nc")
        #expect(run("a\n|b\nc", "VIX<Esc>") == "a\n|Xb\nc")
    }

    @Test func caseOperators() {
        #expect(run("|foo bar", "gUw") == "|FOO bar")
        #expect(run("|Foo Bar", "guu") == "|foo bar")
        #expect(run("fo|o bar", "gUU") == "FO|O BAR")
        #expect(run("|foo bar", "g~~") == "|FOO BAR")
        #expect(run("|foo bar", "g~iw") == "|FOO bar")
        #expect(run("x (|foo) y", "gUi(") == "x (|FOO) y")
        #expect(run("|foo bar baz", "gU2w") == "|FOO BAR baz")
        #expect(run("|foo\nbar\nbaz", "gU2j") == "|FOO\nBAR\nBAZ")
        #expect(run("|foo\nbar", "gUgU") == "|FOO\nbar")
        #expect(run("|foo\nbar", "jgUgg") == "FOO\n|BAR")
        #expect(run("|foo bar", "gUwwgUw") == "FOO |BAR")
        #expect(run("|foo bar", "gUww.") == "FOO |BAR")
        var b = VimHarness("|a")
        b.keys("gU")
        #expect(b.state.badge().title == "Uppercase…")
    }

    @Test func textObjectCountsAndAngles() {
        #expect(run("(a (b|) c)", "d2i(") == "(|)")
        #expect(run("(a (b|) c)", "d2a(") == "|")
        #expect(run("(a (b|) c)", "di(") == "(a (|) c)")
        #expect(run("x <a|b> y", "di<") == "x <|> y")
        #expect(run("x <a|b> y", "da<") == "x | y")
        #expect(run("x <a|b> y", "vi<d") == "x <|> y")
        #expect(run("x <a|b> y", "ci>Z<Esc>") == "x <|Z> y")
        #expect(run("(a (b|) c)", "v2i(d") == "(|)")
    }

    @Test func exSubstitute() {
        #expect(run("|aa aa\naa", ":s/a/b/<CR>") == "|ba aa\naa")
        #expect(run("|aa aa\naa", ":s/a/b/g<CR>") == "|bb bb\naa")
        #expect(run("|aa\naa\naa", ":%s/a/b/g<CR>") == "bb\nbb\n|bb")
        #expect(run("|aa\naa\naa", ":2,3s/a/b/<CR>") == "aa\nba\n|ba")
        #expect(run("|Aa\naa", ":%s/a/b/gi<CR>") == "bb\n|bb")
        #expect(run("|foo bar", ":s/\\(o\\+\\) b/[\\1]/<CR>") == "|f[oo]ar")
        #expect(run("|foo bar", ":s/o/<&>/g<CR>") == "|f<o><o> bar")
        #expect(run("|a b\nc d", ":%s/\\<./X/g<CR>") == "X X\n|X X")
        #expect(run("|ab\nab\nab", "Vj:s/b/c/<CR>") == "ac\n|ac\nab")
        #expect(run("|ab\nab\nab", "jVj<Esc>gg:'<,'>s/a/z/<CR>") == "ab\nzb\n|zb")
        #expect(run("|ab\nab\nab", ":s/a/z/<CR>j&") == "zb\n|zb\nab")
        #expect(run("|ab\nab", ":s/a/z/<CR>j:&&<CR>") == "zb\n|zb")
        var h = VimHarness("|ab")
        h.keys(":s/z/y/<CR>")
        #expect(h.message == "Pattern not found: z" && h.shown == "|ab")
        #expect(run("|a/b", ":s#/#-#<CR>") == "|a-b")
        #expect(run("|a\nb\nc\nd", ":2,3<CR>") == "a\nb\n|c\nd")
        #expect(run("|a\nb\nc", ":.+1<CR>") == "a\n|b\nc")
        #expect(run("|a\nb\nc", ":$<CR>") == "a\nb\n|c")
    }

    @Test func regexSearch() {
        #expect(run("|foo bar\nfoobar bar", "/\\<bar\\><CR>") == "foo |bar\nfoobar bar")
        #expect(run("|foo bar\nfoobar bar", "/\\<bar\\><CR>n") == "foo bar\nfoobar |bar")
        #expect(run("|abc ABC", "/\\cabc<CR>") == "abc |ABC")
        #expect(run("|abc ABC", "/abc<CR>") == "|abc ABC")
        #expect(run("|a1 b22 c", "/[0-9]\\+<CR>") == "a|1 b22 c")
        #expect(run("|x foo y foo", "/f.o<CR>nN") == "x |foo y foo")
        #expect(run("x foo| y foo", "?foo<CR>") == "x |foo y foo")
        #expect(run("|a foo b foo c", "d/foo<CR>") == "|foo b foo c")
        #expect(run("|a foo b foo c", "d2/foo<CR>") == "|foo c")
        #expect(run("|a foo b foo c", "c/foo<CR>X<Esc>") == "|Xfoo b foo c")
        #expect(run("a foo b |foo c", "d?foo<CR>") == "a |foo c")
        #expect(run("|a foo b foo c", "d/foo<CR>.") == "|foo c")
        var h = VimHarness("a |foo b foo")
        h.keys("*")
        #expect(h.shown == "a foo b |foo")
        #expect(h.highlights == [NSRange(location: 2, length: 3), NSRange(location: 8, length: 3)])
        h.keys(":noh<CR>"); #expect(h.highlights.isEmpty)
        h.keys("n"); #expect(h.highlights.count == 2)
        var m = VimHarness("|abc")
        m.keys("/(<CR>"); #expect(m.message?.hasPrefix("Pattern not found") == true)
        m.keys("/\\(<CR>"); #expect(m.message?.hasPrefix("Invalid pattern") == true)
    }

    @Test func insertCtrlKeys() {
        var h = VimHarness("|")
        h.keys("ifoo bar<C-w>")
        #expect(h.text as String == "foo ")
        h.keys("<C-w>x"); #expect(h.text as String == "x")
        var u = VimHarness("a|bc")
        u.keys("i<C-u>")
        #expect(u.text as String == "bc")
        #expect(text("|abc def", "i<C-o>wX<Esc>") == "abc Xdef")
        #expect(text("|abc", "A<C-o>0X<Esc>") == "Xabc")
        #expect(text("|abc", "A<C-o>:s/b/Z/<CR>Y<Esc>") == "YaZc")
        var e = VimHarness("|ab")
        e.keys("A<C-o>")
        #expect(e.state.mode == .normal)
        e.keys("hX")
        #expect(e.state.mode == .insert && e.text as String == "Xab")
    }

    @Test func escPassesThrough() {
        var h = VimHarness("|abc")
        h.keys("<Esc>")
        #expect(!h.handledLast)
        h.keys("d<Esc>")
        #expect(h.handledLast && h.state.pending.isEmpty)
        h.keys("<Esc>"); #expect(!h.handledLast)
        h.keys("v<Esc>"); #expect(h.handledLast && h.state.mode == .normal)
        h.keys("\"<Esc>"); #expect(h.handledLast)
    }

    @Test func dotRepeatsVisual() {
        #expect(run("|abcdef ghijkl", "vld.") == "|ef ghijkl")
        #expect(run("|a\nb\nc\nd\ne", "Vjd.") == "|e")
        #expect(run("|abc\ndef\nghi\njkl", "<C-v>jldj.") == "c\n|\ni\njkl")
        #expect(run("|abcd abcd", "vlUw.") == "ABcd |ABcd")
        #expect(run("|ab ab", "vlcX<Esc>w.") == "X |X")
        let once = text("|a\nb\nc\nd", "Vj>"), twice = text("|a\nb\nc\nd", "Vj>.")
        #expect(twice.count - once.count == once.count - 7)
    }

    @Test func badgeHints() {
        func badge(_ keys: String) -> VimBadge {
            var h = VimHarness("one (two)|")
            h.keys(keys)
            return h.state.badge()
        }
        #expect(badge("di").hints.map(\.key).contains("<"))
        #expect(badge("\"").title == "Register…")
        #expect(badge("\"a").title == "Register \"a…")
        #expect(badge("m").title == "Set mark…")
        #expect(badge("q").title == "Record macro…")
        #expect(badge("@").title == "Play macro…")
        #expect(badge("'").title == "Go to mark line…")
        #expect(badge("g").hints.map(\.key).contains("e"))
        #expect(badge("\"ad").title == "Delete…")
        #expect(badge("<C-v>").title == "Visual Block")
    }
}
