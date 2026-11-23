import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit
#endif

@Suite(.serialized) @MainActor struct TableTests {
    static let plain = """
    #table(
      columns: 3,
      table.header([H1], [H2], [H3]),
      [a1], [a2], [a3],
      [b1], [b2], [b3],
    )
    """

    static let rich = """
    #figure(
      table(
        columns: (1fr, auto),
        align: center,
        stroke: 0.5pt,
        table.header([Name], [Qty]),
        [Apple], [3],
        upper("pear"), [5],
      ),
      caption: [Fruit],
    )
    """

    // MARK: helpers

    func model(_ src: String, at needle: String) throws -> TableModel {
        let caret = (src as NSString).range(of: needle).location + 1
        let found = try #require(TableModel.lookup(in: src, syntax: SyntaxMirror(src), at: caret))
        guard case .table(var m) = found else { Issue.record("\(found)"); throw CancellationError() }
        m.attachFigure(in: src)
        return m
    }

    func unsupported(_ src: String, at needle: String) throws -> String {
        let caret = (src as NSString).range(of: needle).location + 1
        return try #require(SyntaxMirror(src).table(at: caret)?.unsupported)
    }

    func apply(_ src: String, at needle: String = "a1", _ edit: (inout TableModel) -> Void) throws -> String {
        var m = try model(src, at: needle)
        edit(&m)
        let e = try #require(TableCode.edit(m, in: src))
        return (src as NSString).replacingCharacters(in: e.range, with: e.replacement)
    }

    /// Compiles `src` through a real engine: no diagnostics at all, and the PDF text in reading order.
    func compile(_ src: String) async throws -> (diagnostics: [String], text: String) {
        let (p, _) = try await TestEnv.project(files: ["main.typ": src])
        let r = try #require(await p.settle())
        let pdf = try #require(await r.snapshot.pdf())
        return (r.snapshot.diagnostics.map(\.message), TestEnv.pdfText(pdf))
    }

    func expectCompiles(_ src: String, text: String) async throws {
        let r = try await compile(src)
        #expect(r.diagnostics.isEmpty, "\(r.diagnostics)\n\(src)")
        #expect(r.text == text, "\(r.text)\n\(src)")
    }

    // MARK: insert

    @Test func insertSnippetCompilesAndSelectsFirstCell() async throws {
        for figure in [true, false] {
            let s = TableCode.insert(rows: 3, columns: 2, header: true, figure: figure)
            let r = try await compile(s.text)
            #expect(r.diagnostics.isEmpty, "\(r.diagnostics)\n\(s.text)")
            let first = try #require(s.placeholders.first)
            let ns = s.text as NSString
            #expect(first.length == 0 && ns.character(at: first.location - 1) == 91 && ns.character(at: first.location) == 93)   // [|]
            #expect(ns.range(of: "[]").location == first.location - 1)
            #expect(s.placeholders.count == 2 * 3 + (figure ? 1 : 0))
        }
        let s = TableCode.insert(rows: 3, columns: 2, header: true, figure: true)
        #expect(s.text == "#figure(\n  table(\n    columns: 2,\n    table.header([], []),\n    [], [],\n    [], [],\n  ),\n  caption: [],\n)")
        #expect(TableCode.insert(rows: 2, columns: 1, header: false, figure: false).text == "#table(\n  columns: 1,\n  [],\n  [],\n)")
    }

    @Test func insertedTableParsesAndEditsAsAModel() async throws {
        let s = TableCode.insert(rows: 2, columns: 2, header: true, figure: true)
        let m = try model(s.text, at: "table(")
        #expect(m.header?.count == 2 && m.rows.count == 1 && m.columns.count == 2)
        #expect(!m.isModified)
    }

    @Test func placementPutsTheTableOnItsOwnLines() {
        let s = TableCode.insert(rows: 1, columns: 1, header: false, figure: false)
        let mid = TableCode.place(s, in: "ab cd", replacing: NSRange(location: 2, length: 0))
        #expect(mid.replacement == "\n" + s.text + "\n")
        #expect(mid.selection == s.selection(insertedAt: 3))
        let start = TableCode.place(s, in: "ab\ncd", replacing: NSRange(location: 3, length: 0))
        #expect(start.replacement == s.text + "\n")
        let whole = TableCode.place(s, in: "", replacing: NSRange(location: 0, length: 0))
        #expect(whole.replacement == s.text)
    }

