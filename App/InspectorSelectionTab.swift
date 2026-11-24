import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What the caret is on, as the Selection tab shows it. Everything is optional; none of it set means "No Selection".
struct InspectorSelection {
    struct Label { var hit: LabelHit; var definedIn: LabelSite?; var definitionCount = 0; var references: [LabelSite] = [] }
    struct Function { var name: String; var signature: String?; var docs: String?; var url: URL? }
    var figure: FigureInfo?
    var table: TableLookup?
    var color: ColorLiteral?
    var label: Label?
    var function: Function?
    var inFontValue = false

    var isEmpty: Bool { figure == nil && table == nil && color == nil && label == nil && function == nil && !inFontValue }
}

struct InspectorSelectionTab: View {
    let project: Project
    let actions: EditorActions
    let tables: TableEditing
    var browseFonts: () -> Void = {}
    @State private var selection = InspectorSelection()
    @State private var revision = 0
    /// Kept while the colour is dragged: the literal's current range, which the text moves under us.
    @State private var colorRange: NSRange?

    var body: some View {
        // The caret status changes with every caret move and every edit that moves it.
        let key = [actions.caretStatus ?? "", "\(actions.caretEpoch)", project.selectedFile?.raw ?? "", "\(revision)", "\(project.fileRevision)"]
        InspectorSelectionBody(
            selection: selection,
            editFigure: { shown, field, value in
                // The figure that was shown, not the one under the caret now: focus leaves the field after a click in the editor.
                guard let b = buffer, let f = FigureInfo.at(shown.call.range.location + 1, in: b.storage.string), f.call.range.location == shown.call.range.location,
                      f.value(field) != value, let r = f.edit(field, to: value) else { return }
                b.apply([r], actionName: String(localized: "Edit Figure"))
                revision += 1
            },
            editTable: { tables.beginEdit() },
            setColor: setColor,
            browseFonts: browseFonts,
            open: { project.show($0.file, range: $0.token, flash: true) })
            .task(id: key) { await refresh() }
    }

    private var buffer: Buffer? { actions.editor?.buffer }
    private var caret: Int { actions.editor?.textView?.selectedRange().location ?? 0 }

    private func refresh() async {
        // Settle first: a caret that is still moving (a Cmd-click jump, typing) must not queue engine requests or whole-project scans.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        guard let b = buffer, b.isTypst, project.selectedFile == b.path else { selection = InspectorSelection(); return }
        let text = b.storage.string, offset = caret
        var s = InspectorSelection()
        s.figure = FigureInfo.at(offset, in: text)
        s.table = b.table(at: offset)
        s.inFontValue = FontCatalog.valueRange(at: offset, in: text) != nil
        s.color = (b.colorLiterals.isEmpty ? ColorLiterals.scan(text) : b.colorLiterals).first { $0.range.location <= offset && offset <= NSMaxRange($0.range) }
        if s.color?.range != colorRange { colorRange = s.color?.range }
        if let token = TypstSyntax.tokens(in: text).first(where: { $0.tag == .function && $0.range.location <= offset && offset <= NSMaxRange($0.range) }) {
            let name = (text as NSString).substring(with: token.range)
            var f = InspectorSelection.Function(name: name, signature: await project.signature(in: b.path, at: offset))
            if case .builtin(let doc) = await project.definition(in: b.path, at: offset) {
                f.docs = String(doc.docs.split(separator: "\n\n").first ?? ""); f.url = doc.url
            }
            s.function = f
        }
        let labels = await project.labelIndex()
        if let hit = labels.hit(in: b.path, at: offset) {
            let target = labels.target(of: hit.name)
            s.label = .init(hit: hit, definedIn: target?.site, definitionCount: target?.count ?? 0, references: labels.references[hit.name] ?? [])
        }
        guard !Task.isCancelled else { return }
        selection = s
    }

    /// Rewrites the literal under the caret as the colour changes, as the editor's own swatch does.
    private func setColor(_ c: NSColor) {
        guard let b = buffer, let range = colorRange, let c = c.usingColorSpace(.sRGB),
              ColorLiterals.scan(b.storage.string).contains(where: { $0.range == range }) else { return }
        let text = ColorLiterals.source(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
        guard (b.storage.string as NSString).substring(with: range) != text else { return }
        b.apply([Replacement(range: range, text: text)], actionName: String(localized: "Change Color"))
        colorRange = NSRange(location: range.location, length: (text as NSString).length)
    }
}

struct InspectorSelectionBody: View {
    let selection: InspectorSelection
    var editFigure: (FigureInfo, FigureInfo.Field, String) -> Void = { _, _, _ in }
    var editTable: () -> Void = {}
    var setColor: (NSColor) -> Void = { _ in }
    var browseFonts: () -> Void = {}
    var open: (LabelSite) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
    }

