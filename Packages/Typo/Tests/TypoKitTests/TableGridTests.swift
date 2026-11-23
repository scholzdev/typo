import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

/// Spans, rules, ranges, styles, clipboard and figure fields of the spreadsheet editor.
@Suite(.serialized) @MainActor struct TableGridTests {
    let t = TableTests()

    static let spanned = """
    #table(
      columns: 3,
      table.header(table.cell(colspan: 2)[Group], [C]),
      table.hline(stroke: 0.5pt),
      table.cell(rowspan: 2, fill: red)[a1], [a2], [a3],
      [b2], [b3],
      table.hline(),
    )
    """

    func lookup(_ src: String, at needle: String) -> TableLookup? {
        TableModel.lookup(in: src, syntax: SyntaxMirror(src), at: (src as NSString).range(of: needle).location + 1)
    }

    func reparse(_ src: String, at needle: String) throws -> TableModel { try t.model(src, at: needle) }

    // MARK: spans and rules

    @Test func spansAndRulesParseAndRoundTrip() async throws {
        let m = try t.model(Self.spanned, at: "a2")
        #expect(!m.isModified)
        #expect(TableCode.edit(m, in: Self.spanned) == nil)
        #expect(m.header?.map(\.covered) == [false, true, false])
        #expect(m.header?[0].colspan == 2)
        #expect(m.rows.count == 2 && m.rows[1][0].covered && m.rows[0][0].rowspan == 2)
        #expect(m.anchor(row: 2, column: 0) == (1, 0))
        #expect(m.rules == [.init(source: "table.hline(stroke: 0.5pt)", row: 1), .init(source: "table.hline()", row: 3)])
        // Editing one cell rewrites the table but keeps the spans, the cell's other args and the rules.
        let out = try t.apply(Self.spanned, at: "a2") { $0.setText("x", row: 2, column: 0) }
        #expect(out.contains("table.cell(rowspan: 2, fill: red)[x]"))
        #expect(out.contains("table.cell(colspan: 2)[Group]"))
        try await t.expectCompiles(out, text: "Group C a2 a3 x b2 b3")
        #expect(try reparse(out, at: "a2").rules.count == 2)
    }

    /// The sample the editor's Xcode preview opens (TableEditorView.swift), behind other text so offsets matter.
    @Test func editorPreviewSampleParses() async throws {
        let source = """
        = Prices

        #figure(
          table(
            columns: (1fr, auto, auto),
            align: (left, center, right),
            table.header([*Fruit*], table.cell(colspan: 2)[Amount]),
            [Apple], [3], [\\$1.20],
            table.cell(rowspan: 2)[Pear], [5], [\\$2.00],
            [7], [\\$2.80],
            [Mango with a very long name that truncates], [_1_], [\\$0.90],
          ),
          caption: [Fruit prices],
        ) <tab:fruit>
        """
        guard case .table(var m)? = TableModel.lookup(in: source, at: (source as NSString).range(of: "Apple").location) else {
            Issue.record("sample did not parse"); return
        }
        m.attachFigure(in: source)
        #expect(m.header?[1].colspan == 2 && m.rows[1][0].rowspan == 2 && m.rows[2][0].covered)
        #expect(m.figure?.caption == "Fruit prices" && m.figure?.label == "tab:fruit")
        #expect(TableCode.edit(m, in: source) == nil)
        m.setText("Kiwi", row: 1, column: 0)
        let e = try #require(TableCode.edit(m, in: source))
        try await t.expectCompiles((source as NSString).replacingCharacters(in: e.range, with: e.replacement),
                                   text: "Prices Fruit Amount Kiwi 3 $1.20 5 $2.00 Pear 7 $2.80 Mango with a very long name that truncates 1 $0.90 Table 1: Fruit prices")
    }

    @Test func placedCellsStayUnsupported() {
        for src in ["#table(columns: 2, table.cell(x: 1)[a], [b])", "#table(columns: 2, [a], table.vline(), [b])",
                    "#table(columns: 2, table.cell(colspan: 3)[a], [b])", "#table(columns: 2, table.footer([a], [b]))"] {
            guard case .unsupported = lookup(src, at: "table(") else { Issue.record("\(src) should stay unsupported"); continue }
        }
    }

