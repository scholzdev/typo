import SwiftUI
import TypoKit
import TypstEngine

/// The form for a `.bib` file: its entries on the left, the selected entry's fields on the right. Every change goes
/// through `Buffer.apply`, so undo, autosave, the References popover and the preview see it like a typed edit.
struct BibEditorView: View {
    let project: Project
    let buffer: Buffer
    let tables: TableEditing
    @Binding var showsSource: Bool
    @State private var query = ""
    @State private var selection: Int?
    @State private var adding = false
    @State private var creating = false
    @State private var connectingZotero = false

    /// Zotero fills the file: every sync would overwrite an edit made here.
    private var readOnly: Bool { buffer.isZoteroManaged }

    var body: some View {
        let _ = project.bibliographyRevision        // reparse after every edit to the file, ours or the text view's
        let entries = BibTeX.entries(in: buffer.storage.string)
        let shown = entries.indices.filter { matches(entries[$0]) }
        let duplicates = BibTeX.duplicates(entries)
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(shown, id: \.self) { i in
                        BibListRow(entry: entries[i], duplicateOf: duplicates[i]).tag(i)
                    }
                }
                .listStyle(.sidebar)
                // On a row and on the empty space below the rows alike.
                .contextMenu(forSelectionType: Int.self) { items in
                    Button("New Entry…", systemImage: "plus") { creating = true }.disabled(readOnly)
                    Button("New Entry from DOI, arXiv or ISBN…", systemImage: "network") { adding = true }.disabled(readOnly)
                    if !items.isEmpty, !readOnly {
                        Divider()
                        Button(items.count == 1 ? "Delete Entry" : "Delete \(items.count) Entries", systemImage: "trash", role: .destructive) {
                            delete(items)
                        }
                    }
                }
                .onDeleteCommand { if let selection { delete([selection]) } }
                .overlay {
                    if entries.isEmpty {
                        ContentUnavailableView {
                            Label("No Entries", systemImage: "books.vertical")
                        } description: {
                            Text("Add a reference to cite it from your document.")
                        } actions: {
                            Button("New Entry…") { creating = true }.disabled(readOnly)
                        }
                    } else if shown.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text(shown.count == entries.count ? "\(entries.count) entries" : "\(shown.count) of \(entries.count) entries")
                        .font(.caption).foregroundStyle(.secondary).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                }
                .frame(minWidth: 180, idealWidth: 280, maxWidth: 340)
                Divider()
                Group {
                    if let selection, entries.indices.contains(selection) {
                        BibEntryForm(entry: entries[selection], usedKeys: Set(entries.map(\.key)),
                                     change: { change in update(selection, change) }, delete: { delete([selection]) })
                            .id(selection)
                            .disabled(readOnly)
                    } else {
                        ContentUnavailableView("No Entry Selected", systemImage: "text.book.closed",
                                               description: Text("Choose an entry to edit its fields."))
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
        .sheet(isPresented: $adding) { AddReferenceSheet(project: project, tables: tables) }
        .sheet(isPresented: $creating) { NewBibEntrySheet(usedKeys: Set(entries.map(\.key)), add: add) }
        .sheet(isPresented: $connectingZotero) { ZoteroConnectSheet(project: project, suggested: buffer.path) }
        .onAppear { if selection == nil, !entries.isEmpty { selection = 0 } }
        .onChange(of: buffer.path) { selection = BibTeX.entries(in: buffer.storage.string).isEmpty ? nil : 0 }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TextField("Search entries", text: $query).glassSearchField().frame(maxWidth: 240)
            Spacer()
            Menu {
                Button("New Entry…", systemImage: "plus") { creating = true }
                Button("From DOI, arXiv or ISBN…", systemImage: "network") { adding = true }
            } label: {
                Label("New Entry", systemImage: "plus")
            } primaryAction: {
                creating = true
            }
            .menuStyle(.button)
            .help("New Entry")
            .disabled(readOnly)
            if project.zoteroLink == nil {
                Button("Connect Zotero…", systemImage: "books.vertical") { connectingZotero = true }
                    .help("Fill a .bib file from your Zotero library")
            }
            Picker("View", selection: $showsSource) {
                Label("Form", systemImage: "list.bullet.rectangle").tag(false)
                Label("Source", systemImage: "chevron.left.forwardslash.chevron.right").tag(true)
            }
            .pickerStyle(.segmented).fixedSize()
            .help("Show the entries as a form or as BibTeX source")
            .accessibilityLabel("View")
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func matches(_ e: BibTeXEntry) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || ([e.key, e.type] + e.fields.map(\.value)).contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// Edits entry `index` of the file as it is now, not as it was when the view was drawn.
    private func update(_ index: Int, _ change: (inout BibTeXEntry) -> Void) {
        guard !readOnly else { return }
        var entries = BibTeX.entries(in: buffer.storage.string)
        guard entries.indices.contains(index) else { return }
        change(&entries[index])
        buffer.apply([BibTeX.update(entries[index])], actionName: "Edit Reference")
    }

    /// Deletes the entries at `indices` as one undo step, from the last so the earlier ranges stay valid.
    private func delete(_ indices: Set<Int>) {
        guard !readOnly else { return }
        let count = BibTeX.entries(in: buffer.storage.string).count
        let doomed = indices.filter { $0 < count }.sorted(by: >)
        guard let first = doomed.last else { return }
        let um = buffer.undoManager
        um.beginUndoGrouping()
        for i in doomed {
            let text = buffer.storage.string
            buffer.apply([BibTeX.removal(BibTeX.entries(in: text)[i], in: text)])
        }
        um.setActionName(doomed.count == 1 ? "Delete Reference" : "Delete References")
        um.endUndoGrouping()
        let left = count - doomed.count
        selection = left > 0 ? min(first, left - 1) : nil
    }

    private func add(_ entry: BibTeXEntry) {
        guard !readOnly else { return }
        let text = buffer.storage.string
        let index = BibTeX.entries(in: text).count
        buffer.apply([BibTeX.append(entry, to: text)], actionName: "New Reference")
        query = ""
        selection = index
    }
}

/// An entry type's SF Symbol, in the list and in the detail header.
func bibKindSymbol(_ kind: String) -> String {
    switch kind.lowercased() {
    case "book", "inbook", "incollection", "booklet", "anthology", "chapter": "book.closed"
    case "article", "periodical", "newspaper": "doc.text"
    case "inproceedings", "proceedings", "conference": "person.3"
    case "thesis", "phdthesis", "mastersthesis": "graduationcap"
    case "online", "web", "blog": "globe"
    case "software": "chevron.left.forwardslash.chevron.right"
    case "report", "techreport", "manual": "doc.plaintext"
    case "unpublished": "square.and.pencil"
    default: "doc"
    }
}

/// A row of the entry list: title, "Author · Year", the key small and monospaced, the type as a symbol.
private struct BibListRow: View {
    let entry: BibTeXEntry
    let duplicateOf: String?

    var body: some View {
        let s = entry.summary
        let byline = [s.authors, s.year.map(String.init) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: bibKindSymbol(entry.type)).foregroundStyle(.secondary).frame(width: 18).padding(.top, 2)
                .help("@\(entry.type.lowercased())")
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title.isEmpty ? "Untitled" : s.title).lineLimit(2)
                    .foregroundStyle(s.title.isEmpty ? .secondary : .primary)
                if !byline.isEmpty { Text(byline).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 4) {
                    Text(entry.key).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    if let duplicateOf {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                            .help("Duplicate of \(duplicateOf)")
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([s.title, byline, "key \(entry.key)", entry.type, duplicateOf.map { "duplicate of \($0)" } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/// The selected entry: a header with its type, title and key, then its fields as a grouped form.
struct BibEntryForm: View {
    let entry: BibTeXEntry
    let usedKeys: Set<String>
    let change: ((inout BibTeXEntry) -> Void) -> Void
    let delete: () -> Void
    @State private var customField = ""
    @State private var addingCustom = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Form {
                Section("Entry") {
                    Picker("Type", selection: Binding(get: { entry.type.lowercased() }, set: { t in change { $0.type = t } })) {
                        ForEach(types, id: \.self) { Label("@\($0)", systemImage: bibKindSymbol($0)).tag($0) }
                    }
                    FieldEditor(label: "Key", value: entry.key, monospaced: true, isValid: isValidKey) { k in change { $0.key = k } }
                }
                Section("Fields") {
                    let missing = BibTeX.missingRequired(type: entry.type, present: Set(required.filter { !$0.value.isEmpty }.map(\.name) + optional.filter { !$0.value.isEmpty }.map { $0.name.lowercased() }))
                    ForEach(required, id: \.name) { row in fieldRow(row, hint: missing.contains(row.name) ? "Required" : nil) }
                }
                Section("More Fields") {
                    ForEach(optional, id: \.index) { fieldRow($0, hint: nil) }
                    addFieldMenu
                }
            }
            .formStyle(.grouped)
        }
        .alert("Add Field", isPresented: $addingCustom) {
            TextField("Field name", text: $customField)
            Button("Cancel", role: .cancel) {}
            Button("Add") { addField(customField.trimmingCharacters(in: .whitespaces).lowercased()) }
                .disabled(!isFieldName(customField.trimmingCharacters(in: .whitespaces)))
        }
    }

    private var detailHeader: some View {
        let s = entry.summary
        let sub = [s.authors, s.year.map(String.init) ?? "", entry.value("publisher") ?? entry.value("journal") ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: bibKindSymbol(entry.type)).font(.system(size: 34)).foregroundStyle(.secondary)
                .frame(width: 48).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title.isEmpty ? "Untitled" : s.title).font(.title2.bold()).lineLimit(3)
                    .foregroundStyle(s.title.isEmpty ? .secondary : .primary).textSelection(.enabled)
                if !sub.isEmpty { Text(sub).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 8) {
                    Text("@" + entry.key).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(.quaternary, in: .capsule)
                        .layoutPriority(1)
                    Button(copied ? "Copied" : "Copy @key", systemImage: copied ? "checkmark" : "doc.on.doc", action: copyKey)
                        .buttonStyle(.borderless).controlSize(.small)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Button("Delete Entry", systemImage: "trash", role: .destructive, action: delete)
                .labelStyle(.iconOnly).help("Delete Entry (undo with Edit › Undo)")
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
    }

    private var addFieldMenu: some View {
        Menu {
            ForEach(missingFields, id: \.self) { name in Button(name) { addField(name) } }
            if !missingFields.isEmpty { Divider() }
            Button("Custom Field…") { customField = ""; addingCustom = true }
        } label: {
            Label("Add Field", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    /// One form row: a field of the entry (`index`), or a typical field it doesn't have yet (`index == nil`).
    private struct Row { let name: String; let index: Int?; let value: String; let isRaw: Bool }

    private var required: [Row] {
        BibTeX.typicalFields(for: entry.type).map { name in
            let i = entry.fields.firstIndex { $0.name.lowercased() == name }
            return Row(name: name, index: i, value: i.map { entry.fields[$0].value } ?? "", isRaw: i.map { entry.fields[$0].isRaw } ?? false)
        }
    }

    private var optional: [Row] {
        let used = Set(required.compactMap(\.index))
        return entry.fields.indices.filter { !used.contains($0) }
            .map { Row(name: entry.fields[$0].name, index: $0, value: entry.fields[$0].value, isRaw: entry.fields[$0].isRaw) }
    }

    private func fieldRow(_ row: Row, hint: String?) -> some View {
        let valid: (String) -> Bool = row.isRaw ? { !$0.isEmpty } : { BibTeX.isBalanced($0) }
        let tip = row.isRaw ? "Written without braces: a number, @string macro or # concatenation" : ""
        return FieldEditor(label: row.name, value: row.value, hint: hint, multiline: ["abstract", "note"].contains(row.name.lowercased()), remove: row.index.map { i in { remove(i) } }, isValid: valid) { v in
            change { e in
                if let i = row.index, e.fields.indices.contains(i) { e.fields[i].value = v }
                else if !v.isEmpty { e.fields.append(.init(name: row.name, value: v)) }
            }
        }
        .help(tip)
        .contextMenu {
            if let i = row.index { Button("Remove Field", systemImage: "minus.circle", role: .destructive) { remove(i) } }
        }
        .accessibilityAction(named: "Remove \(row.name)") { if let i = row.index { remove(i) } }
    }

    private func remove(_ i: Int) { change { e in if e.fields.indices.contains(i) { e.fields.remove(at: i) } } }

    private func copyKey() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("@" + entry.key, forType: .string)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
    }

    private func isValidKey(_ k: String) -> Bool {
        let wellFormed = !k.isEmpty && !k.contains { $0.isWhitespace || $0 == "," || $0 == "{" || $0 == "}" }
        return wellFormed && (k == entry.key || !usedKeys.contains(k))
    }

    private var types: [String] {
        BibTeX.types.contains(entry.type.lowercased()) ? BibTeX.types : BibTeX.types + [entry.type.lowercased()]
    }

    private var missingFields: [String] {
        let present = Set(entry.fields.map { $0.name.lowercased() })
        return BibTeX.optionalFields(for: entry.type).filter { !present.contains($0) }
    }

    private func isFieldName(_ s: String) -> Bool { s.wholeMatch(of: /[A-Za-z][A-Za-z0-9_\-]*/) != nil }

    private func addField(_ name: String) {
        guard isFieldName(name), !entry.fields.contains(where: { $0.name.lowercased() == name }) else { return }
        change { $0.fields.append(.init(name: name, value: "")) }
    }
}

/// A text field that writes through only valid values: an unbalanced `{` stays in the field, outlined in red, until
/// its `}` is typed, and doesn't break the file in between.
private struct FieldEditor: View {
    let label: String
    let value: String
    var hint: String? = nil
    var monospaced = false
    var multiline = false
    var remove: (() -> Void)? = nil
    let isValid: (String) -> Bool
    let commit: (String) -> Void
    @State private var draft = ""
    @State private var hovering = false

    var body: some View {
        let valid = isValid(draft)
        LabeledContent(label) {
            VStack(alignment: .leading, spacing: 2) {
                TextField(label, text: $draft, axis: .vertical)
                    .labelsHidden()
                    .lineLimit(1...(multiline ? 8 : 4))
                    .font(monospaced ? .body.monospaced() : .body)
                    .foregroundStyle(valid ? Color.primary : Color.red)
                if let hint, draft.isEmpty { Text(hint).font(.caption).foregroundStyle(.orange) }
                if !valid { Text(draft.isEmpty ? "Can't be empty" : "Unbalanced braces or duplicate key").font(.caption).foregroundStyle(.red) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                if let remove, hovering {
                    Button("Remove \(label)", systemImage: "minus.circle.fill", action: remove)
                        .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove Field")
                }
            }
        }
        .onHover { hovering = $0 }
        .onAppear { draft = value }
        .onChange(of: value) { if draft != value { draft = value } }
        .onChange(of: draft) { if draft != value, isValid(draft) { commit(draft) } }
    }
}

extension BibTeXEntry {
    /// What the list row shows: the first author's surname is enough there, the full list is in the form.
    var summary: BibEntry {
        let authors = (value("author") ?? value("editor") ?? "")
            .components(separatedBy: " and ")
            .map { name in
                let n = name.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "{}")))
                if let comma = n.firstIndex(of: ",") { return String(n[..<comma]) }
                return n.split(separator: " ").last.map(String.init) ?? n
            }
            .filter { !$0.isEmpty }
        let who = authors.count > 2 ? "\(authors[0]) et al." : authors.joined(separator: " & ")
        let year = (value("year") ?? value("date")).flatMap { $0.firstMatch(of: /\d{4}/).flatMap { Int($0.output) } }
        let title = (value("title") ?? "").replacing(/[{}]/, with: "")
        return BibEntry(key: key, title: title, authors: who, year: year, kind: type.lowercased())
    }
}

/// Every detail of a new entry before it goes into the file: type, key and the type's fields. Empty fields are left out.
private struct NewBibEntrySheet: View {
    let usedKeys: Set<String>
    let add: (BibTeXEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type = "article"
    @State private var key = ""
    /// Until the key is typed, it follows the author and year.
    @State private var keyEdited = false
    @State private var values: [String: String] = [:]
    @State private var showsMore = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(BibTeX.types, id: \.self) { Text("@\($0)").tag($0) }
                    }
                    TextField("Key", text: Binding(get: { key }, set: { key = $0; keyEdited = true }), prompt: Text("surname2024"))
                        .font(.body.monospaced())
                } footer: {
                    if let problem = keyProblem { Text(problem).foregroundStyle(.red).font(.callout) }
                }
                Section("Fields") {
                    ForEach(BibTeX.typicalFields(for: type), id: \.self) { fieldRow($0) }
                }
                Section(isExpanded: $showsMore) {
                    ForEach(BibTeX.optionalFields(for: type), id: \.self) { fieldRow($0) }
                } header: {
                    Text("More Fields")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                SheetButtons(ok: "Add Entry", disabled: keyProblem != nil || !invalidFields.isEmpty, cancel: { dismiss() }, action: commit)
            }
            .padding(14)
        }
        .frame(width: 480, height: 560)
        .onChange(of: values) { suggestKey() }
        .onAppear { suggestKey() }
    }

    private func fieldRow(_ name: String) -> some View {
        let value = values[name] ?? ""
        return TextField(name, text: Binding(get: { value }, set: { values[name] = $0 }), axis: .vertical)
            .foregroundStyle(BibTeX.isBalanced(value) ? Color.primary : Color.red)
    }

    private var keyProblem: String? {
        if key.isEmpty { return "Every entry needs a key." }
        if key.contains(where: { $0.isWhitespace || ",{}".contains($0) }) { return "A key can't contain spaces, commas or braces." }
        if usedKeys.contains(key) { return "“\(key)” is already used in this file." }
        return nil
    }

    private var invalidFields: [String] { values.filter { !BibTeX.isBalanced($0.value) }.map(\.key) }

    private func suggestKey() {
        guard !keyEdited else { return }
        let base = BibTeX.suggestedKey(author: values["author"] ?? "", year: values["year"] ?? "") ?? type
        key = BibTeX.uniqueKey(base, used: usedKeys)
    }

    private func commit() {
        let names = BibTeX.suggestedFields(for: type)
        let fields = names.compactMap { name -> BibTeXEntry.Field? in
            let v = (values[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return v.isEmpty ? nil : .init(name: name, value: v)
        }
        add(BibTeXEntry(type: type, key: key, fields: fields))
        dismiss()
    }
}

#Preview("Entry form") {
    @Previewable @State var entry = BibTeXEntry(type: "book", key: "knuth1984", fields: [
        .init(name: "author", value: "Knuth, Donald E."), .init(name: "title", value: "The {TeX}book"),
        .init(name: "publisher", value: "Addison-Wesley"), .init(name: "year", value: "1984"),
        .init(name: "note", value: "Computers & Typesetting, Volume A"),
    ])
    BibEntryForm(entry: entry, usedKeys: ["knuth1984", "lamport1994"], change: { $0(&entry) }, delete: {})
        .frame(width: 620, height: 640)
}
