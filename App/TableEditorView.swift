import SwiftUI
import TypoKit
import TypstEngine

/// Spreadsheet editor for one table: a formatting bar, a formula bar over the grid (cells show as Typst renders them), a
/// live typeset of the whole table beside it, and the figure's fields. Done hands the edited model back (one edit in the
/// document); Cancel discards it.
struct TableEditorView: View {
    @State private var state: TableSheetState
    let done: (TableModel) -> Void
    let cancel: () -> Void
    let completion: () async -> CellCompletion
    /// Engine-backed completion for a cell; nil completes from `completions` alone.
    var complete: ((_ model: TableModel, _ row: Int, _ column: Int, _ text: String, _ caret: Int, _ request: CellCompletion.Request, _ fallback: CellCompletion) async -> [CompletionItem])?
    /// Each cell's markup as the document renders it, in a Typst colour at a text size in points; nil shows the markup.
    var renderCells: ((_ model: TableModel, _ fill: String, _ size: Double) async -> [String: CGImage])?
    /// The table as the document would show it with this model, at `previewPixelsPerPoint`; nil leaves the typeset pane out.
    var preview: ((TableModel) async -> CGImage?)?
    /// Enough pixels that the typeset table stays sharp zoomed in on a Retina screen.
    static let previewPixelsPerPoint: Float = 4
    @State private var completions = CellCompletion()
    @State private var confirmDiscard = false
    @State private var showsAssist = false
    @FocusState private var figureField: WritableKeyPath<TableModel.Figure, String>?
    @FocusState private var formulaFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("TableEditorLayout") private var layout = Layout.split
    @AppStorage("TableEditorShowsRaw") private var showsRaw = false
    @State private var previewImage: CGImage?
    @State private var rendering = false

    enum Layout: String { case editor, split, preview }

    init(model: TableModel, done: @escaping (TableModel) -> Void, cancel: @escaping () -> Void,
         completion: @escaping () async -> CellCompletion = { CellCompletion() },
         complete: ((TableModel, Int, Int, String, Int, CellCompletion.Request, CellCompletion) async -> [CompletionItem])? = nil,
         renderCells: ((TableModel, String, Double) async -> [String: CGImage])? = nil,
         preview: ((TableModel) async -> CGImage?)? = nil) {
        _state = State(initialValue: TableSheetState(model: model))
        self.done = done
        self.cancel = cancel
        self.completion = completion
        self.complete = complete
        self.renderCells = renderCells
        self.preview = preview
    }

    private var model: TableModel { state.model }
    private var shownLayout: Layout { preview == nil ? .editor : layout }

