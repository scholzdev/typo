import SwiftUI
import TypoKit
import TypstEngine

/// One window's table editing: what the menus, the toolbar button and the sheet share.
@MainActor @Observable final class TableEditing {
    /// The caret is in a `table(...)` / `grid(...)` call (editable or not).
    var caretInTable = false
    var insertPresented = false
    var editing: TableModel? {
        didSet { if editing == nil { previewer = nil } }
    }
    var unsupportedReason: String?
    /// What the open sheet completes from; also says which `#names` need an import when the table is applied.
    @ObservationIgnored var completion: CellCompletion?
    @ObservationIgnored weak var editor: EditorView.Coordinator?
    /// The open sheet's cell renderer (a world of its own); dropped when the sheet closes.
    @ObservationIgnored var previewer: TablePreviewer?

    func beginEdit() {
        switch editor?.tableAtCaret() {
        case .table(var model):
            if let text = editor?.buffer?.storage.string { model.attachFigure(in: text) }
            editing = model
        case .unsupported(let reason): unsupportedReason = reason
        case nil: break
        }
    }

    func apply(_ model: TableModel) {
        editing = nil
        editor?.apply(model)
        // Names picked from other files get their import, in a second undo step after the table's.
        guard let completion, let buffer = editor?.buffer else { return }
        let cells = (model.header ?? []).map(\.text) + model.rows.flatMap { $0.map(\.text) }
        let lines = completion.missingImports(cells: cells, file: buffer.path)
        guard !lines.isEmpty else { return }
        let at = CellCompletion.importInsertionPoint(in: buffer.storage.string)
        buffer.apply([Replacement(range: NSRange(location: at, length: 0), text: lines)], actionName: "Add Import")
    }

    func insert(rows: Int, columns: Int, header: Bool, figure: Bool) {
        insertPresented = false
        editor?.insert(TableCode.insert(rows: rows, columns: columns, header: header, figure: figure))
    }
}

/// Pages-style grid picker: hover selects, click inserts.
struct TableInsertPopover: View {
    static let maxColumns = 10, maxRows = 8
    let insert: (_ rows: Int, _ columns: Int, _ header: Bool, _ figure: Bool) -> Void
    @State private var hovered: (row: Int, column: Int)?
    @State private var header = true
    @State private var figure = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                ForEach(1...Self.maxRows, id: \.self) { r in
                    GridRow {
                        ForEach(1...Self.maxColumns, id: \.self) { c in
                            let selected = hovered.map { r <= $0.row && c <= $0.column } ?? false
                            RoundedRectangle(cornerRadius: 3)
                                .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                                .onHover { inside in if inside { hovered = (r, c) } }
                                .onTapGesture { insert(r, c, header, figure) }
                        }
                    }
                }
            }
            .onHover { if !$0 { hovered = nil } }
            Text(hovered.map { "\($0.column) columns × \($0.row) rows" } ?? "Choose a size")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Toggle("Header row", isOn: $header)
            Toggle("As figure with caption", isOn: $figure)
        }
        .padding(16)
    }
}