    @Test func unsupportedReasonNamesWhatTheEditorCantDo() {
        func reason(_ src: String) -> String? { if case .unsupported(let r) = lookup(src, at: "table(") { r } else { nil } }
        let placed = reason("#table(columns: 2, table.cell(x: 1, y: 0)[a], [b])") ?? ""
        #expect(placed.contains("x:, y:") && !placed.contains("colspan"), "\(placed)")
        #expect(reason("#table(columns: 2, table.header(table.cell(y: 0)[a], [b]), [c], [d])")?.contains("x:, y:") == true)
        let overflow = reason("#table(columns: 2, table.cell(colspan: 3)[a], [b])") ?? ""
        #expect(overflow.contains("doesn't fit") && !overflow.contains(" x "), "\(overflow)")
    }

    @Test func cellFillIsWrittenAndReadBackAsACell() async throws {
        let out = try t.apply(TableTests.plain) { $0.setFill("red.lighten(70%)", rows: 1...1, columns: 0...1) }
        #expect(out.contains("table.cell(fill: red.lighten(70%))[a1], table.cell(fill: red.lighten(70%))[a2], [a3]"), "\(out)")
        try await t.expectCompiles(out, text: "H1 H2 H3 a1 a2 a3 b1 b2 b3")
        var m = try reparse(out, at: "a3")
        #expect(m.cell(row: 1, column: 0).text == "a1" && m.fill(row: 1, column: 0) == "red.lighten(70%)" && !m.isModified)
        m.setFill(nil, rows: 1...1, columns: 0...0)
        #expect(TableCode.render(m).contains("[a1], table.cell(fill: red.lighten(70%))[a2]"))
        // A fill set on a merged cell keeps its span.
        var s = try t.model(Self.spanned, at: "a2")
        s.setFill("blue", rows: 1...1, columns: 0...0)
        #expect(TableCode.render(s).contains("table.cell(rowspan: 2, fill: blue)[a1]"))
    }

    @Test func mergeAndUnmerge() async throws {
        let src = TableTests.plain
        let out = try t.apply(src) { $0.merge(rows: 1...2, columns: 0...1) }
        #expect(out.contains("table.cell(colspan: 2, rowspan: 2)[a1 a2 b1 b2]"))
        try await t.expectCompiles(out, text: "H1 H2 H3 a3 a1 a2 b1 b2 b3")
        var m = try reparse(out, at: "a3")
        #expect(m.rows[0][0].colspan == 2 && m.rows[1][1].covered)
        // A rectangle that cuts a merged cell grows to take it in; header and body never merge.
        let crossed = m.merge(rows: 0...1, columns: 0...0)
        #expect(!crossed)
        m.unmerge(row: 2, column: 1)
        #expect(m.rows.flatMap { $0 }.allSatisfy { !$0.covered && !$0.isMerged })
        #expect(m.rows[0][0].text == "a1 a2 b1 b2")
        var n = try reparse(out, at: "a3")
        let merged = n.merge(rows: 2...2, columns: 1...2)
        #expect(merged)      // cuts the 2×2 cell: grows to rows 1–2, columns 0–2
        #expect(n.rows[0][0].colspan == 3 && n.rows[0][0].rowspan == 2)
    }

    @Test func rowAndColumnOpsKeepSpans() async throws {
        let base = try t.apply(TableTests.plain) { $0.merge(rows: 1...2, columns: 0...0) }
        // Inserting inside the merged cell makes it taller; deleting its top row hands it down.
        var m = try reparse(base, at: "a2")
        m.insertRow(at: 2)
        #expect(m.rows[0][0].rowspan == 3 && m.rows[1][0].covered)
        m.deleteRow(at: 1)
        #expect(m.rows[0][0].rowspan == 2 && m.rows[0][0].text == "a1 b1")
        m.insertColumn(at: 0)
        #expect(m.rows[0][1].rowspan == 2 && m.columns.count == 4)
        m.deleteColumn(at: 1)
        #expect(m.rows[1][0].text == "" && !m.rows[1][0].covered)
        var w = try reparse(try t.apply(TableTests.plain) { $0.merge(rows: 1...1, columns: 0...1) }, at: "a3")
        w.insertColumn(at: 1)
        #expect(w.rows[0][0].colspan == 3)
        w.duplicateRow(at: 1)
        #expect(w.rows[1][0].colspan == 3 && w.rows[1][1].covered)
        w.moveRow(from: 2, to: 3)
        let out = try #require(TableCode.edit(w, in: TableTests.plain)).replacement
        try await t.expectCompiles("#" + out, text: "H1 H2 H3 a1 a2 a3 b1 b2 b3 a1 a2 a3")
    }

