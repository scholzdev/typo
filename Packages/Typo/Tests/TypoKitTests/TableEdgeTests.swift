import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

/// Deleting everything, raw fences and fill colours in the spreadsheet editor.
@Suite(.serialized) @MainActor struct TableEdgeTests {
    let t = TableTests()

    @Test func deletingEveryRowOrColumnKeepsOneAndCompiles() async throws {
        var m = try t.model(TableTests.plain, at: "a1")
        m.deleteRows(0...2)                                     // all of them: cleared, as Delete clears the whole table
        #expect(m.rowCount == 3 && m.grid.allSatisfy { $0.allSatisfy(\.text.isEmpty) })
        for _ in 0..<5 { m.deleteRow(at: 0) }
        #expect(m.rowCount == 1 && m.header == nil)
        m.deleteColumns(0...2)
        #expect(m.columns.count == 3)
        for _ in 0..<5 { m.deleteColumn(at: 0) }
        #expect(m.columns.count == 1)
        m.setText("x", row: 0, column: 0)
        try await t.expectCompiles("#" + TableCode.render(m), text: "x")

        // Every body row goes, the header stays: a header-only table, which Typst accepts.
        var h = try t.model(TableTests.plain, at: "a1")
        h.deleteRows(1...2)
        #expect(h.rowCount == 1 && h.rows.isEmpty && h.cell(row: 0, column: 2).text == "H3")
        h.deleteRows(0...0)
        #expect(h.rowCount == 1 && h.header?.map(\.text) == ["", "", ""])
        h.setText("H", row: 0, column: 0)
        try await t.expectCompiles("#" + TableCode.render(h), text: "H")
    }

    @Test func anEmptyTableGetsARowAndIsUnchanged() throws {
        let src = "#table(columns: 2)"
        var m = try t.model(src, at: "table")
        #expect(m.rowCount == 1 && m.columns.count == 2 && !m.isModified)
        m.setText("a", row: 0, column: 1)
        #expect(TableCode.render(m).contains("[], [a],"))
    }

    @Test func codeTogglePicksAFenceLongerThanTheBackticksInside() async throws {
        let cases: [(String, String)] = [
            ("x", "`x`"), ("a`b", "``` a`b```"), ("`x`", "``` `x` ```"), ("a```b", "```` a```b````"), ("rust x`", "``` rust x` ```"), ("x` ", "``` x`  ```"),
        ]
        for (text, raw) in cases {
            #expect(TableCode.wrapped(text, in: "`") == raw)
            #expect(TableCode.isWrapped(raw, in: "`"))
            #expect(TableCode.unwrapped(raw, from: "`") == text)
        }
        // Two raws, or a two-backtick (empty) raw, are not one wrapped cell.
        for text in ["`a` and `b`", "``x``", "`", "``` x``` y"] { #expect(!TableCode.isWrapped(text, in: "`"), "\(text)") }

        var m = try t.model(TableTests.plain, at: "a1")
        m.setText("a`b", row: 1, column: 0)
        m.setText("`a` and `b`", row: 1, column: 1)
        m.toggleEmphasis("`", rows: 1...1, columns: 0...1)
        #expect(m.rows[0].prefix(2).map(\.text) == ["``` a`b```", "``` `a` and `b` ```"])
        try await t.expectCompiles("#" + TableCode.render(m), text: "H1 H2 H3 a`b `a` and `b` a3 b1 b2 b3")
        m.toggleEmphasis("`", rows: 1...1, columns: 0...1)
        #expect(m.rows[0].prefix(2).map(\.text) == ["a`b", "`a` and `b`"])
    }

    @Test func fillColours() throws {
        func rgb(_ s: String) -> [Int]? { TableFill.color(s).map { [$0.red, $0.green, $0.blue].map { Int(($0 * 255).rounded()) } } }
        #expect(rgb("red") == [255, 65, 54])
        #expect(rgb("red.lighten(70%)") == [255, 198, 195])
        #expect(rgb("luma(235)") == [235, 235, 235])
        #expect(rgb(##"rgb("#336699")"##) == [51, 102, 153])
        #expect(rgb("blue.darken(50%)") == [0, 58, 109])
        #expect(rgb("(x, y) => red") == nil && rgb("gradient.linear(red, blue)") == nil && rgb("myfill") == nil)

        var m = try t.model(TableGridTests.spanned, at: "a2")
        #expect(m.shownFill(row: 2, column: 0) == "red")       // the merged cell's fill, from a covered slot
        #expect(m.shownFill(row: 1, column: 1) == nil)
        m.applyStyle(.striped)
        #expect(m.shownFill(row: 1, column: 1) == "luma(240)" && m.shownFill(row: 2, column: 1) == nil)
    }
}
