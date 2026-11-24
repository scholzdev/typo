import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

private func settings(_ change: (inout IndentSettings) -> Void) -> IndentSettings {
    var s = IndentSettings.standard
    change(&s)
    return s
}

/// Applies replacements to `text`; `|` in the result marks the returned selection when it is a caret.
private func applied(_ text: String, _ o: (edits: [Replacement], selection: NSRange)?) -> String? {
    guard let o else { return nil }
    var out = text as NSString
    for e in o.edits.sorted(by: { $0.range.location > $1.range.location }) { out = out.replacingCharacters(in: e.range, with: e.text) as NSString }
    return o.selection.length == 0 ? out.replacingCharacters(in: o.selection, with: "|") : out as String
}

/// `|` marks a caret, `<` and `>` a selection.
private func marked(_ m: String) -> (String, NSRange) {
    var t = m, sel = NSRange(location: 0, length: 0)
    if let a = t.firstIndex(of: "<") {
        let start = t.utf16.distance(from: t.startIndex, to: a); t.remove(at: a)
        let b = t.firstIndex(of: ">")!
        sel = NSRange(location: start, length: t.utf16.distance(from: t.startIndex, to: b) - start); t.remove(at: b)
    } else if let c = t.firstIndex(of: "|") {
        sel.location = t.utf16.distance(from: t.startIndex, to: c); t.remove(at: c)
    }
    return (t, sel)
}

@Suite struct IndentSettingsTests {
    @Test func unitFollowsLineStyleThenPreference() {
        for w in [2, 4, 8] {
            let spaces = settings { $0.indentWidth = w }
            #expect(spaces.unit(for: "") == String(repeating: " ", count: w))
            #expect(spaces.unit(for: "  ") == String(repeating: " ", count: w))
            #expect(spaces.unit(for: "\t") == "\t")                    // a tab-indented line keeps tabs
            let tabs = settings { $0.indentWidth = w; $0.useTabs = true; $0.tabWidth = w }
            #expect(tabs.unit(for: "") == "\t")
            #expect(tabs.unit(for: "\t") == "\t")
            #expect(tabs.unit(for: "  ") == String(repeating: " ", count: w))  // a space-indented line keeps spaces
            var explicit = tabs; explicit.explicitStyle = true
            #expect(explicit.unit(for: "  ") == "\t")                  // .editorconfig's indent_style wins
        }
        #expect(IndentSettings.standard.unit(for: "") == "  ")
    }

    @Test func indentWidthDrivesEnterTabShiftTabAndBackspace() {
        let four = settings { $0.indentWidth = 4 }
        let e = Indent.newline(in: "#f(", selection: NSRange(location: 3, length: 0), mode: .code, settings: four)
        #expect(e.replacement == "\n    ")
        #expect(applied("a\n", Indent.tab(in: "a\n", from: NSRange(location: 2, length: 0), settings: four)) == "a\n    |")
        #expect(applied("a\n      b", Indent.outdent(in: "a\n      b", from: NSRange(location: 8, length: 0), settings: four)) == "a\n  |b")
        let b = Indent.backspace(in: "a\n      b", selection: NSRange(location: 8, length: 0), settings: four)
        #expect(b?.range == NSRange(location: 6, length: 2))
        #expect(Indent.backspace(in: "a\n        b", selection: NSRange(location: 10, length: 0), settings: four)?.range.length == 4)
    }

    @Test func tabKeyModes() {
        func tab(_ m: String, _ mode: IndentSettings.TabKey, tabs: Bool = false) -> String? {
            let (t, sel) = marked(m)
            return applied(t, Indent.tab(in: t, from: sel, settings: settings { $0.tabKey = mode; $0.useTabs = tabs }))
        }
        // Leading whitespace: today's behaviour; mid-line the text view types a tab.
        #expect(tab("a\n|b", .leadingWhitespace) == "a\n  |b")
        #expect(tab("ab|c", .leadingWhitespace) == nil)
        // Always: the line nests wherever the caret is.
        #expect(tab("ab|c", .always) == "  ab|c")
        #expect(tab("<a\nb>", .always) == "  a\n  b")
        // Inserts tab: one unit at the caret, to the next indent stop; multi-line selections still nest.
        #expect(tab("a|b", .insertsTab) == "a |b")
        #expect(tab("|b", .insertsTab) == "  |b")
        #expect(tab("a|b", .insertsTab, tabs: true) == "a\t|b")
        #expect(tab("<a\nb>", .insertsTab) == "  a\n  b")
    }