    // MARK: parse

    @Test func parsesHeaderNamedArgsAndNonContentCells() throws {
        let m = try model(Self.rich, at: "Apple")
        #expect(m.callee == "table")
        #expect(m.columns.map(\.size) == ["1fr", "auto"])
        #expect(m.columns.map(\.align) == ["center", "center"])
        #expect(m.slots == [.columns, .align, .verbatim("stroke: 0.5pt")])
        #expect(m.header?.map(\.text) == ["Name", "Qty"])
        #expect(m.rows.map { $0.map(\.text) } == [["Apple", "3"], ["#upper(\"pear\")", "5"]])
        #expect(m.rows[1][0].original == "upper(\"pear\")")
        let call = (Self.rich as NSString).substring(with: m.range)
        #expect(call.hasPrefix("table(") && call.hasSuffix(")") && call.contains("Qty"))
        #expect(!call.contains("caption"))
    }

    @Test func headerKeepsItsOwnArgs() throws {
        let m = try model("#table(columns: 2, table.header(repeat: false, [A], [B]), [a], [b])", at: "[a]")
        #expect(m.headerArgs == ["repeat: false"])
        let out = try apply("#table(columns: 2, table.header(repeat: false, [A], [B]), [a], [b])", at: "[a]") { $0.setText("x", row: 1, column: 0) }
        #expect(out.contains("table.header(repeat: false, [A], [B]),"))
    }

    @Test func findsTheInnermostTableAndOnlyWhenInside() throws {
        let src = "#table(columns: 1, [#table(columns: 2, [i], [j])])\n\ntext"
        let ns = src as NSString
        let inner = try #require(SyntaxMirror(src).table(at: ns.range(of: "[i]").location + 1))
        #expect(inner.cells.count == 2)
        let outer = try #require(SyntaxMirror(src).table(at: ns.range(of: "#table").location + 3))
        #expect(outer.cells.count == 1)
        #expect(SyntaxMirror(src).table(at: ns.length) == nil)
        #expect(SyntaxMirror("plain *text*").table(at: 3) == nil)
        let bare = "#let t = table(columns: 1, [x])"                  // no `#` call
        #expect(SyntaxMirror(bare).table(at: (bare as NSString).range(of: "[x]").location) != nil)
    }

    @Test func gridWorksLikeTable() async throws {
        let src = "#grid(\n  columns: 2,\n  column-gutter: 1em,\n  grid.header([H], [I]),\n  [a1], [a2],\n)"
        let m = try model(src, at: "a1")
        #expect(m.callee == "grid" && m.header?.count == 2)
        let out = try apply(src) { $0.insertRow(at: 2); $0.setText("n1", row: 2, column: 0) }
        #expect(out == "#grid(\n  columns: 2,\n  column-gutter: 1em,\n  grid.header([H], [I]),\n  [a1], [a2],\n  [n1], [],\n)")
        try await expectCompiles(out, text: "H I a1 a2 n1")
    }

    @Test func everyUnsupportedCaseSaysWhy() throws {
        let cases: [(String, String)] = [
            ("#table(columns: 2, ..items)", "spread"),
            ("#table(columns: 2, table.cell(colspan: 2)[a], [b])", "colspan"),
            ("#table(columns: 2, table.cell(rowspan: 2)[a], [b], [c])", "rowspan"),
            ("#table(columns: 2, table.hline(), [a], [b])", "hline"),
            ("#table(columns: 2, table.vline(), [a], [b])", "vline"),
            ("#table(columns: 2, [a], [b], table.footer([c], [d]))", "footer"),
            ("#table(columns: auto, [a])", "columns"),
            ("#table(columns: (1fr), [a])", "columns"),
            ("#table(columns: n, [a])", "columns"),
            ("#table(columns: (..a), [a])", "columns"),
            ("#table(columns: 2, [a], [b], [c])", "3 cells"),
            ("#table(columns: 3, table.header([a], [b]), [c])", "header"),
            ("#table(columns: 2, // note\n [a], [b])", "comments"),
            ("#table(columns: 2)[a][b]", "after the closing"),
            ("#table(columns: 2, [a], [b], table.header([c], [d]))", "not the first"),
        ]
        for (src, reason) in cases {
            let got = try unsupported(src, at: "table")
            #expect(got.localizedCaseInsensitiveContains(reason), "\(src) -> \(got)")
        }
    }

