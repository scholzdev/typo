import Foundation
import TypstEngine

public enum TableLookup: Equatable, Sendable {
    case table(TableModel)
    case unsupported(reason: String)
}

public struct ColumnSpec: Equatable, Sendable {
    /// Source of this column's `columns:` array entry; nil writes `auto` (or the integer form).
    public var size: String?
    /// `left`, `center`, `right` or any other alignment source; nil is the default.
    public var align: String?

    public init(size: String? = nil, align: String? = nil) { self.size = size; self.align = align }

    static let verticals: Set<String> = ["top", "horizon", "bottom"]

    /// The horizontal part of `align` (`left + top` → `left`).
    public var horizontal: String? {
        get { Self.split(align).h }
        set { align = Self.join(newValue, vertical) }
    }

    /// The vertical part of `align` (`top`, `horizon`, `bottom`).
    public var vertical: String? {
        get { Self.split(align).v }
        set { align = Self.join(horizontal, newValue) }
    }

    public var width: ColumnWidth {
        get { ColumnWidth(size) }
        set { size = newValue.size }
    }

    static func split(_ a: String?) -> (h: String?, v: String?) {
        guard let a else { return (nil, nil) }
        let parts = a.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        let v = parts.first { verticals.contains($0) }
        let h = parts.filter { !verticals.contains($0) }.joined(separator: " + ")
        return (h.isEmpty ? nil : h, v)
    }

    static func join(_ h: String?, _ v: String?) -> String? {
        let s = [h, v].compactMap { $0 }.joined(separator: " + ")
        return s.isEmpty ? nil : s
    }
}

/// One entry of `columns:`.
public enum ColumnWidth: Equatable, Sendable {
    case auto, points(Double), fraction(Double), other(String)

    public init(_ size: String?) {
        let s = size?.trimmingCharacters(in: .whitespaces) ?? "auto"
        if s == "auto" { self = .auto }
        else if s.hasSuffix("pt"), let v = Double(s.dropLast(2)), v > 0 { self = .points(v) }
        else if s.hasSuffix("fr"), let v = Double(s.dropLast(2)), v > 0 { self = .fraction(v) }
        else { self = .other(s) }
    }

    /// The source for `columns:`; nil is `auto`.
    public var size: String? {
        switch self {
        case .auto: nil
        case .points(let v): "\(Self.number(v))pt"
        case .fraction(let v): "\(Self.number(v))fr"
        case .other(let s): s
        }
    }

    static func number(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e9 ? String(Int(v)) : String(format: "%.4g", v)
    }
}