    @Test func enterWithoutIndentWhenTyping() {
        let off = settings { $0.indentWhenTyping = false }
        let e = Indent.newline(in: "  #f()", selection: NSRange(location: 5, length: 0), mode: .code, settings: off)
        #expect(e.replacement == "\n  ")
        #expect(e.range == NSRange(location: 5, length: 0))
    }
}

@Suite struct ReindentTests {
    func reindent(_ m: String, _ s: IndentSettings = .standard) -> String? {
        let (t, sel) = marked(m)
        let spans = SyntaxMirror(t).spans(in: NSRange(location: 0, length: (t as NSString).length))
        let o = Reindent.edits(in: t, selection: sel, spans: spans, settings: s)
        return applied(t, o).map { $0.replacingOccurrences(of: "|", with: "") }
    }

    @Test func nestedBracketsAndClosers() {
        #expect(reindent("<#let f(x) = {\nif x {\n(1,\n2)\n}\n}>") == "#let f(x) = {\n  if x {\n    (1,\n      2)\n  }\n}")
        #expect(reindent("<#f(a, [\nb\n])>") == "#f(a, [\n  b\n])")              // one level per line, however many it opens
        #expect(reindent("<#let x = (\n      1,\n  )>") == "#let x = (\n  1,\n)")
    }

    @Test func onlyTheSelectedLinesChange() {
        #expect(reindent("#let x = (\n1,\n|2,\n)") == "#let x = (\n1,\n  2,\n)")
    }

    @Test func bracketsInStringsCommentsAndRawDoNotCount() {
        #expect(reindent("<#let x = {\n\"(\"\n// (\n/* { */\n`[`\ny\n}>") == "#let x = {\n  \"(\"\n  // (\n  /* { */\n  `[`\n  y\n}")
    }

    @Test func rawBlocksAndMultilineStringsAreNotTouched() {
        let raw = "<#let x = {\n```\n   code (\n```\n}>"
        #expect(reindent(raw) == "#let x = {\n  ```\n   code (\n```\n}")
        #expect(reindent("<#let x = {\n\"a\n    b\"\n}>") == "#let x = {\n  \"a\n    b\"\n}")
    }

    @Test func markupKeepsRelativeIndentation() {
        #expect(reindent("<#block[\n- a\n    cont\n  - b\n]>") == "#block[\n  - a\n      cont\n    - b\n]")
        #expect(reindent("<- a\n  - b>") == nil)                               // top-level list nesting stays
        #expect(reindent("<  - a\n    - b\n      more>") == "- a\n  - b\n    more")   // a moved list keeps its shape
    }

    @Test func markupOutsideListsLosesItsIndentation() {
        #expect(reindent("<= Title\n    #line(length: 100%)\n  Text>") == "= Title\n#line(length: 100%)\nText")
        #expect(reindent("<#block[\n      #line()\n]>") == "#block[\n  #line()\n]")
        #expect(reindent("<- a\nb\n  c>") == "- a\nb\nc")                      // a line at the marker's column ends the item
    }

    @Test func soloBrace() {
        let s = settings { $0.soloBraceIndent = 4 }
        #expect(reindent("<#let f() = (\n{\nx\n}\n)>", s) == "#let f() = (\n      {\n        x\n      }\n)")
        #expect(reindent("<#let f() = (\n{\nx\n}\n)>") == "#let f() = (\n  {\n    x\n  }\n)")
    }

    @Test func commentLines() {
        let t = "<#let x = {\n// note\n    y\n}>"
        #expect(reindent(t) == "#let x = {\n  // note\n  y\n}")
        #expect(reindent(t, settings { $0.indentComments = false }) == "#let x = {\n// note\n  y\n}")
    }

    @Test func trailingCommentAlignment() {
        let t = "<#let x = (\n  a, // one\n  bbbb, // two\n  c,\n  d,   // three\n)>"
        #expect(reindent(t, settings { $0.alignComments = true }) == "#let x = (\n  a,    // one\n  bbbb, // two\n  c,\n  d,   // three\n)")
        #expect(reindent(t) == nil)
    }

    @Test func tabsPreference() {
        let s = settings { $0.useTabs = true }
        #expect(reindent("<#let x = (\n  1,\n)>", s) == "#let x = (\n\t1,\n)")
    }

    @Test func caretFollowsItsText() {
        let (t, sel) = marked("#let x = (\n      1|,\n)")
        let o = Reindent.edits(in: t, selection: sel, spans: SyntaxMirror(t).spans(in: NSRange(location: 0, length: (t as NSString).length)), settings: .standard)
        #expect(applied(t, o) == "#let x = (\n  1|,\n)")
    }
}

@Suite struct PasteReindentTests {
    func paste(_ clip: String, into m: String, _ s: IndentSettings = .standard) -> String? {
        let (t, sel) = marked(m)
        return Reindent.pasted(clip, into: t, at: sel, settings: s)
    }