    @Test func clearEmphasisAndPaste() throws {
        var m = try t.model(TableTests.plain, at: "a1")
        m.toggleEmphasis("*", rows: 1...2, columns: 0...0)
        #expect(m.rows.map { $0[0].text } == ["*a1*", "*b1*"])
        m.setText("x", row: 2, column: 0)
        m.toggleEmphasis("*", rows: 1...2, columns: 0...0)      // mixed: wrap the rest
        #expect(m.rows.map { $0[0].text } == ["*a1*", "*x*"])
        m.toggleEmphasis("*", rows: 1...2, columns: 0...0)
        #expect(m.rows.map { $0[0].text } == ["a1", "x"])
        m.toggleEmphasis("_", rows: 0...0, columns: 0...2)
        #expect(m.header?.map(\.text) == ["_H1_", "_H2_", "_H3_"])
        m.clear(rows: 1...2, columns: 1...2)
        #expect(m.rows.map { $0[1].text + $0[2].text } == ["", ""])
        let r = m.paste([["p", "q"], ["r", "s"], ["t"]], row: 2, column: 2)
        #expect(r?.rows == 2...4 && r?.columns == 2...3)
        #expect(m.rowCount == 5 && m.columns.count == 4)
        #expect(m.cell(row: 4, column: 2).text == "t" && m.cell(row: 3, column: 3).text == "s")
    }

    // MARK: styles

    @Test(arguments: TableStyle.allCases) func everyPresetCompilesAndIsRecognized(_ style: TableStyle) async throws {
        let base = TableTests.rich.replacingOccurrences(of: "stroke: 0.5pt", with: "stroke: blue")
        let out = try t.apply(base, at: "Apple") { $0.applyStyle(style) }
        try await t.expectCompiles(out, text: "Name Qty Apple 3 PEAR 5 Table 1: Fruit")
        #expect(!out.contains("0.5pt,\n    stroke") )
        let m = try reparse(out, at: "Apple")
        #expect(m.style == style, "\(out)")
        #expect(out.components(separatedBy: "stroke:").count - 1 <= (style == .booktabs ? 4 : 1))
    }

    @Test func handWrittenStrokeIsKeptUntilAPresetIsPicked() throws {
        let m = try t.model(TableTests.rich, at: "Apple")
        #expect(m.style == .grid)                     // `stroke: 0.5pt` is what Grid writes
        let custom = TableTests.rich.replacingOccurrences(of: "stroke: 0.5pt", with: "stroke: blue")
        var c = try t.model(custom, at: "Apple")
        #expect(c.style == nil)
        c.setText("Kiwi", row: 1, column: 0)
        #expect(try #require(TableCode.edit(c, in: custom)).replacement.contains("stroke: blue"))
    }