/// A `table(...)` / `grid(...)` call as a grid of cells. Edits change the model; `TableCode.render` writes it back.
public struct TableModel: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        /// Source text as written; kept verbatim while `text` and the spans are untouched.
        public var original: String?
        /// What the editor shows: the markup inside `[...]`, or `#` + the source of any other expression.
        public var text: String
        public var colspan = 1
        public var rowspan = 1
        /// Part of a merged cell to its left or above: it stays in the grid so indices hold, but is never written.
        public internal(set) var covered = false
        /// A slot the source left empty after its last cell; written only once it has text.
        var hole = false
        /// Named arguments of `table.cell(...)` other than the spans (`fill: red`), written back as they were.
        var cellArgs: [String] = []
        fileprivate var initial: String
        fileprivate var initialSpan = [1, 1]
        fileprivate var initialArgs: [String] = []

        public init(text: String = "") { original = nil; self.text = text; initial = text }
        init(_ raw: RawTable.Cell) { original = raw.source; text = raw.inner; initial = raw.inner }
        init(source: String, text: String, colspan: Int, rowspan: Int, args: [String]) {
            original = source; self.text = text; initial = text
            self.colspan = colspan; self.rowspan = rowspan; initialSpan = [colspan, rowspan]; cellArgs = args; initialArgs = args
        }
        static var coveredCell: Cell { var c = Cell(); c.covered = true; return c }
        var isUnchanged: Bool { original != nil && text == initial && [colspan, rowspan] == initialSpan && cellArgs == initialArgs }
        public var isMerged: Bool { colspan > 1 || rowspan > 1 }
    }

    /// A `table.hline(...)` / `table.vline(...)` written verbatim before the cells of display row `row` (`rowCount`: after the last).
    public struct Rule: Equatable, Sendable {
        public var source: String
        public var row: Int
        public init(source: String, row: Int) { self.source = source; self.row = row }
        var isHorizontal: Bool { source.contains(".hline") }
    }

    /// The `figure(...)` the table is the body of: what its fields show.
    public struct Figure: Equatable, Sendable {
        public var caption: String
        public var label: String
        public var placement: String
    }

    enum Slot: Equatable, Sendable { case columns, align, verbatim(String) }

    public let callee: String
    public let range: NSRange                        // the call, without a leading `#`
    public var columns: [ColumnSpec]
    public var header: [Cell]?
    public var headerArgs: [String]                  // e.g. "repeat: false", written back verbatim
    public var rows: [[Cell]]
    public var rules: [Rule] = []
    /// Nil when the table is not the body of a figure.
    public var figure: Figure?
    /// False when `align:` is something else (a function), which the editor keeps as written.
    public let alignEditable: Bool

    var slots: [Slot]                                // named args in source order
    let columnsOriginal: String?, columnsBaseline: [String?]
    let alignOriginal: String?, alignBaseline: [String?]
    private(set) var pristine = ""
    private(set) var figureBaseline: Figure?

    /// What a span cell or a line stands for in the parse; see `TableModel.lookup`.
    enum Special { case cell(Cell), rule(String) }
    static let specialMark = "\u{E010}", padMark = "\u{E011}"

    /// Nil when the cells can't be laid out (a span that leaves the table or overlaps another).
    init?(_ raw: RawTable, specials: [Special] = [], range: NSRange? = nil) {
        callee = raw.callee
        self.range = range ?? raw.range
        let cols = raw.args.first { $0.name == "columns" }
        let count = switch cols?.shape { case 1: max(1, Int(cols!.value) ?? 1); case 2: max(1, cols!.items.count); default: 1 }
        let sizes: [String?] = (0..<count).map { cols?.shape == 2 && $0 < cols!.items.count ? cols!.items[$0] : nil }
        let align = raw.args.first { $0.name == "align" }
        alignEditable = align == nil || align!.shape == 2 || align!.shape == 3
        func entry(_ s: String) -> String? { s == "auto" ? nil : s }
        let aligns: [String?] = (0..<count).map { i in
            switch align?.shape {
            case 3: entry(align!.value)
            case 2: align!.items.isEmpty ? nil : entry(align!.items[i % align!.items.count])
            default: nil
            }
        }
        columns = (0..<count).map { ColumnSpec(size: sizes[$0], align: aligns[$0]) }
        columnsOriginal = cols?.value
        columnsBaseline = sizes
        alignOriginal = align?.value
        alignBaseline = aligns
        slots = raw.args.map { $0.name == "columns" ? .columns : $0.name == "align" ? .align : .verbatim("\($0.name): \($0.value)") }
        headerArgs = raw.headerArgs.map { "\($0.name): \($0.value)" }

        var queue = specials[...]
        func item(_ c: RawTable.Cell) -> Special? {
            if c.isContent && c.inner == Self.specialMark { return queue.popFirst() }
            if c.isContent && c.inner == Self.padMark { return nil }
            return .cell(Cell(c))
        }
        if let h = raw.header {
            guard let placed = Self.place(h.compactMap(item), columns: count, rowOffset: 0), placed.grid.count <= 1, placed.rules.isEmpty else { return nil }
            header = placed.grid.first ?? Array(repeating: Cell(), count: count)
        } else {
            header = nil
        }
        guard let body = Self.place(raw.cells.compactMap(item), columns: count, rowOffset: raw.header == nil ? 0 : 1) else { return nil }
        // An empty `table(columns: n)` still gets a row to edit: holes stay unwritten, so the source is unchanged.
        rows = body.grid.isEmpty && header == nil ? [Array(repeating: { var c = Cell(); c.hole = true; return c }(), count: count)] : body.grid
        rules = body.rules
        pristine = TableCode.render(self)
    }

    /// Lays cells out the way Typst places them automatically: left to right, skipping slots a span above already took.
    static func place(_ items: [Special], columns: Int, rowOffset: Int) -> (grid: [[Cell]], rules: [Rule])? {
        var grid: [[Cell?]] = []
        var rules: [Rule] = []
        var r = 0, c = 0
        func ensure(_ row: Int) { while grid.count <= row { grid.append(Array(repeating: nil, count: columns)) } }
        func skipTaken() { while true { ensure(r); if grid[r][c] == nil { return }; c += 1; if c == columns { c = 0; r += 1 } } }
        for item in items {
            switch item {
            case .rule(let source):
                while r < grid.count, grid[r][c] != nil { c += 1; if c == columns { c = 0; r += 1 } }    // no new row for a line
                // A vertical line in mid-row would move if written at a row boundary.
                if c != 0 && source.contains(".vline") { return nil }
                rules.append(Rule(source: source, row: rowOffset + r + (c == 0 ? 0 : 1)))
            case .cell(let cell):
                skipTaken()
                guard cell.colspan >= 1, cell.rowspan >= 1, c + cell.colspan <= columns else { return nil }
                ensure(r + cell.rowspan - 1)
                for rr in r..<r + cell.rowspan { for cc in c..<c + cell.colspan where grid[rr][cc] != nil { return nil } }
                for rr in r..<r + cell.rowspan { for cc in c..<c + cell.colspan { grid[rr][cc] = .coveredCell } }
                grid[r][c] = cell
                c += cell.colspan
                if c == columns { c = 0; r += 1 }
            }
        }
        return (grid.map { $0.map { $0 ?? { var c = Cell(); c.hole = true; return c }() } }, rules)
    }

    public var rowCount: Int { rows.count + headerRows }
    /// False until an edit changes what would be written: applying an unmodified model is a no-op.
    public var isModified: Bool { TableCode.render(self) != pristine || figure != figureBaseline }

    public var headerRows: Int { header == nil ? 0 : 1 }

    /// The header (if any) and the body rows as one grid, header first.
    public var grid: [[Cell]] {
        get { (header.map { [$0] } ?? []) + rows }
        set {
            if header != nil, let first = newValue.first { header = first; rows = Array(newValue.dropFirst()) } else { rows = newValue }
        }
    }

    /// Rows are addressed as shown: the header, if any, is row 0. A covered slot returns the covered placeholder.
    public func cell(row: Int, column: Int) -> Cell { row < headerRows ? header![column] : rows[row - headerRows][column] }

    /// The top-left slot of the merged cell covering (`row`, `column`); the slot itself when it is not covered.
    public func anchor(row: Int, column: Int) -> (row: Int, column: Int) { Self.anchor(in: grid, row: row, column: column) }

    static func anchor(in g: [[Cell]], row: Int, column: Int) -> (row: Int, column: Int) {
        guard g.indices.contains(row), g[row].indices.contains(column), g[row][column].covered else { return (row, column) }
        for r in stride(from: row, through: 0, by: -1) {
            for c in stride(from: column, through: 0, by: -1) {
                let a = g[r][c]
                if !a.covered && r + a.rowspan > row && c + a.colspan > column { return (r, c) }
            }
        }
        return (row, column)
    }

    /// Writes to the merged cell when the slot is covered.
    public mutating func setText(_ text: String, row: Int, column: Int) {
        let a = anchor(row: row, column: column)
        if a.row < headerRows { header![a.column].text = text } else { rows[a.row - headerRows][a.column].text = text }
    }

    private var emptyRow: [Cell] { Array(repeating: Cell(), count: columns.count) }

    // MARK: rows

    /// Inserts above `index`; nothing goes above the header. A row inserted inside a merged cell makes it taller.
    public mutating func insertRow(at index: Int) {
        let i = min(max(index, headerRows), rowCount), old = rowCount
        grid = Self.inserting(grid, at: i, width: columns.count)
        for k in rules.indices where rules[k].row > i || (i == old && rules[k].row == i) { rules[k].row += 1 }
    }

    /// Deleting the header row removes the `table.header` wrapper and the row with it. A merged cell over the row gets shorter.
    /// A table keeps at least one row, as it keeps a column.
    public mutating func deleteRow(at index: Int) {
        guard rowCount > 1, index >= 0, index < rowCount else { return }
        if index < headerRows { header = nil } else { grid = Self.removing(grid, at: index) }
        for k in rules.indices where rules[k].row > index { rules[k].row -= 1 }
    }

    /// `to` is the row's index after the move. The header does not move and nothing moves above it.
    /// Merged cells reaching over the rows in between are split first. Lines on the row's own top and bottom go with it,
    /// except the table's edges (top, under the header, bottom); the others shift as a delete and an insert would.
    public mutating func moveRow(from: Int, to: Int) {
        let f = from - headerRows
        guard rows.indices.contains(f) else { return }
        let t = min(max(to - headerRows, 0), rows.count - 1)
        guard f != t else { return }
        var g = grid
        Self.unmergeCrossing(&g, lines: min(from, t + headerRows)...max(from, t + headerRows))
        grid = g
        rows.insert(rows.remove(at: f), at: t)
        let dt = t + headerRows
        for k in rules.indices {
            let b = rules[k].row, edge = b <= headerRows || b >= rowCount
            if !edge && b == from { rules[k].row = dt; continue }
            if !edge && b == from + 1 { rules[k].row = dt + 1; continue }
            var n = b > from ? b - 1 : b
            if n > dt || (n == dt && dt == rowCount - 1) { n += 1 }
            rules[k].row = n
        }
    }

    /// A copy of the row goes below it (a copied header row becomes the first body row).
    public mutating func duplicateRow(at index: Int) {
        guard index >= 0, index < rowCount else { return }
        var g = grid
        Self.unmergeCrossing(&g, lines: index...index)
        let copy = g[index].map { c in c.covered ? c : { var c = c; c.rowspan = 1; return c }() }
        g.insert(copy, at: index + 1)
        grid = g
        for k in rules.indices where rules[k].row > index { rules[k].row += 1 }
    }

    /// The first body row becomes the header and back. With no rows, the header is a new empty row.
    public mutating func toggleHeader() {
        if let h = header { rows.insert(h, at: 0); header = nil; return }
        guard !rows.isEmpty else { header = emptyRow; return }
        var g = grid
        Self.unmergeCrossing(&g, lines: 0...0)
        rows = g
        header = rows.removeFirst()
    }

    // MARK: columns

    public mutating func insertColumn(at index: Int) {
        let i = min(max(index, 0), columns.count)
        columns.insert(ColumnSpec(), at: i)
        grid = Self.transposed(Self.inserting(Self.transposed(grid), at: i, width: rowCount))
    }

    /// A table keeps at least one column.
    public mutating func deleteColumn(at index: Int) {
        guard columns.count > 1, columns.indices.contains(index) else { return }
        columns.remove(at: index)
        grid = Self.transposed(Self.removing(Self.transposed(grid), at: index))
    }

    /// `to` is the column's index after the move.
    public mutating func moveColumn(from: Int, to: Int) {
        guard columns.indices.contains(from) else { return }
        let t = min(max(to, 0), columns.count - 1)
        guard from != t else { return }
        var g = Self.transposed(grid)
        Self.unmergeCrossing(&g, lines: min(from, t)...max(from, t))
        g.insert(g.remove(at: from), at: t)
        columns.insert(columns.remove(at: from), at: t)
        grid = Self.transposed(g)
    }

    public mutating func duplicateColumn(at index: Int) {
        guard columns.indices.contains(index) else { return }
        var g = Self.transposed(grid)
        Self.unmergeCrossing(&g, lines: index...index)
        g.insert(g[index].map { c in c.covered ? c : { var c = c; c.colspan = 1; return c }() }, at: index + 1)
        columns.insert(columns[index], at: index + 1)
        grid = Self.transposed(g)
    }

    public mutating func setAlignment(_ align: String?, column: Int) {
        guard alignEditable, columns.indices.contains(column) else { return }
        columns[column].align = align
    }

    // MARK: ranges

    /// Merges the rectangle (grown to take in merged cells it cuts) into its top-left cell, joining the texts.
    /// False when it would join the header and the body, or is one cell.
    /// The rectangle grown until it cuts no merged cell: what a selection from one corner to the other covers.
    public func covering(rows rr: ClosedRange<Int>, columns cr: ClosedRange<Int>) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>) {
        let g = grid
        var (r0, r1, c0, c1) = (max(0, rr.lowerBound), min(rr.upperBound, g.count - 1), max(0, cr.lowerBound), min(cr.upperBound, columns.count - 1))
        guard r0 <= r1, c0 <= c1 else { return (rr, cr) }
        var grown = true
        while grown {
            grown = false
            for r in r0...r1 { for c in c0...c1 {
                let a = Self.anchor(in: g, row: r, column: c), cell = g[a.row][a.column]
                let (ar1, ac1) = (a.row + cell.rowspan - 1, a.column + cell.colspan - 1)
                if a.row < r0 || a.column < c0 || ar1 > r1 || ac1 > c1 {
                    (r0, c0, r1, c1) = (min(r0, a.row), min(c0, a.column), max(r1, ar1), max(c1, ac1))
                    grown = true
                }
            } }
        }
        return (r0...r1, c0...c1)
    }

    /// Merges the rectangle (grown to take in merged cells it cuts) into its top-left cell, joining the texts.
    /// False when it would join the header and the body, or is one cell.
    @discardableResult
    public mutating func merge(rows rr: ClosedRange<Int>, columns cr: ClosedRange<Int>) -> Bool {
        var g = grid
        guard rr.lowerBound >= 0, rr.upperBound < g.count, cr.lowerBound >= 0, cr.upperBound < columns.count else { return false }
        let area = covering(rows: rr, columns: cr)
        let (r0, r1, c0, c1) = (area.rows.lowerBound, area.rows.upperBound, area.columns.lowerBound, area.columns.upperBound)
        guard (r0, c0) != (r1, c1), r0 >= headerRows || r1 < headerRows else { return false }
        let texts = (r0...r1).flatMap { r in (c0...c1).map { g[r][$0] } }.filter { !$0.covered && !$0.text.isEmpty }.map(\.text)
        for r in r0...r1 { for c in c0...c1 { g[r][c] = .coveredCell } }
        var anchor = grid[r0][c0]
        if anchor.covered { anchor = Cell() }
        anchor.text = texts.joined(separator: " ")
        anchor.colspan = c1 - c0 + 1
        anchor.rowspan = r1 - r0 + 1
        g[r0][c0] = anchor
        grid = g
        return true
    }

    /// Splits the merged cell covering the slot back into single cells; the text stays in the top-left one.
    public mutating func unmerge(row: Int, column: Int) {
        var g = grid
        let a = Self.anchor(in: g, row: row, column: column)
        Self.unmerge(&g, a.row, a.column)
        grid = g
    }

    static func unmerge(_ g: inout [[Cell]], _ r: Int, _ c: Int) {
        let cell = g[r][c]
        guard !cell.covered, cell.isMerged else { return }
        for rr in r..<r + cell.rowspan { for cc in c..<c + cell.colspan { g[rr][cc] = Cell() } }
        g[r][c] = cell
        g[r][c].colspan = 1
        g[r][c].rowspan = 1
    }

    public enum Deletion: Equatable, Sendable { case rows, columns, cells }

    /// What Delete does to the rectangle: whole rows or whole columns go; one cell, the whole table or anything else is cleared.
    public func deletion(rows rr: ClosedRange<Int>, columns cr: ClosedRange<Int>) -> Deletion {
        let a = cell(row: rr.lowerBound, column: cr.lowerBound)
        // One (merged) cell can span a 1-column table or a full-width title: clearing it is what the user means.
        if !a.covered && rr.count == a.rowspan && cr.count == a.colspan { return .cells }
        let allRows = rr.count >= rowCount, allColumns = cr.count >= columns.count
        return allRows == allColumns ? .cells : allColumns ? .rows : .columns
    }

    /// Deletes the rows; when they are all the rows, they are cleared instead, as Delete clears the whole table.
    public mutating func deleteRows(_ rr: ClosedRange<Int>) {
        guard rr.count < rowCount else { return clear(rows: rr, columns: 0...columns.count - 1) }
        for r in rr.reversed() { deleteRow(at: r) }
    }

    /// Deletes the columns; when they are all the columns, they are cleared instead.
    public mutating func deleteColumns(_ cr: ClosedRange<Int>) {
        guard cr.count < columns.count else { return clear(rows: 0...rowCount - 1, columns: cr) }
        for c in cr.reversed() { deleteColumn(at: c) }
    }

    /// Empties every cell in the rectangle.
    public mutating func clear(rows rr: ClosedRange<Int>, columns cr: ClosedRange<Int>) {
        for r in rr where r < rowCount { for c in cr where c < columns.count { setText("", row: r, column: c) } }
    }

    /// The `fill:` of the (merged) cell covering the slot, as written; nil when it has none.
    public func fill(row: Int, column: Int) -> String? {
        let a = anchor(row: row, column: column)
        return cell(row: a.row, column: a.column).cellArgs.first { $0.hasPrefix("fill:") }.map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
    }

    /// Sets (nil: removes) the `fill:` of every cell in the rectangle; a filled cell is written as `table.cell(fill: …)[…]`.
    public mutating func setFill(_ fill: String?, rows rr: ClosedRange<Int>, columns cr: ClosedRange<Int>) {
        var g = grid
        for r in rr where r < g.count { for c in cr where c < columns.count && !g[r][c].covered {
            g[r][c].cellArgs.removeAll { $0.hasPrefix("fill:") }
            if let fill { g[r][c].cellArgs.append("fill: \(fill)") }
        } }
        grid = g
    }

    /// Wraps the texts in `marker` (`*` bold, `_` italic), or unwraps them when every non-empty cell already is.
    public mutating func toggleEmphasis(_ marker: Character, rows rr: ClosedRange<Int>, columns cr: ClosedRange<Int>) {
        let slots = rr.flatMap { r in cr.map { (r, $0) } }.filter { $0.0 < rowCount && $0.1 < columns.count && !cell(row: $0.0, column: $0.1).covered }
        let texts = slots.map { cell(row: $0.0, column: $0.1).text }
        let all = texts.filter { !$0.isEmpty }.allSatisfy { TableCode.isWrapped($0, in: marker) }
        for ((r, c), t) in zip(slots, texts) where !t.isEmpty {
            setText(all ? TableCode.unwrapped(t, from: marker) : TableCode.isWrapped(t, in: marker) ? t : TableCode.wrapped(t, in: marker), row: r, column: c)
        }
    }

    /// Writes `values` with their top-left at (`row`, `column`), adding rows and columns as needed. Returns the rectangle written.
    @discardableResult
    public mutating func paste(_ values: [[String]], row: Int, column: Int) -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
        let height = values.count, width = values.map(\.count).max() ?? 0
        guard height > 0, width > 0, row >= 0, column >= 0 else { return nil }
        while columns.count < column + width { insertColumn(at: columns.count) }
        while rowCount < row + height { insertRow(at: rowCount) }
        for (i, line) in values.enumerated() { for (j, v) in line.enumerated() { setText(v, row: row + i, column: column + j) } }
        return (row...row + height - 1, column...column + width - 1)
    }

    // MARK: grid helpers (columns are rows of the transposed grid)

    static func transposed(_ g: [[Cell]]) -> [[Cell]] {
        guard let width = g.first?.count else { return [] }
        return (0..<width).map { c in g.map { var cell = $0[c]; swap(&cell.colspan, &cell.rowspan); cell.initialSpan.swapAt(0, 1); return cell } }
    }

    static func inserting(_ g: [[Cell]], at i: Int, width: Int) -> [[Cell]] {
        var g = g
        var line = Array(repeating: Cell(), count: width)
        if i < g.count {
            for r in 0..<i { for c in 0..<width where !g[r][c].covered && r + g[r][c].rowspan > i {
                g[r][c].rowspan += 1
                for cc in c..<c + g[r][c].colspan { line[cc] = .coveredCell }
            } }
        }
        g.insert(line, at: i)
        return g
    }

    static func removing(_ g: [[Cell]], at i: Int) -> [[Cell]] {
        var g = g
        for r in 0..<i { for c in g[r].indices where !g[r][c].covered && r + g[r][c].rowspan > i { g[r][c].rowspan -= 1 } }
        for c in g[i].indices where !g[i][c].covered && g[i][c].rowspan > 1 {
            var moved = g[i][c]
            moved.rowspan -= 1
            g[i + 1][c] = moved
        }
        g.remove(at: i)
        return g
    }

    /// Splits merged cells that reach over more than one line and touch `lines`.
    static func unmergeCrossing(_ g: inout [[Cell]], lines: ClosedRange<Int>) {
        for r in g.indices { for c in g[r].indices {
            let cell = g[r][c]
            if !cell.covered, cell.rowspan > 1, r <= lines.upperBound, r + cell.rowspan - 1 >= lines.lowerBound { unmerge(&g, r, c) }
        } }
    }
}