    // MARK: render

    @Test func unchangedModelIsNoOp() throws {
        for src in [Self.plain, Self.rich, "#table(columns:2,[ a ],   [b])"] {
            let m = try model(src, at: src.contains("a1") ? "a1" : src.contains("Apple") ? "Apple" : "[ a ]")
            #expect(!m.isModified)
            #expect(TableCode.edit(m, in: src) == nil)
        }
        var m = try model(Self.plain, at: "a1")
        m.setText("changed", row: 1, column: 0)
        m.setText("a1", row: 1, column: 0)
        #expect(TableCode.edit(m, in: Self.plain) == nil)
    }

    @Test func oneCellEditChangesOnlyThatCell() throws {
        let out = try apply(Self.rich, at: "Apple") { $0.setText("Banana", row: 1, column: 0) }
        #expect(out == Self.rich.replacingOccurrences(of: "[Apple]", with: "[Banana]"))
        let messy = "#table(columns:2,[ a ],   upper(\"x\"),\n  [c], [d])"
        let out2 = try apply(messy, at: "[ a ]") { $0.setText("d2", row: 1, column: 1) }
        #expect(out2.contains("[ a ], [c], [d]") == false)                 // re-laid out, one row per line
        #expect(out2 == "#table(\n  columns: 2,\n  [ a ], upper(\"x\"),\n  [c], [d2],\n)")
    }

    @Test func rowOperationsCompileInOrder() async throws {
        var out = try apply(Self.plain) { $0.insertRow(at: 2); $0.setText("n1", row: 2, column: 0); $0.setText("n2", row: 2, column: 2) }
        try await expectCompiles(out, text: "H1 H2 H3 a1 a2 a3 n1 n2 b1 b2 b3")
        out = try apply(Self.plain) { $0.deleteRow(at: 1) }
        try await expectCompiles(out, text: "H1 H2 H3 b1 b2 b3")
        out = try apply(Self.plain) { $0.moveRow(from: 1, to: 2) }
        try await expectCompiles(out, text: "H1 H2 H3 b1 b2 b3 a1 a2 a3")
        out = try apply(Self.plain) { $0.moveRow(from: 2, to: 0) }          // nothing goes above the header
        try await expectCompiles(out, text: "H1 H2 H3 b1 b2 b3 a1 a2 a3")
        out = try apply(Self.plain) { $0.insertRow(at: 0) }
        try await expectCompiles(out, text: "H1 H2 H3 a1 a2 a3 b1 b2 b3")
        #expect(out.contains("table.header([H1], [H2], [H3]),\n  [], [], [],\n  [a1]"))
    }

    @Test func columnOperationsCompileInOrder() async throws {
        var out = try apply(Self.plain) { $0.insertColumn(at: 1); $0.setText("N", row: 0, column: 1); $0.setText("n", row: 2, column: 1) }
        try await expectCompiles(out, text: "H1 N H2 H3 a1 a2 a3 b1 n b2 b3")
        #expect(out.contains("columns: 4,"))
        out = try apply(Self.plain) { $0.deleteColumn(at: 0) }
        try await expectCompiles(out, text: "H2 H3 a2 a3 b2 b3")
        out = try apply(Self.plain) { $0.moveColumn(from: 0, to: 2) }
        try await expectCompiles(out, text: "H2 H3 H1 a2 a3 a1 b2 b3 b1")
        var one = try model("#table([x], [y])", at: "[x]")                    // a table keeps its last column
        one.deleteColumn(at: 0)
        #expect(one.columns.count == 1 && !one.isModified)
    }

