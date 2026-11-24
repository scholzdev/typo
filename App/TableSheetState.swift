import AppKit
import TypoKit
import TypstEngine

/// The open table editor: the model being edited, the selection, and the editor's own undo history.
@MainActor @Observable final class TableSheetState {
    struct Point: Equatable, Hashable { var row: Int; var column: Int }

    private(set) var model: TableModel
    /// The active cell (always a merged cell's top-left slot) and the other corner of the selection.
    private(set) var cursor = Point(row: 0, column: 0)
    private(set) var anchor = Point(row: 0, column: 0)
    /// Undo and redo of every edit made in the sheet; the document gets one edit on Done.
    @ObservationIgnored let undo = UndoManager()
    /// Cell markup as the document renders it, at the grid's text size; a cell without one shows its markup.
    var cellImages: [String: NSImage] = [:]
    /// The grid shows every cell's markup instead of its rendered image.
    var showsRaw = false
    /// Writes an open cell edit into the model (the grid sets it); every change runs it first, so the field can't overwrite the change.
    @ObservationIgnored var commitEdit: () -> Void = {}
    /// True while a figure field is being typed in after its first edit: later keystrokes join that undo step.
    @ObservationIgnored private var coalescing = false

    init(model: TableModel) {
        self.model = model
        undo.groupsByEvent = true
    }

    var rowCount: Int { model.rowCount }
    var columnCount: Int { model.columns.count }

    /// The selected rectangle, grown over merged cells it cuts.
    var selection: (rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        model.covering(rows: min(cursor.row, anchor.row)...max(cursor.row, anchor.row),
                       columns: min(cursor.column, anchor.column)...max(cursor.column, anchor.column))
    }

    var selectedColumns: ClosedRange<Int> { selection.columns }
    var isSingleCell: Bool {
        let s = selection, a = model.anchor(row: s.rows.lowerBound, column: s.columns.lowerBound)
        let cell = model.cell(row: a.row, column: a.column)
        return s.rows.count == cell.rowspan && s.columns.count == cell.colspan
    }

    /// Moves the active cell; `extend` keeps the other corner where it is.
    func select(_ p: Point, extend: Bool = false) {
        let r = min(max(p.row, 0), max(rowCount - 1, 0)), c = min(max(p.column, 0), max(columnCount - 1, 0))
        let a = model.anchor(row: r, column: c)
        cursor = extend ? Point(row: r, column: c) : Point(row: a.row, column: a.column)
        if !extend { anchor = cursor }
    }

    func selectAll() {
        anchor = Point(row: 0, column: 0)
        cursor = Point(row: max(rowCount - 1, 0), column: max(columnCount - 1, 0))
    }

    func selectRows(_ rows: ClosedRange<Int>) {
        anchor = Point(row: rows.lowerBound, column: 0)
        cursor = Point(row: rows.upperBound, column: max(columnCount - 1, 0))
    }

    func selectColumns(_ columns: ClosedRange<Int>) {
        anchor = Point(row: 0, column: columns.lowerBound)
        cursor = Point(row: max(rowCount - 1, 0), column: columns.upperBound)
    }

    /// One undoable step named `name`; nothing is recorded when the model does not change.
    /// `coalesce` joins the change to the previous one while that one coalesced too, until `endCoalescing`.
    func change(_ name: LocalizedStringResource, coalesce: Bool = false, _ body: (inout TableModel) -> Void) {
        commitEdit()
        var m = model
        body(&m)
        guard m != model else { return }
        if !(coalesce && coalescing) { record(name) }
        coalescing = coalesce
        model = m
        clampSelection()
    }

    private func record(_ name: LocalizedStringResource) {
        let old = model, sel = (cursor, anchor)
        undo.registerUndo(withTarget: self) { s in s.restore(old, sel, name) }
        undo.setActionName(String(localized: name))
    }

    func endCoalescing() { coalescing = false }