// MARK: styles

/// Ready-made looks: each writes `stroke:` / `fill:` (and Booktabs its rules) and replaces what was there.
public enum TableStyle: String, CaseIterable, Sendable, Identifiable {
    case plain, grid, headerLine, booktabs, striped
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: "Plain"
        case .grid: "Grid"
        case .headerLine: "Header Line"
        case .booktabs: "Booktabs"
        case .striped: "Striped"
        }
    }

    var arguments: [String] {
        switch self {
        case .plain: []
        case .grid: ["stroke: 0.5pt"]
        case .headerLine: ["stroke: (x, y) => if y == 0 { (bottom: 0.7pt) }"]
        case .booktabs: ["stroke: none"]
        case .striped: ["fill: (_, y) => if calc.odd(y) { luma(240) }"]
        }
    }
}

extension TableModel {
    private static func isStyle(_ s: Slot) -> Bool {
        guard case .verbatim(let v) = s else { return false }
        return v.hasPrefix("stroke:") || v.hasPrefix("fill:")
    }

    /// The preset the table looks like now; nil for anything else (hand-written strokes).
    public var style: TableStyle? {
        func written(_ m: TableModel) -> [String] { m.slots.filter(Self.isStyle).map { "\($0)" }.sorted() + m.rules.filter(\.isHorizontal).map(\.source).sorted() }
        return TableStyle.allCases.first { s in
            var m = self
            m.applyStyle(s)
            return written(m) == written(self)
        }
    }