    @Test func columnsArrayKeepsItsFormAndGrowsWithAuto() async throws {
        var out = try apply(Self.rich, at: "Apple") { $0.insertColumn(at: 2); $0.setText("Z", row: 0, column: 2) }
        #expect(out.contains("columns: (1fr, auto, auto),"))
        #expect(out.contains("align: (center, center, auto),"))
        try await expectCompiles(out, text: "Name Qty Z Apple 3 PEAR 5 Table 1: Fruit")
        out = try apply(Self.rich, at: "Apple") { $0.deleteColumn(at: 0) }
        #expect(out.contains("columns: (auto,),"))
        #expect(out.contains("align: center,"))
        let c = try await compile(out)
        #expect(c.diagnostics.isEmpty, "\(c.diagnostics)")
    }

    @Test func headerToggle() async throws {
        var out = try apply(Self.plain) { $0.toggleHeader() }
        #expect(!out.contains("table.header"))
        try await expectCompiles(out, text: "H1 H2 H3 a1 a2 a3 b1 b2 b3")
        out = try apply("#table(columns: 2, [a1], [a2], [b1], [b2])") { $0.toggleHeader() }
        #expect(out == "#table(\n  columns: 2,\n  table.header([a1], [a2]),\n  [b1], [b2],\n)")
        var m = try model("#table(columns: 2, table.header(repeat: false, [A], [B]), [a1], [a2])", at: "a1")
        m.toggleHeader(); m.toggleHeader()
        #expect(!m.isModified)                                              // back to where it was
        var empty = try model("#table(columns: 2)", at: "table")
        empty.toggleHeader()
        #expect(empty.header?.count == 2 && TableCode.render(empty).contains("table.header([], [])"))
    }

    @Test func alignmentRules() async throws {
        var out = try apply(Self.plain) { $0.setAlignment("center", column: 1) }
        #expect(out.contains("align: (auto, center, auto),"))
        try await expectCompiles(out, text: "H1 H2 H3 a1 a2 a3 b1 b2 b3")
        out = try apply(Self.plain) { for c in 0..<3 { $0.setAlignment("right", column: c) } }
        #expect(out.hasPrefix("#table(\n  align: right,\n  columns: 3,") || out.hasPrefix("#table(\n  columns: 3,\n  align: right,"))
        try await expectCompiles(out, text: "H1 H2 H3 a1 a2 a3 b1 b2 b3")
        out = try apply(Self.rich, at: "Apple") { $0.setAlignment("left", column: 0) }
        #expect(out.contains("align: (left, center),"))
        out = try apply(Self.rich, at: "Apple") { $0.setAlignment(nil, column: 0); $0.setAlignment(nil, column: 1) }
        #expect(!out.contains("align:"))
        // A function `align:` is not touched and the controls are off.
        let fn = "#table(columns: 2, align: (x, y) => if x == 0 { left } else { right }, [a1], [a2])"
        var m = try model(fn, at: "a1")
        #expect(!m.alignEditable)
        m.setAlignment("center", column: 0)
        m.setText("z", row: 0, column: 1)
        #expect(TableCode.render(m).contains("align: (x, y) => if x == 0 { left } else { right },"))
    }

    @Test func escapingKeepsTheBlockBalanced() async throws {
        #expect(TableCode.escape("plain") == "plain")
        #expect(TableCode.escape("a[b") == "a\\[b")
        #expect(TableCode.escape("a]b") == "a\\]b")
        #expect(TableCode.escape("[ok] and ]x[") == "[ok] and \\]x\\[")
        #expect(TableCode.escape("end\\") == "end\\\\")
        #expect(TableCode.escape("\\[") == "\\[")
        let out = try apply("#table(columns: 3, [a1], [a2], [a3])") {
            $0.setText("p[q", row: 0, column: 0); $0.setText("r]s", row: 0, column: 1); $0.setText("t\\", row: 0, column: 2)
        }
        #expect(out.contains("[p\\[q], [r\\]s], [t\\\\],"))
        let r = try await compile(out)
        #expect(r.diagnostics.isEmpty, "\(r.diagnostics)\n\(out)")
        #expect(r.text == "p[q r]s t\\")
    }

    /// A changed cell written through the real edit path must compile cleanly and show exactly what was typed.
    func expectCell(_ typed: String, writtenAs written: String, shows: String? = nil) async throws {
        let out = try apply("#table(columns: 1, [a1])") { $0.setText(typed, row: 0, column: 0) }
        #expect(out.contains("  [\(written)],\n"), "\(out)")
        try await expectCompiles(out, text: shows ?? typed)
    }