    private func restore(_ m: TableModel, _ sel: (Point, Point), _ name: LocalizedStringResource) {
        coalescing = false
        record(name)                        // registered while undoing: becomes the redo
        model = m
        (cursor, anchor) = sel
        clampSelection()
    }

    private func clampSelection() {
        func clamp(_ p: Point) -> Point {
            Point(row: min(max(p.row, 0), max(rowCount - 1, 0)), column: min(max(p.column, 0), max(columnCount - 1, 0)))
        }
        cursor = clamp(cursor)
        anchor = clamp(anchor)
        let a = model.anchor(row: cursor.row, column: cursor.column)
        if anchor == cursor { anchor = Point(row: a.row, column: a.column) }
        cursor = Point(row: a.row, column: a.column)
    }

    // MARK: edits on the selection

    func clearSelection() {
        let s = selection
        change("Clear") { $0.clear(rows: s.rows, columns: s.columns) }
    }

    /// Delete: removes selected whole rows or columns, else clears the cells.
    func deleteSelection() {
        let s = selection
        switch model.deletion(rows: s.rows, columns: s.columns) {
        case .rows: deleteRows()
        case .columns: deleteColumns()
        case .cells: clearSelection()
        }
    }

    func toggleEmphasis(_ marker: Character) {
        let s = selection
        change(marker == "*" ? "Bold" : marker == "_" ? "Italic" : "Code") { $0.toggleEmphasis(marker, rows: s.rows, columns: s.columns) }
    }

    func mergeSelection() {
        let s = selection
        change("Merge Cells") { $0.merge(rows: s.rows, columns: s.columns) }
        select(Point(row: s.rows.lowerBound, column: s.columns.lowerBound))
    }

    func unmergeSelection() {
        let s = selection
        change("Unmerge Cells") { m in
            for r in s.rows { for c in s.columns where m.cell(row: r, column: c).isMerged { m.unmerge(row: r, column: c) } }
        }
    }

    var canMerge: Bool {
        let s = selection
        return !isSingleCell && (s.rows.lowerBound >= model.headerRows || s.rows.upperBound < model.headerRows)
    }

    var canUnmerge: Bool {
        let s = selection
        return s.rows.contains { r in s.columns.contains { model.cell(row: r, column: $0).isMerged } }
    }

    /// Text of the selected cells as rows (covered slots are empty).
    var selectedTexts: [[String]] {
        let s = selection
        return s.rows.map { r in s.columns.map { c in model.cell(row: r, column: c).covered ? "" : model.cell(row: r, column: c).text } }
    }

    func paste(_ values: [[String]]) {
        let s = selection
        // One value fills the whole selection, as in Numbers.
        let fill = values.count == 1 && values[0].count == 1 && !isSingleCell
            ? Array(repeating: Array(repeating: values[0][0], count: s.columns.count), count: s.rows.count) : values
        var written: (rows: ClosedRange<Int>, columns: ClosedRange<Int>)?
        change("Paste") { written = $0.paste(fill, row: s.rows.lowerBound, column: s.columns.lowerBound) }
        if let written {
            anchor = Point(row: written.rows.lowerBound, column: written.columns.lowerBound)
            cursor = Point(row: written.rows.upperBound, column: written.columns.upperBound)
        }
    }

    func setText(_ text: String, at p: Point) {
        change("Typing") { $0.setText(text, row: p.row, column: p.column) }
    }

    /// The active cell's markup, for the formula bar: one undo step per visit (see `endCoalescing`).
    var activeText: String {
        get { model.cell(row: cursor.row, column: cursor.column).text }
        set { let p = cursor; change("Typing", coalesce: true) { $0.setText(newValue, row: p.row, column: p.column) } }
    }

    func setFill(_ fill: String?) {
        let s = selection
        change("Cell Fill") { $0.setFill(fill, rows: s.rows, columns: s.columns) }
    }

    /// Left, center, right and round again; for the alignment icon in the column bar.
    func cycleAlignment(column c: Int) {
        guard model.alignEditable, model.columns.indices.contains(c) else { return }
        let next = switch model.columns[c].horizontal { case "center": "right"; case "right", "end": "left"; default: "center" }
        change("Alignment") { $0.columns[c].horizontal = next }
    }