    var body: some View {
        VStack(spacing: 0) {
            // Titles and the layout names go to icons when the sheet is too narrow for them.
            ViewThatFits(in: .horizontal) { formatBar(compact: false); formatBar(compact: true) }
                .padding(.horizontal, 12)
                .frame(height: 48)
            Divider()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if shownLayout != .preview {
                        editorPane.frame(width: shownLayout == .split ? geo.size.width * 0.55 : geo.size.width)
                    }
                    if shownLayout == .split { Divider() }
                    if shownLayout != .editor {
                        TableTypesetPane(model: model, image: previewImage, pixelsPerPoint: CGFloat(Self.previewPixelsPerPoint), rendering: rendering)
                    }
                }
            }
            if model.figure != nil {
                Divider()
                figureFields
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            Divider()
            statusRow.padding(12)
        }
        .frame(minWidth: TableSheetWindow.minSize.width, idealWidth: 1080, maxWidth: .infinity, minHeight: 420, idealHeight: 660, maxHeight: .infinity)
        .task { completions = await completion() }
        .task(id: RenderKey(model: model, dark: colorScheme == .dark)) { await render() }
        .task(id: shownLayout != .editor ? model : nil) { await renderPreview() }
        .onChange(of: colorScheme) { state.cellImages = [:] }       // drawn in the other appearance's colour
        .onChange(of: showsRaw, initial: true) { state.showsRaw = showsRaw }
        .confirmationDialog("Discard your changes to this table?", isPresented: $confirmDiscard) {
            Button("Discard Changes", role: .destructive, action: cancel)
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private func requestCancel() {
        state.commitEdit()
        if model.isModified { confirmDiscard = true } else { cancel() }
    }

    // MARK: formatting bar

    private var selectedSpec: ColumnSpec {
        model.columns.indices.contains(state.selectedColumns.lowerBound) ? model.columns[state.selectedColumns.lowerBound] : ColumnSpec()
    }

    private func formatBar(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button("Header", systemImage: "tablecells") { state.toggleHeader() }
                .labelStyle(TitledLabelStyle(titled: !compact))
                .modifier(BarToggle(on: model.header != nil))
                .help("The first row repeats on every page as the table's header")

            Picker("Alignment", selection: Binding(get: { selectedSpec.horizontal ?? "" }, set: { state.setHorizontal($0.isEmpty ? nil : $0) })) {
                Image(systemName: "text.alignleft").tag("left").help("Align Left")
                Image(systemName: "text.aligncenter").tag("center").help("Align Center")
                Image(systemName: "text.alignright").tag("right").help("Align Right")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(!model.alignEditable)

            Menu {
                Picker("Vertical Alignment", selection: Binding(get: { selectedSpec.vertical ?? "" }, set: { state.setVertical($0.isEmpty ? nil : $0) })) {
                    Text("Default").tag("")
                    Label("Top", systemImage: "arrow.up.to.line").tag("top")
                    Label("Middle", systemImage: "arrow.up.and.down").tag("horizon")
                    Label("Bottom", systemImage: "arrow.down.to.line").tag("bottom")
                }
                .pickerStyle(.inline)
            } label: {
                Label("Vertical Alignment", systemImage: "align.vertical.center")
            }
            .fixedSize()
            .disabled(!model.alignEditable)
            .help("Vertical alignment of the selected columns")

            ControlGroup {
                Button("Bold", systemImage: "bold") { state.toggleEmphasis("*") }.help("Bold (⌘B): wraps the cells in *…*")
                Button("Italic", systemImage: "italic") { state.toggleEmphasis("_") }.help("Italic (⌘I): wraps the cells in _…_")
                Button("Code", systemImage: "chevron.left.forwardslash.chevron.right") { state.toggleEmphasis("`") }
                    .help("Code: wraps the cells in `…` (raw text)")
            }
            .fixedSize()

            if state.canUnmerge {
                Button("Unmerge", systemImage: "rectangle.split.2x1") { state.unmergeSelection() }
            } else {
                Button("Merge", systemImage: "rectangle.split.2x1.slash") { state.mergeSelection() }
                    .disabled(!state.canMerge)
                    .help("Merge the selected cells into one (colspan / rowspan)")
            }

            fillMenu

            Menu {
                ForEach(TableStyle.allCases) { style in
                    Toggle(style.title, isOn: Binding(get: { model.style == style }, set: { _ in state.applyStyle(style) }))
                }
            } label: {
                Label(model.style?.title ?? "Custom Style", systemImage: "line.3.horizontal")
            }
            .labelStyle(TitledLabelStyle(titled: !compact))
            .fixedSize()
            .help("Strokes and fills; a custom style stays as written until you pick one")

            Menu {
                Button("Row Above", systemImage: "arrow.up.to.line") { state.insertRows(above: true) }
                    .disabled(state.selection.rows.lowerBound < model.headerRows)
                Button("Row Below", systemImage: "arrow.down.to.line") { state.insertRows(above: false) }
                Button("Column Left", systemImage: "arrow.left.to.line") { state.insertColumns(left: true) }
                Button("Column Right", systemImage: "arrow.right.to.line") { state.insertColumns(left: false) }
            } label: {
                Label("Insert", systemImage: "plus")
            }
            .fixedSize()

            Button("Assist", systemImage: "sparkles") { state.commitEdit(); showsAssist.toggle() }
                .labelStyle(TitledLabelStyle(titled: !compact))
                .tint(.purple)
                .help("Change the table with a model: sort, add totals, translate …")
                .popover(isPresented: $showsAssist, arrowEdge: .bottom) { TableAssistPopover(state: state) }

            Spacer(minLength: 0)

            if preview != nil {
                // The grid goes when the layout drops it: write its open cell first.
                Picker("Layout", selection: Binding(get: { layout }, set: { state.commitEdit(); layout = $0 })) {
                    Label("Editor", systemImage: "tablecells").tag(Layout.editor)
                    Label("Split", systemImage: "rectangle.split.2x1").tag(Layout.split)
                    Label("Preview", systemImage: "doc.richtext").tag(Layout.preview)
                }
                .labelStyle(compact ? AnyLabelStyle.iconOnly : .titleOnly)
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("The grid, the typeset table, or both side by side")
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.regular)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .menuStyle(.button)
    }

    /// Light fills that keep black text readable; the Typst source is what the cell gets.
    private static let fills: [(name: String, typst: String, color: NSColor)] = [
        ("Grey", "luma(235)", NSColor(white: 0.92, alpha: 1)),
        ("Red", "red.lighten(70%)", NSColor(srgbRed: 1, green: 0.78, blue: 0.76, alpha: 1)),
        ("Orange", "orange.lighten(70%)", NSColor(srgbRed: 1, green: 0.86, blue: 0.73, alpha: 1)),
        ("Yellow", "yellow.lighten(70%)", NSColor(srgbRed: 1, green: 0.96, blue: 0.70, alpha: 1)),
        ("Green", "green.lighten(70%)", NSColor(srgbRed: 0.78, green: 0.94, blue: 0.80, alpha: 1)),
        ("Blue", "blue.lighten(70%)", NSColor(srgbRed: 0.70, green: 0.84, blue: 0.96, alpha: 1)),
        ("Purple", "purple.lighten(70%)", NSColor(srgbRed: 0.91, green: 0.73, blue: 0.94, alpha: 1)),
    ]

    private var fillMenu: some View {
        let current = model.fill(row: state.cursor.row, column: state.cursor.column)
        return Menu {
            Button("No Fill", systemImage: "circle.slash") { state.setFill(nil) }
            Divider()
            ForEach(Self.fills, id: \.typst) { f in
                Toggle(isOn: Binding(get: { current == f.typst }, set: { _ in state.setFill(f.typst) })) {
                    Label { Text(f.name) } icon: { Image(nsImage: Self.swatch(f.color)) }
                }
            }
        } label: {
            if let c = Self.fills.first(where: { $0.typst == current }) {
                Label { Text("Cell Fill") } icon: { Image(nsImage: Self.swatch(c.color)) }
            } else {
                Label("Cell Fill", systemImage: "paintpalette")
            }
        }
        .fixedSize()
        .help("Fill colour of the selected cells (table.cell(fill: …))")
    }

    /// Menus draw SF Symbols as templates, so a colour swatch is a non-template image.
    private static func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { r in
            let path = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            color.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: grid pane

    private var address: String {
        TableGridView.columnName(state.cursor.column) + "·" + TableGridView.rowName(state.cursor.row, headerRows: model.headerRows)
    }

    private var formulaBar: some View {
        HStack(spacing: 8) {
            Text(address)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            Text("Typst").font(.caption).foregroundStyle(.secondary)
            TextField("Cell markup", text: Binding(get: { state.activeText }, set: { state.activeText = $0 }), prompt: Text("empty"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($formulaFocused)
                .onSubmit { formulaFocused = false }
                .onChange(of: formulaFocused) { state.endCoalescing() }
            Toggle("Raw", isOn: $showsRaw)
                .toggleStyle(.checkbox)
                .help("Show each cell's markup in the grid instead of how Typst renders it")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var editorPane: some View {
        VStack(spacing: 8) {
            formulaBar
            HStack(spacing: 8) {
                TableGrid(state: state, completions: completions, complete: { row, column, text, caret, request in
                    guard let complete else { return completions.items(for: request) }
                    return await complete(state.model, row, column, text, caret, request, completions)
                }, cancel: requestCancel)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
                AddTarget(title: "Add Column", vertical: true, action: state.appendColumn)
                    .frame(width: 30)
            }
            AddTarget(title: "Add row", vertical: false, action: state.appendRow)
                .frame(height: 30)
                .padding(.trailing, 38)
            HStack(spacing: 4) {
                Text("Tip: Press")
                Keycap("Tab")
                Text("or")
                Keycap("Enter")
                Text("to navigate & add rows")
                Spacer(minLength: 8)
                Text("Click column icons to cycle alignment")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
    }

    // MARK: figure

    private func figure(_ key: WritableKeyPath<TableModel.Figure, String>, typing: Bool = false) -> Binding<String> {
        Binding(get: { model.figure?[keyPath: key] ?? "" }, set: { v in state.setFigure(typing: typing) { $0[keyPath: key] = v } })
    }

    private var figureFields: some View {
        HStack(spacing: 12) {
            Text("Caption").foregroundStyle(.secondary)
            TextField("Caption", text: figure(\.caption, typing: true), prompt: Text("Caption"))
                .labelsHidden()
                .focused($figureField, equals: \.caption)
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.secondary)
                    .help("The figure's label, written as <tab:name>")
                TextField("Label", text: figure(\.label, typing: true), prompt: Text("tab:name"))
                    .labelsHidden()
                    .focused($figureField, equals: \.label)
                    .frame(width: 130)
                if let label = model.figure?.label, !label.isEmpty, !LabelIndex.isValidName(label) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Not a valid label name: it won't be written")
                }
            }
            Picker("Placement", selection: figure(\.placement)) {
                Text("In Flow").tag("")
                Text("Auto").tag("auto")
                Text("Top").tag("top")
                Text("Bottom").tag("bottom")
            }
            .fixedSize()
            Picker("Width", selection: Binding(get: { state.tableWidth }, set: { state.setTableWidth($0) })) {
                Text("Auto").tag(TableSheetState.TableWidth.auto)
                Text("Full").tag(TableSheetState.TableWidth.full)
                if state.tableWidth == .custom { Text("Custom").tag(TableSheetState.TableWidth.custom) }
            }
            .fixedSize()
            .help("Auto: columns fit their content. Full: every column 1fr, so the table spans the text width.")
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: figureField) { state.endCoalescing() }
        .onSubmit { state.endCoalescing() }
    }

    // MARK: status

    private var widthName: String {
        switch state.tableWidth { case .auto: "Auto"; case .full: "Full"; case .custom: "Custom" }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            Chip("\(model.columns.count) cols × \(model.rowCount) rows")
            if model.header != nil { Chip("Header row") }
            Chip("Width: \(widthName)")
            let s = state.selection
            if s.rows.count * s.columns.count > 1 && !state.isSingleCell { Chip("\(s.columns.count) × \(s.rows.count) selected") }
            Spacer()
            Button("Cancel", action: requestCancel).buttonStyle(.bordered)
            Button { state.commitEdit(); done(state.model) } label: {
                HStack(spacing: 6) {
                    Text("Done")
                    Text(verbatim: "⌘↩")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityHidden(true)
                }
            }
            // The Assist popover's Send uses ⌘↩ too; it must not also end the sheet.
            .keyboardShortcut(showsAssist ? nil : KeyboardShortcut(.return, modifiers: .command))
            .buttonStyle(.borderedProminent)
        }
        .monospacedDigit()
    }

    // MARK: typeset

    /// Debounced: typing restarts the wait, so only a pause compiles.
    private func renderPreview() async {
        guard shownLayout != .editor, let preview else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        rendering = true
        defer { rendering = false }
        let rendered = await preview(state.model)
        if !Task.isCancelled { previewImage = rendered }
    }

    // MARK: rendered cells

    private struct RenderKey: Equatable { let model: TableModel; let dark: Bool }

    /// Debounced: typing restarts the wait, so only a pause compiles. A failed compile keeps the last images; they are
    /// keyed by markup, so a changed cell shows its markup until it renders.
    private func render() async {
        guard let renderCells else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let images = await renderCells(state.model, colorScheme == .dark ? "rgb(\"#ffffffd9\")" : "rgb(\"#000000d9\")", NSFont.systemFontSize)
        guard !Task.isCancelled, !images.isEmpty else { return }
        state.cellImages = images.mapValues { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / 2, height: CGFloat($0.height) / 2)) }
    }
}

#Preview("Table editor") {
    let source = """
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
    if case .table(let model)? = TableModel.lookup(in: source, at: (source as NSString).range(of: "Apple").location) {
        TableEditorView(model: model, done: { _ in }, cancel: {})
            .frame(width: 1080, height: 660)
    } else {
        Text("The sample table did not parse")
    }
}

/// Title and icon, or the icon alone.
private struct TitledLabelStyle: LabelStyle {
    let titled: Bool
    func makeBody(configuration: Configuration) -> some View {
        if titled { Label(configuration) } else { configuration.icon }
    }
}

/// `.iconOnly` or `.titleOnly`, chosen at run time.
private struct AnyLabelStyle: LabelStyle {
    let icon: Bool
    static let iconOnly = AnyLabelStyle(icon: true), titleOnly = AnyLabelStyle(icon: false)
    func makeBody(configuration: Configuration) -> some View {
        if icon { configuration.icon } else { configuration.title }
    }
}

/// A dashed "+" target that adds a row or a column.
private struct AddTarget: View {
    let title: String
    let vertical: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if vertical { Image(systemName: "plus") } else { Label(title, systemImage: "plus").labelStyle(.titleAndIcon) }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A key name drawn as a small keycap.
private struct Keycap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
    }
}

/// A grey rounded status chip.
private struct Chip: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

/// A bordered toggle shows no on state, so an on toggle draws prominent (filled with the accent), as before.
private struct BarToggle: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        Group {
            if on { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