    @ViewBuilder private var content: some View {
        if selection.isEmpty {
            ContentUnavailableView("No Selection", systemImage: "cursorarrow.click.2",
                                   description: Text("Put the caret in a figure, table, color, label or function call."))
        }
        if let f = selection.figure {
            InspectorSection("Figure") {
                InspectorField(title: "Caption", value: f.value(.caption)) { editFigure(f, .caption, $0) }
                InspectorField(title: "Label", value: f.value(.label)) { editFigure(f, .label, $0) }
                InspectorField(title: "Alt Text", value: f.value(.alt)) { editFigure(f, .alt, $0) }
                InspectorField(title: "Placement", value: f.value(.placement)) { editFigure(f, .placement, $0) }
                InspectorField(title: "Kind", value: f.value(.kind)) { editFigure(f, .kind, $0) }
                Text("Empty fields are left out of the source. Placement is top, bottom, auto or none.").font(.caption).foregroundStyle(.secondary)
            }
        }
        if let t = selection.table {
            InspectorSection("Table") {
                switch t {
                case .table(let m):
                    InspectorRow("Columns", m.columns.count.formatted())
                    InspectorRow("Header", m.header == nil ? String(localized: "No") : String(localized: "Yes"))
                    Button("Edit Table…", systemImage: "tablecells.badge.ellipsis", action: editTable).help("Edit this table in the table editor")
                case .unsupported(let reason):
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        if let c = selection.color {
            InspectorSection("Color") {
                ColorPopoverView(color: c, onChange: setColor).id(c.range.location)
            }
        }
        if let l = selection.label {
            InspectorSection(l.hit.kind == .reference ? "Reference" : "Label") {
                InspectorRow("Name", l.hit.name)
                InspectorRow("Defined", l.definedIn.map { _ in l.definitionCount == 1 ? String(localized: "Once") : String(localized: "\(l.definitionCount) times") } ?? String(localized: "Nowhere"))
                InspectorRow("References", l.references.count.formatted())
                if let d = l.definedIn {
                    Button("Go to \(l.hit.kind == .bibKey ? "Entry" : "Definition") in \(d.file.name)", systemImage: "arrow.turn.down.right") { open(d) }
                        .buttonStyle(.link)
                }
                ForEach(Array(l.references.prefix(12).enumerated()), id: \.offset) { _, r in
                    Button("Reference in \(r.file.name)", systemImage: "arrow.turn.down.right") { open(r) }.buttonStyle(.link)
                }
                if l.references.count > 12 { Text("and \(l.references.count - 12) more").font(.caption).foregroundStyle(.secondary) }
            }
        }
        if selection.inFontValue {
            InspectorSection("Font") {
                Button("Browse Fonts…", systemImage: "textformat", action: browseFonts).help("Pick the font's exact name in the library")
            }
        }
        if let f = selection.function {
            InspectorSection("Function \(f.name)") {
                if let s = f.signature { Text(s).font(.callout.monospaced()).textSelection(.enabled).accessibilityLabel("Signature \(s)") }
                if let d = f.docs, !d.isEmpty { Text(d).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                if let u = f.url { Link("Open Documentation", destination: u).font(.callout) }
            }
        }
    }
}

#Preview("Selection: figure and function") {
    ScrollView {
        InspectorSelectionBody(selection: {
            var s = InspectorSelection()
            s.figure = FigureInfo.at(10, in: "#figure(image(\"a.png\"), caption: [A cat], placement: top) <cat>")
            s.function = .init(name: "figure", signature: "figure(\n  body: content,\n  caption: none | content,\n)", docs: "A figure with an optional caption.", url: URL(string: "https://typst.app/docs/reference/model/figure/"))
            return s
        }()).padding(12)
    }
    .frame(width: 280, height: 560)
}

#Preview("Selection: none") {
    InspectorSelectionBody(selection: InspectorSelection()).frame(width: 280, height: 300)
}