    enum TableWidth { case auto, full, custom }

    /// Auto: every column fits its content; Full: every column `1fr`, so the table spans the text width.
    var tableWidth: TableWidth {
        let ws = model.columns.map(\.width)
        return ws.allSatisfy { $0 == .auto } ? .auto : ws.allSatisfy { $0 == .fraction(1) } ? .full : .custom
    }

    func setTableWidth(_ w: TableWidth) {
        guard w != .custom, columnCount > 0 else { return }
        change("Table Width") { m in for c in m.columns.indices { m.columns[c].width = w == .full ? .fraction(1) : .auto } }
    }

    func setHorizontal(_ align: String?) {
        let cols = selectedColumns
        change("Alignment") { m in for c in cols { m.columns[c].horizontal = align } }
    }

    func setVertical(_ align: String?) {
        let cols = selectedColumns
        change("Alignment") { m in for c in cols { m.columns[c].vertical = align } }
    }

    func setWidth(_ width: ColumnWidth, columns: ClosedRange<Int>) {
        change("Column Width") { m in for c in columns { m.columns[c].width = width } }
    }

    func applyStyle(_ style: TableStyle) { change("Table Style") { $0.applyStyle(style) } }

    func toggleHeader() { change("Header Row") { $0.toggleHeader() } }

    // MARK: rows and columns

    func insertRows(above: Bool) {
        let s = selection
        change(s.rows.count > 1 ? "Insert Rows" : "Insert Row") { m in
            for _ in s.rows { m.insertRow(at: above ? s.rows.lowerBound : s.rows.upperBound + 1) }
        }
        if !above { select(Point(row: s.rows.upperBound + 1, column: cursor.column)) }
    }

    func insertColumns(left: Bool) {
        let s = selection
        change(s.columns.count > 1 ? "Insert Columns" : "Insert Column") { m in
            for _ in s.columns { m.insertColumn(at: left ? s.columns.lowerBound : s.columns.upperBound + 1) }
        }
        if !left { select(Point(row: cursor.row, column: s.columns.upperBound + 1)) }
    }

    func appendRow() {
        change("Add Row") { $0.insertRow(at: $0.rowCount) }
        select(Point(row: rowCount - 1, column: 0))
    }

    func appendColumn() {
        change("Add Column") { $0.insertColumn(at: $0.columns.count) }
        select(Point(row: cursor.row, column: columnCount - 1))
    }

    func deleteRows() {
        let s = selection
        change(s.rows.count > 1 ? "Delete Rows" : "Delete Row") { $0.deleteRows(s.rows) }
    }

    func deleteColumns() {
        let s = selection
        change(s.columns.count > 1 ? "Delete Columns" : "Delete Column") { $0.deleteColumns(s.columns) }
    }

    func duplicateRows() {
        let s = selection
        change("Duplicate Row") { m in for r in s.rows.reversed() { m.duplicateRow(at: r) } }
    }

    func duplicateColumns() {
        let s = selection
        change("Duplicate Column") { m in for c in s.columns.reversed() { m.duplicateColumn(at: c) } }
    }

    func moveRow(from: Int, to: Int) {
        change("Move Row") { $0.moveRow(from: from, to: to) }
        select(Point(row: min(max(to, model.headerRows), rowCount - 1), column: cursor.column))
        selectRows(cursor.row...cursor.row)
    }

    func moveColumn(from: Int, to: Int) {
        change("Move Column") { $0.moveColumn(from: from, to: to) }
        let c = min(max(to, 0), columnCount - 1)
        selectColumns(c...c)
    }

    /// `typing`: one undo step per editing session of a text field (see `endCoalescing`).
    func setFigure(typing: Bool = false, _ body: (inout TableModel.Figure) -> Void) {
        change("Edit Figure", coalesce: typing) { m in if var f = m.figure { body(&f); m.figure = f } }
    }
}