    /// Replaces `stroke:`, `fill:` and the horizontal rules with the preset's.
    public mutating func applyStyle(_ style: TableStyle) {
        slots.removeAll(where: Self.isStyle)
        slots += style.arguments.map { .verbatim($0) }
        rules.removeAll(where: \.isHorizontal)
        guard style == .booktabs else { return }
        rules.append(Rule(source: "\(callee).hline(y: 0, stroke: 1pt)", row: 0))
        if header != nil { rules.append(Rule(source: "\(callee).hline(stroke: 0.5pt)", row: 1)) }
        rules.append(Rule(source: "\(callee).hline(stroke: 1pt)", row: rowCount))
    }
}

// MARK: parsing tables Rust declines

extension TableModel {
    /// The table around `caret`: its model, or why it can't be edited visually. Nil if the caret is in no table.
    /// Merged cells (`table.cell(colspan:, rowspan:)`) and lines (`table.hline`, `table.vline`) are read here: they stand in as
    /// marker cells for the Rust parse, which then checks everything else as usual.
    /// `lookup` on a string of its own (previews, tests).
    public static func lookup(in text: String, at caret: Int) -> TableLookup? { lookup(in: text, syntax: SyntaxMirror(text), at: caret) }

    static func lookup(in text: String, syntax: SyntaxMirror, at caret: Int) -> TableLookup? {
        guard let raw = syntax.table(at: caret) else { return nil }
        var model: TableModel
        if var reason = raw.unsupported {
            guard reason.contains("places cells by hand") || reason.contains(" lines (") || reason.contains("don't fill whole rows"),
                  let m = spanned(raw, in: text, reason: &reason) else { return .unsupported(reason: reason) }
            model = m
        } else {
            var reason = ""
            // `table.cell(fill: …)` cells are read as cells (with their args), not as code.
            let cellCalls = ((raw.header ?? []) + raw.cells).contains { $0.source.hasPrefix("\(raw.callee).cell(") }
            guard let m = (cellCalls ? spanned(raw, in: text, reason: &reason) : nil) ?? TableModel(raw) else {
                return .unsupported(reason: "the cells don't fit the columns")
            }
            model = m
        }
        return .table(model)
    }

