import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

struct IndentTests {
    /// `|` is the caret; returns the text after Enter with `|` at the new caret.
    func enter(_ marked: String, mode: SyntaxMode = .markup) -> String {
        let text = marked.replacingOccurrences(of: "|", with: "")
        let caret = (marked as NSString).range(of: "|").location
        let e = Indent.newline(in: text, selection: NSRange(location: caret, length: 0), mode: mode)
        let out = (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
        return (out as NSString).replacingCharacters(in: e.selection, with: "|")
    }

    @Test func enterKeepsIndentation() {
        #expect(enter("  a|") == "  a\n  |")
        #expect(enter("\tb|") == "\tb\n\t|")
        #expect(enter("a|") == "a\n|")
        #expect(enter("  a|b") == "  a\n  |b")
    }

    @Test func enterAfterBracketDeepens() {
        #expect(enter("#block[|") == "#block[\n  |")
        #expect(enter("  #f(|") == "  #f(\n    |")
        #expect(enter("\t#f(|") == "\t#f(\n\t\t|")
        #expect(enter("#block[|]") == "#block[\n  |\n]")
        #expect(enter("  #f(|)") == "  #f(\n    |\n  )")
        #expect(enter("\"a[|", mode: .text) == "\"a[\n|")
    }

    @Test func enterOnBlankLineDropsTrailingBlanks() {
        #expect(enter("a\n  |") == "a\n\n  |")
    }

    func backspace(_ marked: String) -> String? {
        let text = marked.replacingOccurrences(of: "|", with: "")
        let caret = (marked as NSString).range(of: "|").location
        guard let e = Indent.backspace(in: text, selection: NSRange(location: caret, length: 0)) else { return nil }
        let out = (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
        return (out as NSString).replacingCharacters(in: e.selection, with: "|")
    }

    @Test func backspaceRemovesOneLevel() {
        #expect(backspace("a\n    |b") == "a\n  |b")
        #expect(backspace("a\n   |b") == "a\n  |b")        // off-grid: back to the level
        #expect(backspace("a\n  |") == "a\n|")
        #expect(backspace("a\n\t|") == nil)                // a tab is one character anyway
        #expect(backspace("a\n  b |") == nil)              // not in the indentation
        #expect(backspace("a\n|b") == nil)
    }

    func tab(_ marked: String, outdent: Bool = false) -> String? {
        var text = marked.replacingOccurrences(of: "|", with: "")
        let carets = marked.indices.filter { marked[$0] == "|" }.map { marked.distance(from: marked.startIndex, to: $0) }
        let start = carets[0], end = carets.count > 1 ? carets[1] - 1 : start
        let sel = NSRange(location: start, length: end - start)
        guard let r = outdent ? Indent.outdent(in: text, from: sel) : Indent.indent(in: text, from: sel) else { return nil }
        for e in r.edits.sorted(by: { $0.range.location > $1.range.location }) {
            text = (text as NSString).replacingCharacters(in: e.range, with: e.text)
        }
        let ns = text as NSString
        return r.selection.length == 0
            ? ns.replacingCharacters(in: r.selection, with: "|")
            : ns.replacingCharacters(in: r.selection, with: "|" + ns.substring(with: r.selection) + "|")
    }

    @Test func tabNestsInIndentationAndLists() {
        #expect(tab("|") == "  |")
        #expect(tab("  |a") == "    |a")
        #expect(tab("\t|a") == "\t\t|a")
        #expect(tab("- a|b") == "  - a|b")
        #expect(tab("- #f(a|, b)") == "  - #f(a|, b)")
        #expect(tab("plain| text") == nil)
    }

    @Test func tabOnSeveralLines() {
        #expect(tab("|a\nb\n\nc|") == "|  a\n  b\n\n  c|")
        #expect(tab("|a\nb\n|") == "|  a\n  b\n|")      // a trailing line start is not touched
        #expect(tab("|  a\n  b|", outdent: true) == "|a\nb|")
    }

    @Test func outdentUnits() {
        #expect(tab("    |a", outdent: true) == "  |a")
        #expect(tab(" |a", outdent: true) == "|a")
        #expect(tab("\t\t|a", outdent: true) == "\t|a")
        #expect(tab("|a", outdent: true) == nil)
        #expect(tab("x |a", outdent: true) == nil)
        #expect(tab("  - a|", outdent: true) == "- a|")
    }

    @Test func snippetKeepsShapeAtIndent() {
        let s = Snippet.parse("#table(\n  columns: ${1:2},\n\n  [${}],\n)")
        let t = s.indented(by: "    ")
        #expect(t.text == "#table(\n      columns: 2,\n\n      [],\n    )")
        let first = t.placeholders[0], second = t.placeholders[1]
        #expect((t.text as NSString).substring(with: first) == "2")
        #expect(second == NSRange(location: (t.text as NSString).range(of: "[]").location + 1, length: 0))
        #expect(s.indented(by: "") == s)
    }

    @Test func placeIndentsEveryLine() {
        let s = Snippet.parse("#table(\n  columns: 2,\n)")
        let r = TableCode.place(s, in: "- a\n  b ", replacing: NSRange(location: 8, length: 0))
        #expect(r.replacement == "\n#table(\n    columns: 2,\n  )")
    }
}
