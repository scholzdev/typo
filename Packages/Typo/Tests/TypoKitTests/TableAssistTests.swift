import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

@Suite struct TableAssistTests {
    static let doc = """
    Before.

    #figure(
      table(
        columns: (1fr, auto),
        stroke: 0.5pt,
        table.header([Name], [Qty]),
        [Pear], [5],
        [Apple], [$3$],
      ),
      caption: [Fruit],
    ) <tab:fruit>

    After.
    """

    func model(_ src: String = doc, at needle: String = "Pear") throws -> TableModel {
        let found = try #require(TableModel.lookup(in: src, at: (src as NSString).range(of: needle).location + 1))
        guard case .table(var m) = found else { Issue.record("\(found)"); throw CancellationError() }
        m.attachFigure(in: src)
        return m
    }

    // MARK: delete

    @Test func deleteRemovesWholeRowsOrColumnsAndClearsTheRest() throws {
        let m = try model()       // 3 rows (header + 2) × 2 columns
        #expect(m.deletion(rows: 1...2, columns: 0...1) == .rows)
        #expect(m.deletion(rows: 0...0, columns: 0...1) == .rows)        // the header row goes as a row
        #expect(m.deletion(rows: 0...2, columns: 1...1) == .columns)
        #expect(m.deletion(rows: 0...2, columns: 0...1) == .cells)       // the whole table is cleared, never removed
        #expect(m.deletion(rows: 1...2, columns: 0...0) == .cells)
        #expect(m.deletion(rows: 1...1, columns: 1...1) == .cells)
        let narrow = try model("#table(columns: 1, [a], [b])", at: "a")
        #expect(narrow.deletion(rows: 0...0, columns: 0...0) == .cells)  // one cell spans a 1-column table: cleared
        #expect(narrow.deletion(rows: 0...1, columns: 0...0) == .cells)
        let titled = try model("#table(columns: 2, table.cell(colspan: 2)[Title], [a], [b])", at: "a")
        #expect(titled.deletion(rows: 0...0, columns: 0...1) == .cells)  // a full-width merged cell is one cell
        #expect(titled.deletion(rows: 1...1, columns: 0...1) == .rows)
    }

    // MARK: reply

    @Test func replyTakesTheFencedCodeAndTheLineAfterIt() {
        let r = TableAssist.reply("Here you go:\n```typst\ntable(columns: 1, [a])\n```\n\nSorted 2 rows by Name.\nMore.")
        #expect(r.code == "table(columns: 1, [a])")
        #expect(r.summary == "Sorted 2 rows by Name.")
        let bare = TableAssist.reply("  table(columns: 1, [a])\n")
        #expect(bare.code == "table(columns: 1, [a])")
        #expect(bare.summary == nil)
        #expect(TableAssist.reply("```\n#table(columns: 1, [a])\n```").code == "#table(columns: 1, [a])")
    }

    // MARK: apply

    @Test func applyKeepsRangeCalleeAndFigureAndWritesTheNewCells() throws {
        let m = try model()
        let reply = """
        ```typst
        table(
          columns: (1fr, auto),
          stroke: 0.5pt,
          table.header([Name], [Qty]),
          [Apple], [$3$],
          [Pear], [5],
        )
        ```
        Sorted 2 rows by Name.
        """
        let (new, summary) = try #require(TableAssist.apply(reply, to: m))
        #expect(summary == "Sorted 2 rows by Name.")
        #expect(new.range == m.range && new.callee == m.callee && new.figure == m.figure)
        #expect(new.isModified)
        let e = try #require(TableCode.edit(new, in: Self.doc))
        #expect(e.range == m.range)
        let out = (Self.doc as NSString).replacingCharacters(in: e.range, with: e.replacement)
        #expect(out.contains("[Apple], [$3$],\n    [Pear], [5],"), "\(out)")
        #expect(out.hasPrefix("Before.\n\n#figure(\n  table(") && out.hasSuffix("caption: [Fruit],\n) <tab:fruit>\n\nAfter."), "\(out)")
        #expect(try model(out, at: "Apple").rows.map { $0.map(\.text) } == [["Apple", "$3$"], ["Pear", "5"]])
    }

    @Test func applyingTheSameTableChangesNothing() throws {
        let m = try model()
        let same = "```typst\n" + TableCode.render(m) + "\n```"
        let (new, _) = try #require(TableAssist.apply(same, to: m))
        #expect(new == m)
        #expect(!new.isModified)
    }

    @Test func applyRejectsUnreadableOrOtherTables() throws {
        let m = try model()
        #expect(TableAssist.apply("I can't do that.", to: m) == nil)
        #expect(TableAssist.apply("```typst\ngrid(columns: 1, [a])\n```", to: m) == nil)
        #expect(TableAssist.apply("```typst\ntable(columns: 2, table.cell(colspan: 3)[x])\n```", to: m) == nil)
        // A figure the model added anyway: the table inside is still read.
        #expect(TableAssist.apply("```typst\nfigure(table(columns: 1, [a]), caption: [x])\n```", to: m)?.model.columns.count == 1)
    }

    @Test func messageCarriesTableCaptionSelectionAndRequest() {
        let s = TableAssist.message(markup: "table(columns: 1, [a])", caption: "Fruit", selection: "B2:B3", request: "Sort")
        #expect(s.contains("```typst\ntable(columns: 1, [a])\n```") && s.contains("Fruit") && s.contains("B2:B3") && s.hasSuffix("Change: Sort"))
        #expect(TableAssist.system(callee: "grid").contains("`grid.cell`"))
    }
}