    private enum Positional { case plain, special(Special), placed, invalid }

    private static func classify(_ s: String, callee: String) -> Positional {
        if s.hasPrefix("\(callee).hline(") || s.hasPrefix("\(callee).vline(") { return .special(.rule(s)) }
        let prefix = "\(callee).cell"
        guard s.hasPrefix(prefix + "(") else { return .plain }
        let synthetic = "#table" + s.dropFirst(prefix.count)
        let ns = synthetic as NSString
        guard let call = TypstCalls.calls(named: ["table"], in: synthetic).first, call.range.location == 1 else { return .invalid }
        var colspan = 1, rowspan = 1, spans = false, body: String?
        var args: [String] = []
        for a in call.args {
            let value = ns.substring(with: a.value)
            switch a.name {
            case "colspan", "rowspan":
                guard let n = Int(value), n >= 1 else { return .invalid }
                if a.name == "colspan" { colspan = n } else { rowspan = n }
                spans = true
            case "x", "y": return .placed
            case let name?: args.append("\(name): \(value)")
            case nil:
                guard body == nil, value.hasPrefix("["), value.hasSuffix("]") else { return .invalid }
                body = String(value.dropFirst().dropLast())
            }
        }
        let rest = ns.substring(from: NSMaxRange(call.range)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty {
            guard body == nil, rest.hasPrefix("["), rest.hasSuffix("]") else { return .invalid }
            body = String(rest.dropFirst().dropLast())
        }
        guard spans || !args.isEmpty else { return .plain }
        guard let body else { return .invalid }
        return .special(.cell(Cell(source: s, text: body, colspan: colspan, rowspan: rowspan, args: args)))
    }

    /// Number of columns `columns:` asks for; nil when it is not a whole number or a plain array.
    private static func columnCount(_ value: String) -> Int? {
        if let n = Int(value) { return max(1, n) }
        guard value.hasPrefix("("), let call = TypstCalls.calls(named: ["table"], in: "#table" + value).first, call.range.location == 1 else { return nil }
        return max(1, call.args.count)
    }

    /// Works on the call alone (as `#table(...)`), so a long document is not tokenized again.
    /// `reason` becomes what the user is told when the result is nil for a reason the Rust parse can't name.
    private static func spanned(_ raw: RawTable, in document: String, reason: inout String) -> TableModel? {
        let text = "#" + (document as NSString).substring(with: raw.range)
        let ns = text as NSString
        let callee = raw.callee
        guard let call = TypstCalls.calls(named: [callee], in: text).first, call.range == NSRange(location: 1, length: raw.range.length) else { return nil }
        var specials: [Special] = []
        var edits: [(range: NSRange, text: String)] = []
        var columns = 1, bodyCells = 0, hasHeader = false
        let mark = "[\(specialMark)]", pad = "[\(padMark)]"
        let placedReason = "\(callee).cell(x:, y:) puts cells at fixed positions, which can't be edited visually"

        /// Markers before the `)` at `close`, keeping the comma style.
        func padding(_ n: Int, before close: Int) -> (NSRange, String) {
            var i = close - 1
            while i > 0, [0x20, 0x09, 0x0A, 0x0D].contains(ns.character(at: i)) { i -= 1 }
            let pads = Array(repeating: pad, count: n)
            return ns.character(at: i) == 0x2C || ns.character(at: i) == 0x28
                ? (NSRange(location: close, length: 0), pads.map { $0 + ", " }.joined())
                : (NSRange(location: close, length: 0), pads.map { ", " + $0 }.joined())
        }

        if let a = call.arg("columns") { guard let n = columnCount(ns.substring(with: a.value)) else { return nil }; columns = n }
        for a in call.args {
            if a.name != nil { continue }
            let s = ns.substring(with: a.range)
            let headerPrefix = "\(callee).header"
            if s.hasPrefix(headerPrefix + "("), !hasHeader {
                hasHeader = true
                let synthetic = "#table" + s.dropFirst(headerPrefix.count)
                let sns = synthetic as NSString
                guard let h = TypstCalls.calls(named: ["table"], in: synthetic).first, h.range.location == 1 else { return nil }
                let shift = a.range.location + headerPrefix.utf16.count - 6     // synthetic offset → text offset
                for ha in h.args where ha.name == nil {
                    switch classify(sns.substring(with: ha.range), callee: callee) {
                    case .plain: break
                    case .special(.cell(let c)):
                        specials.append(.cell(c)); edits.append((NSRange(location: ha.range.location + shift, length: ha.range.length), mark))
                    case .placed: reason = placedReason; return nil
                    case .special(.rule), .invalid: return nil
                    }
                }
                // Rust wants one slot per column: a merged cell is one slot.
                let headerSlots = h.args.filter { $0.name == nil }.count
                if headerSlots < columns { edits.append(padding(columns - headerSlots, before: h.close + shift)) }
                continue
            }
            switch classify(s, callee: callee) {
            case .plain: bodyCells += 1
            case .special(let sp):
                if case .cell = sp { bodyCells += 1 }
                specials.append(sp)
                edits.append((a.range, mark))
            case .placed: reason = placedReason; return nil
            case .invalid: return nil
            }
        }
        // Rust wants whole rows of `columns` slots: rules count as one, merged cells as one.
        let lineMarks = specials.filter { if case .rule = $0 { return true }; return false }.count
        let total = bodyCells + lineMarks
        if total % columns != 0 { edits.append(padding(columns - total % columns, before: call.close)) }

        var masked = ns
        for e in edits.sorted(by: { $0.range.location > $1.range.location }) { masked = masked.replacingCharacters(in: e.range, with: e.text) as NSString }
        guard let raw2 = SyntaxMirror(masked as String).table(at: 2), raw2.unsupported == nil else { return nil }
        guard let model = TableModel(raw2, specials: specials, range: raw.range) else {
            reason = "a merged cell or a line doesn't fit the table (it leaves it, overlaps another cell, or a vertical line sits mid-row)"
            return nil
        }
        return model
    }

    /// Fills `figure` when the table is the body of a `figure(...)`. Tokenizes the whole text: for the editor, not caret checks.
    public mutating func attachFigure(in text: String) {
        guard let f = FigureInfo.at(range.location + 1, in: text),
              let body = f.call.args.first(where: { $0.name == nil }),
              NSLocationInRange(range.location, body.value) || body.value.location == range.location - 1,
              NSMaxRange(range) <= NSMaxRange(body.value) else { return }
        figure = Figure(caption: f.value(.caption), label: f.value(.label), placement: f.value(.placement))
        figureBaseline = figure
    }
}

/// Pure code generation for tables: insert, and write an edited model back.
public enum TableCode {
    /// `rows` counts the header row. Every cell is an empty stop, so the first cell is selected.
    public static func insert(rows: Int, columns: Int, header: Bool, figure: Bool) -> Snippet {
        let rows = max(rows, 1), columns = max(columns, 1)
        let line = Array(repeating: "[${}]", count: columns).joined(separator: ", ")
        var body = ["columns: \(columns),"]
        if header { body.append("table.header(\(line)),") }
        body += Array(repeating: "\(line),", count: rows - (header ? 1 : 0))
        let apply = figure
            ? "#figure(\n  table(\n" + body.map { "    \($0)\n" }.joined() + "  ),\n  caption: [${}],\n)"
            : "#table(\n" + body.map { "  \($0)\n" }.joined() + ")"
        return Snippet.parse(apply)
    }