    @Test func deeperAndShallower() {
        #expect(paste("#f(\n  a,\n)", into: "#let x = {\n    |\n}") == "#f(\n      a,\n    )")
        #expect(paste("        a\n          b\n        c", into: "  |") == "a\n    b\n  c")
    }

    @Test func mixedTabsAndSpaces() {
        // A tab counts as a tab stop; the insertion line's tabs decide the style.
        #expect(paste("\ta\n\t  b", into: "    |") == "a\n      b")
        #expect(paste("  a\n    b", into: "\t|") == "a\n\t  b")
    }

    @Test func singleLineAndBlankLines() {
        #expect(paste("abc", into: "  |") == nil)
        #expect(paste("a\n\n  b", into: "  |") == "a\n\n  b")
    }
}

@Suite struct EditorConfigTests {
    @Test func parsing() {
        let f = EditorConfig.parse("root = true\n# c\n[*.typ]\nindent_style = Tab\n; x\n[docs/**.typ]\nindent_size=4\nunknown = 1\n")
        #expect(f.root)
        #expect(f.sections.count == 2)
        #expect(f.sections[0].properties == ["indent_style": "tab"])
        #expect(f.sections[1].properties == ["indent_size": "4", "unknown": "1"])
    }

    @Test func globs() {
        #expect(EditorConfig.matches("*", "a/b/main.typ"))
        #expect(EditorConfig.matches("*.typ", "a/main.typ"))
        #expect(!EditorConfig.matches("*.typ", "main.bib"))
        #expect(EditorConfig.matches("*.{typ,bib}", "x.bib"))
        #expect(EditorConfig.matches("docs/**.typ", "docs/a/b.typ"))
        #expect(!EditorConfig.matches("docs/**.typ", "src/docs/b.typ"))
        #expect(!EditorConfig.matches("docs/*.typ", "docs/a/b.typ"))
        #expect(EditorConfig.matches("/main.typ", "main.typ"))
        #expect(!EditorConfig.matches("/main.typ", "sub/main.typ"))
        #expect(EditorConfig.matches("ma?n.[tx]yp", "main.typ"))
        #expect(!EditorConfig.matches("main.[!t]yp", "main.typ"))
    }

    @Test func nearestWinsAndRootStops() {
        let near = (path: "main.typ", text: "[*]\nindent_size = 4\n")
        let mid = (path: "sub/main.typ", text: "[*]\nindent_size = 8\nindent_style = space\n")
        let far = (path: "x/sub/main.typ", text: "[*]\ntab_width = 3\n")
        #expect(EditorConfig.properties([near, mid, far]) == ["indent_size": "4", "indent_style": "space", "tab_width": "3"])
        let rootMid = (path: mid.path, text: "root = true\n" + mid.text)
        #expect(EditorConfig.properties([near, rootMid, far]) == ["indent_size": "4", "indent_style": "space"])
        #expect(EditorConfig.properties([(path: "a.typ", text: "[*]\nindent_size = 2\n[*.typ]\nindent_size = 6\n")]) == ["indent_size": "6"])
    }

    @Test func overridesTheThreeSettings() {
        let s = IndentSettings.standard
        let tabs = s.applying(editorConfig: ["indent_style": "tab", "tab_width": "8"])
        #expect(tabs.useTabs && tabs.explicitStyle && tabs.tabWidth == 8 && tabs.indentWidth == 8)
        let sized = s.applying(editorConfig: ["indent_size": "3"])
        #expect(!sized.useTabs && sized.indentWidth == 3 && sized.tabWidth == 3)
        let tabSize = s.applying(editorConfig: ["indent_size": "tab", "tab_width": "5"])
        #expect(tabSize.indentWidth == 5 && tabSize.tabWidth == 5)
        #expect(s.applying(editorConfig: ["end_of_line": "lf", "indent_size": "unset"]) == s)
    }

    @Test func readsFilesUpToTheProjectRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sub = root.appendingPathComponent("chapters")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "[*.typ]\nindent_style = tab\n".write(to: root.appendingPathComponent(".editorconfig"), atomically: true, encoding: .utf8)
        try "[*.typ]\ntab_width = 6\n".write(to: sub.appendingPathComponent(".editorconfig"), atomically: true, encoding: .utf8)
        let file = sub.appendingPathComponent("one.typ")
        let r = IndentSettings.standard.resolved(for: file, root: root)
        #expect(r.useTabs && r.tabWidth == 6)
        var off = IndentSettings.standard; off.preferEditorConfig = false
        #expect(off.resolved(for: file, root: root) == off)
    }
}