    @Test func booktabsBottomRuleFollowsTheRows() async throws {
        var m = try t.model(TableTests.plain, at: "a1")
        m.applyStyle(.booktabs)
        m.insertRow(at: m.rowCount)
        m.setText("c1", row: 3, column: 0)
        let out = "#" + (try #require(TableCode.edit(m, in: TableTests.plain))).replacement
        let lines = out.components(separatedBy: "\n")
        #expect(lines[lines.count - 2].contains("table.hline(stroke: 1pt)"))
        #expect(lines[lines.count - 3].contains("[c1]"))
        try await t.expectCompiles(out, text: "H1 H2 H3 a1 a2 a3 b1 b2 b3 c1")
    }

    @Test func trailingHolesStayHolesUntilFilled() async throws {
        let ruled = "#table(\n  columns: 3,\n  table.hline(),\n  [a1], [a2], [a3],\n  [b1],\n)"
        let out = try t.apply(ruled) { $0.setText("x", row: 0, column: 1) }
        #expect(out == "#table(\n  columns: 3,\n  table.hline(),\n  [a1], [x], [a3],\n  [b1],\n)")
        // Without lines the table still opens again, and filling a hole writes the ones before it.
        let plain = try t.apply("#table(columns: 3, [a1], [a2], [a3], [b1])") { $0.setText("x", row: 0, column: 1) }
        #expect(plain.hasSuffix("[a1], [x], [a3],\n  [b1],\n)"))
        let filled = try t.apply(plain) { $0.setText("b3", row: 1, column: 2) }
        #expect(filled.hasSuffix("[b1], [], [b3],\n)"))
        try await t.expectCompiles(filled, text: "a1 x a3 b1 b3")
        let below = try t.apply(plain) { $0.insertRow(at: 2); $0.setText("c1", row: 2, column: 0) }
        #expect(below.hasSuffix("[b1], [], [],\n  [c1], [], [],\n)"))
    }

    @Test func movedRowTakesItsLinesButNotTheTableEdges() async throws {
        var m = try t.model(TableTests.plain, at: "a1")
        m.insertRow(at: 3)
        m.setText("c1", row: 3, column: 0)
        m.applyStyle(.booktabs)
        m.moveRow(from: 1, to: 3)
        #expect(m.style == .booktabs)
        m.moveRow(from: 3, to: 1)
        #expect(m.style == .booktabs)
        // A line above the last row (a total) moves with it, and the one below it stays the bottom edge.
        m.rules.append(.init(source: "table.hline(stroke: red)", row: 3))
        m.moveRow(from: 3, to: 1)
        #expect(m.rules.first { $0.source.contains("red") }?.row == 1)
        #expect(m.rules.first { $0.source.contains("1pt)") && !$0.source.contains("y:") }?.row == m.rowCount)
        let out = "#" + (try #require(TableCode.edit(m, in: TableTests.plain))).replacement
        #expect(out.contains("table.hline(stroke: red),\n  [c1]"), "\(out)")
        try await t.expectCompiles(out, text: "H1 H2 H3 c1 a1 a2 a3 b1 b2 b3")
    }

    // MARK: columns

    @Test func columnWidthsAndAlignment() async throws {
        #expect(ColumnWidth("auto") == .auto && ColumnWidth(nil) == .auto)
        #expect(ColumnWidth("72pt") == .points(72) && ColumnWidth("1.5fr") == .fraction(1.5) && ColumnWidth("30%") == .other("30%"))
        #expect(ColumnWidth.points(80.5).size == "80.5pt" && ColumnWidth.fraction(2).size == "2fr" && ColumnWidth.auto.size == nil)
        var spec = ColumnSpec(align: "left + top")
        #expect(spec.horizontal == "left" && spec.vertical == "top")
        spec.horizontal = "right"
        #expect(spec.align == "right + top")
        spec.vertical = nil
        #expect(spec.align == "right")
        let out = try t.apply(TableTests.plain) {
            $0.columns[0].width = .points(80)
            $0.columns[2].width = .fraction(1)
            $0.columns[1].vertical = "horizon"
        }
        #expect(out.contains("columns: (80pt, auto, 1fr),"))
        #expect(out.contains("align: (auto, horizon, auto),"))
        try await t.expectCompiles(out, text: "H1 H2 H3 a1 a2 a3 b1 b2 b3")
    }

    // MARK: clipboard

    @Test func clipboardParsesTSVAndCSV() {
        #expect(TableClipboard.parse("a\tb\nc\td\n") == [["a", "b"], ["c", "d"]])
        #expect(TableClipboard.parse("a,b\r\n\"c, d\",\"say \"\"hi\"\"\"") == [["a", "b"], ["c, d", "say \"hi\""]])
        #expect(TableClipboard.parse("Hello, world") == [["Hello, world"]])
        #expect(TableClipboard.parse("one\ntwo") == [["one"], ["two"]])
        #expect(TableClipboard.parse("\"multi\nline\"\tx") == [["multi\nline", "x"]])
        #expect(TableClipboard.parse("") == [])
        let grid = [["a\tb", "c"], ["\"q\"", "line\nbreak"]]
        #expect(TableClipboard.parse(TableClipboard.tsv(grid)) == grid)
    }

    @Test func pastedPlainTextStaysText() async throws {
        #expect(TableClipboard.markup("$12.50 #1 *x*") == "\\$12.50 \\#1 \\*x\\*")
        #expect(TableClipboard.markup("- item") == "\\- item")
        #expect(TableClipboard.markup("1. first") == "1\\. first")
        let out = try t.apply(TableTests.plain) {
            $0.paste([["$12.50", "http://x.org", "a_b [c]"], ["= no heading", "<tag>", "@ref"]].map { $0.map(TableClipboard.markup) }, row: 1, column: 0)
        }
        try await t.expectCompiles(out, text: "H1 H2 H3 $12.50 http://x.org a_b [c] = no heading <tag> @ref")
    }

    // MARK: figure

    @Test func figureFieldsAreWrittenWithTheTableInOneEdit() async throws {
        var m = try t.model(TableTests.rich, at: "Apple")
        #expect(m.figure == .init(caption: "Fruit", label: "", placement: ""))
        m.figure?.caption = "Fresh fruit"
        m.figure?.label = "tab:fruit"
        m.figure?.placement = "top"
        m.setText("Mango", row: 1, column: 0)
        let e = try #require(TableCode.edit(m, in: TableTests.rich))
        let out = (TableTests.rich as NSString).replacingCharacters(in: e.range, with: e.replacement)
        #expect(out.contains("caption: [Fresh fruit], placement: top") || out.contains("placement: top"))
        #expect(out.hasSuffix(") <tab:fruit>"))
        try await t.expectCompiles(out + "\n@tab:fruit", text: "Name Qty Mango 3 PEAR 5 Table 1: Fresh fruit Table 1")
        // Only a figure field changed: still an edit.
        var f = try t.model(TableTests.rich, at: "Apple")
        f.figure?.caption = ""
        #expect(f.isModified)
        let g = try #require(TableCode.edit(f, in: TableTests.rich))
        #expect(!(TableTests.rich as NSString).replacingCharacters(in: g.range, with: g.replacement).contains("caption"))
        #expect(try t.model(TableTests.plain, at: "a1").figure == nil)
    }

    // MARK: rendered cells

    @Test func cellsRenderAsTheDocumentSetsThem() async throws {
        let src = "#set heading(numbering: \"1\", supplement: [Abschnitt])\n= Intro <intro>\n\n#table(columns: 4, [*Bold*], [$2023$], [@intro], [], [intro])\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": src])
        let previewer = try #require(p.tablePreviewer())
        let images = await previewer.renderCells(["*Bold*", "$2023$", "@intro", "", "intro"], file: RelPath("main.typ")!, text: src,
                                                 fill: "black", size: 13)
        #expect(Set(images.keys) == ["*Bold*", "$2023$", "@intro", "intro"])
        for image in images.values { #expect(image.width > 0 && image.height > 0 && image.height < 40 * 2) }
        // "Abschnitt 1" is wider than the plain word: the reference resolved.
        #expect(try #require(images["@intro"]).width > 2 * #require(images["intro"]).width)
        // Transparent around the text, so the grid's background shows in dark mode.
        let bold = try #require(images["*Bold*"]), data = try #require(bold.dataProvider?.data as Data?)
        #expect(data[3] == 0)
        // The appended pages live only in the previewer's compile.
        #expect(try await p.exportPages(.svg).count == 1)
    }

    @Test func previewRendersTheTableArea() async throws {
        let src = "= Title\n\nSome text.\n\n" + TableTests.plain + "\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": src])
        let previewer = try #require(p.tablePreviewer())
        let range = (src as NSString).range(of: "table(")
        let image = try #require(await previewer.render(file: RelPath("main.typ")!, text: src,
                                                        range: NSRange(location: range.location, length: (src as NSString).length - range.location)))
        #expect(image.width > 100 && image.height > 20)
        #expect(await previewer.render(file: RelPath("main.typ")!, text: "#table(columns: 1)", range: NSRange(location: 0, length: 5)) == nil)
    }

    /// The table in an included file, under a template that adds a page after the body.
    @Test func cellsRenderFromAnIncludedFileUnderATemplate() async throws {
        let main = "#set heading(numbering: \"1\")\n#let t(b) = { b; pagebreak(); [After] }\n#show: t\n#include \"ch.typ\"\n"
        let ch = "= Intro <intro>\n\n#table(columns: 2, [@intro], [x])\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": main, "ch.typ": ch])
        let previewer = try #require(p.tablePreviewer())
        let images = await previewer.renderCells(["@intro", "x"], file: RelPath("ch.typ")!, text: ch,
                                                 fill: "rgb(\"#ffffffd9\")", size: 13)
        let ref = try #require(images["@intro"]), x = try #require(images["x"])
        #expect(ref.width > 2 * x.width && ref.height < 40 * 2)
    }
}