    /// The text to put over `range` so the snippet sits on its own lines, and the selection that follows.
    public static func place(_ snippet: Snippet, in text: String, replacing range: NSRange) -> (replacement: String, selection: NSRange) {
        let p = placement(of: snippet, in: text, replacing: range)
        return (p.replacement, p.selection)
    }

    /// `place`, also returning the re-indented snippet and where it starts in the new text (for a `SnippetSession`).
    public static func placement(of snippet: Snippet, in text: String, replacing range: NSRange) -> (replacement: String, selection: NSRange, snippet: Snippet, at: Int) {
        let ns = text as NSString
        func isBreak(_ u: unichar) -> Bool { u == 10 || u == 13 }
        let lineStart = range.location == 0 || isBreak(ns.character(at: range.location - 1))
        let lineEnd = NSMaxRange(range) >= ns.length || isBreak(ns.character(at: NSMaxRange(range)))
        let before = lineStart ? "" : "\n"
        // The lines after the first sit at the indentation of the line the snippet starts on.
        let snippet = snippet.indentedKeepingGroups(by: Indent.lineIndent(in: text, before: range.location))
        let at = range.location + before.utf16.count
        return (before + snippet.text + (lineEnd ? "" : "\n"), snippet.selection(insertedAt: at), snippet, at)
    }