    @Test func bracketsOutsideMarkupAreNotEscaped() async throws {
        try await expectCell("`a[b`", writtenAs: "`a[b`", shows: "a[b")
        try await expectCell("`a]b`", writtenAs: "`a]b`", shows: "a]b")
        try await expectCell("#\"x]\"", writtenAs: "#\"x]\"", shows: "x]")
        try await expectCell("a]b", writtenAs: "a\\]b", shows: "a]b")
        try await expectCell("[x]", writtenAs: "[x]")
        try await expectCell("a\\", writtenAs: "a\\\\", shows: "a\\")
        try await expectCell("``` [```", writtenAs: "``` [```", shows: "[")
    }

    @Test func bracketsInMathStayAsTyped() async throws {
        try await expectCell("$[a$", writtenAs: "$[a$", shows: "[𝑎")
        try await expectCell("$a]$", writtenAs: "$a]$", shows: "𝑎]")
    }
}

#if canImport(AppKit)
extension TableTests {
    @Test func appliedEditIsOneUndoStepAndEngineStaysExact() async throws {
        let src = "= Doc\n\n" + Self.rich + "\n\nTail text here\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": src])
        let b = try await p.open(RelPath("main.typ")!)
        let um = b.undoManager
        um.groupsByEvent = false
        let tv = CaretTests.view(b)
        let delegate = UndoRouter(um)
        tv.delegate = delegate

        let caret = (b.storage.string as NSString).range(of: "Apple").location + 1
        guard case .table(var m) = try #require(b.table(at: caret)) else { Issue.record("not a table"); return }
        m.setText("Mango", row: 1, column: 0)
        m.insertRow(at: 3)
        m.insertColumn(at: 2)
        let e = try #require(TableCode.edit(m, in: b.storage.string))
        let before = b.storage.string
        let seqBefore = p.resyncCount

        um.beginUndoGrouping()
        tv.insertText(e.replacement, replacementRange: e.range)
        um.endUndoGrouping()
        #expect(b.storage.string != before && b.storage.string.contains("[Mango]") && b.storage.string.hasSuffix("Tail text here\n"))
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == b.storage.string)

        um.undo()
        #expect(b.storage.string == before)
        #expect(!um.canUndo)
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == before)
        um.redo()
        #expect(b.storage.string.contains("[Mango]"))
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
        #expect(p.resyncCount == seqBefore)
        let r = try #require(await p.settle())
        #expect(r.snapshot.diagnostics.isEmpty, "\(r.snapshot.diagnostics.map(\.message))")
    }

    @Test func insertingATableIsOneUndoStepOnItsOwnLines() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "before after\n"])
        let b = try await p.open(RelPath("main.typ")!)
        let um = b.undoManager
        um.groupsByEvent = false
        let tv = CaretTests.view(b)
        let delegate = UndoRouter(um)
        tv.delegate = delegate
        tv.setSelectedRange(NSRange(location: 6, length: 0))
        let s = TableCode.insert(rows: 3, columns: 2, header: true, figure: true)
        let placed = TableCode.place(s, in: b.storage.string, replacing: tv.selectedRange())
        um.beginUndoGrouping()
        tv.insertText(placed.replacement, replacementRange: tv.selectedRange())
        tv.setSelectedRange(placed.selection)
        um.endUndoGrouping()
        let text = b.storage.string
        #expect(text.hasPrefix("before\n#figure(") && text.hasSuffix(")\n after\n"))
        #expect(tv.selectedRange().length == 0 && (text as NSString).substring(with: NSRange(location: tv.selectedRange().location - 1, length: 2)) == "[]")
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == text)
        um.undo()
        #expect(b.storage.string == "before after\n" && !um.canUndo)
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == "before after\n")
    }
}

/// Routes the text view's undo to the buffer's manager, like the editor's coordinator.
@MainActor private final class UndoRouter: NSObject, NSTextViewDelegate {
    let um: UndoManager
    init(_ um: UndoManager) { self.um = um }
    func undoManager(for view: NSTextView) -> UndoManager? { um }
}
#endif