    /// Markup for `text` inside `[...]`: markup-level unbalanced brackets and a trailing backslash are escaped so the block still closes.
    /// Brackets in raw, strings, comments and math never end the block (math checked against the engine) and stay as typed.
    public static func escape(_ text: String) -> String {
        let mirror = SyntaxMirror(text)
        var units = Array(text.utf16)
        // Code-level brackets are the balanced `[...]` of a content block, so modes 0 and 1 both count.
        func isMarkup(_ at: Int) -> Bool { mirror.mode(at: at + 1).rawValue <= SyntaxMode.code.rawValue }
        var open: [Int] = [], stray: [Int] = []
        var i = 0
        while i < units.count {
            switch units[i] {
            case 0x5C where isMarkup(i):
                if i == units.count - 1 { units.append(0x5C) }
                i += 1                                          // the escaped character is not a bracket
            case 0x5B where isMarkup(i): open.append(i)
            case 0x5D where isMarkup(i): if open.popLast() == nil { stray.append(i) }
            default: break
            }
            i += 1
        }
        for at in (stray + open).sorted(by: >) { units.insert(0x5C, at: at) }
        return String(decoding: units, as: UTF16.self)
    }

    // MARK: emphasis

    public static func isWrapped(_ text: String, in marker: Character) -> Bool {
        marker == "`" ? rawContent(text) != nil : text.count >= 2 && text.first == marker && text.last == marker
    }

    public static func wrapped(_ text: String, in marker: Character) -> String {
        guard marker == "`" else { return "\(marker)\(text)\(marker)" }
        let longest = text.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
        guard longest > 0 else { return "`\(text)`" }
        // Two backticks are an empty raw; the leading space stops a language tag, Typst trims the trailing one only after a backtick.
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return fence + " " + text + (text.last(where: { $0 != " " }) == "`" ? " " : "") + fence
    }

    public static func unwrapped(_ text: String, from marker: Character) -> String {
        if marker == "`" { return rawContent(text) ?? text }
        return isWrapped(text, in: marker) ? String(text.dropFirst().dropLast()) : text
    }

    /// The text of the raw element `text` is as a whole, as Typst reads it; nil when it is not one raw element.
    static func rawContent(_ text: String) -> String? {
        let fence = text.prefix { $0 == "`" }.count
        guard fence == 1 || fence >= 3 else { return nil }
        let rest = text.dropFirst(fence)
        // The raw ends at the first run of `fence` backticks; it must be the end of the text.
        var run = 0
        for i in rest.indices {
            run = rest[i] == "`" ? run + 1 : 0
            guard run == fence else { continue }
            guard rest.index(after: i) == rest.endIndex else { return nil }
            var inner = rest.dropLast(fence)
            guard fence >= 3 else { return String(inner) }
            if inner.first == " " { inner = inner.dropFirst() }
            if inner.last == " ", inner.last(where: { $0 != " " }) == "`" { inner = inner.dropLast() }
            return String(inner)
        }
        return nil
    }

    // MARK: writing

    static func source(_ c: TableModel.Cell, callee: String) -> String {
        if c.isUnchanged { return c.original! }
        guard c.isMerged || !c.cellArgs.isEmpty else { return "[\(escape(c.text))]" }
        let args = (c.colspan > 1 ? ["colspan: \(c.colspan)"] : []) + (c.rowspan > 1 ? ["rowspan: \(c.rowspan)"] : []) + c.cellArgs
        return "\(callee).cell(\(args.joined(separator: ", ")))[\(escape(c.text))]"
    }

    /// One table row per line, one `unit` of indent, `indent` in front of every line after the first.
    public static func render(_ m: TableModel, indent: String = "", unit: String = "  ") -> String {
        func columnsArg() -> String? {
            let sizes = m.columns.map(\.size)
            if let o = m.columnsOriginal, sizes == m.columnsBaseline { return "columns: \(o)" }
            if sizes.contains(where: { $0 != nil }) {
                return "columns: (\(sizes.map { $0 ?? "auto" }.joined(separator: ", "))\(sizes.count == 1 ? "," : ""))"
            }
            return m.columnsOriginal == nil && m.columns.count == 1 ? nil : "columns: \(m.columns.count)"
        }
        func alignArg() -> String? {
            let aligns = m.columns.map(\.align)
            if !m.alignEditable || aligns == m.alignBaseline { return m.alignOriginal.map { "align: \($0)" } }
            if aligns.allSatisfy({ $0 == nil }) { return nil }
            if let first = aligns[0], aligns.allSatisfy({ $0 == first }) { return "align: \(first)" }
            return "align: (\(aligns.map { $0 ?? "auto" }.joined(separator: ", "))\(aligns.count == 1 ? "," : ""))"
        }
        func cells(_ row: [TableModel.Cell]) -> [String] { row.filter { !$0.covered }.map { source($0, callee: m.callee) } }
        var lines: [String] = []
        for slot in m.slots {
            switch slot {
            case .columns: lines += columnsArg().map { [$0] } ?? []
            case .align: lines += alignArg().map { [$0] } ?? []
            case .verbatim(let s): lines.append(s)
            }
        }
        // Absent args that the edit needs come first, `columns` before `align`.
        lines.insert(contentsOf: [m.slots.contains(.columns) ? nil : columnsArg(), m.slots.contains(.align) ? nil : alignArg()].compactMap { $0 }, at: 0)
        lines = lines.map { $0 + "," }
        if let h = m.header {
            lines.append("\(m.callee).header(" + (m.headerArgs + cells(h)).joined(separator: ", ") + "),")
        }
        var body = m.rows.map { $0.filter { !$0.covered } }
        // Typst leaves the slots after the last cell empty on its own, so holes that are still empty stay unwritten.
        trim: for k in body.indices.reversed() {
            while let last = body[k].last {
                guard last.hole, last.text.isEmpty, !last.isMerged else { break trim }
                body[k].removeLast()
            }
        }
        let first = m.headerRows
        for (k, row) in body.enumerated() {
            let r = k + first
            lines += m.rules.filter { k == 0 ? $0.row <= r : $0.row == r }.map { $0.source + "," }
            let written = row.map { source($0, callee: m.callee) }
            if !written.isEmpty { lines.append(written.joined(separator: ", ") + ",") }
        }
        lines += m.rules.filter { m.rows.isEmpty || $0.row >= m.rowCount }.map { $0.source + "," }
        return "\(m.callee)(\n" + lines.map { "\(indent)\(unit)\($0)\n" }.joined() + "\(indent))"
    }

    /// The replacement for the call's range, nil when the model is unmodified. Lines after the first keep the call's indentation
    /// (under the item text for a list item). Changed figure fields widen it to the whole figure and its label: still one edit.
    public static func edit(_ m: TableModel, in text: String, settings: IndentSettings = .standard) -> (range: NSRange, replacement: String)? {
        guard m.isModified else { return nil }
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: m.range.location, length: 0))
        let lead = Indent.leadingBlanks(ns, from: line.location, to: NSMaxRange(line))
        var indent = lead
        // A call that follows a list marker (`- #table(`) continues under the item's text.
        let head = ns.substring(with: NSRange(location: line.location + lead.utf16.count, length: max(0, m.range.location - line.location - lead.utf16.count)))
        if let marker = head.prefixMatch(of: /(?:[-+\/]|\d+\.)\s+/) { indent += String(repeating: " ", count: marker.output.utf16.count) }
        let table = render(m, indent: indent, unit: settings.unit(for: lead))
        guard let figure = m.figure, figure != m.figureBaseline,
              let start = FigureInfo.at(m.range.location + 1, in: text)?.call.range.location else { return (m.range, table) }
        var t = ns.replacingCharacters(in: m.range, with: table)
        for (field, value) in [(FigureInfo.Field.caption, figure.caption), (.placement, figure.placement), (.label, figure.label)] {
            guard let f = FigureInfo.at(start + 1, in: t), f.call.range.location == start, f.value(field) != value,
                  let r = f.edit(field, to: value) else { continue }
            t = (t as NSString).replacingCharacters(in: r.range, with: r.text)
        }
        // Everything outside [start, end) is unchanged, so one replacement covers both edits.
        let new = t as NSString
        var suffix = 0
        while suffix < ns.length - start, suffix < new.length - start,
              ns.character(at: ns.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        suffix = min(suffix, ns.length - NSMaxRange(m.range))      // never cut into the table itself
        let range = NSRange(location: start, length: ns.length - suffix - start)
        return (range, new.substring(with: NSRange(location: start, length: new.length - suffix - start)))
    }
}

extension Buffer {
    /// The table around `caret`: its model, or why it can't be edited visually. Nil if the caret is in no table.
    public func table(at caret: Int) -> TableLookup? {
        TableModel.lookup(in: storage.string, syntax: syntax, at: caret)
    }
}
