import SwiftUI
import TypoKit
import TypstEngine

extension View {
    func citationPicker(project: Project, actions: EditorActions, tables: TableEditing) -> some View {
        sheet(isPresented: Binding(get: { actions.citationPickerPresented }, set: { actions.citationPickerPresented = $0 })) {
            CitationPicker(project: project, tables: tables) { keys in
                actions.citationPickerPresented = false
                DispatchQueue.main.async { actions.editor?.insertText { BibliographyFile.citations(keys, mode: $0) } }
            }
        }
    }
}

/// Search over every entry of the project's bibliographies; Return inserts the selected ones.
private struct CitationPicker: View {
    let project: Project
    let tables: TableEditing
    let insert: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var files: [BibFile] = []
    @State private var selection: Set<String> = []
    @State private var adding = false
    @FocusState private var searching: Bool

    private var entries: [BibEntry] { files.flatMap(\.entries).filter { $0.matches(query) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Bibliography").font(.headline).foregroundStyle(.secondary)
                Spacer()
                TextField("Search entries", text: $query)
                    .focused($searching)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.return) { commit(); return .handled }
                    .glassSearchField().frame(maxWidth: 240)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            List(entries, selection: $selection) { e in
                BibEntryRow(entry: e).tag(e.key)
            }
            .scrollContentBackground(.hidden)
            .overlay { if entries.isEmpty { ContentUnavailableView(files.isEmpty ? "No Bibliography" : "No Matches", systemImage: "books.vertical") } }
            HStack {
                Button("Add from DOI, arXiv or ISBN…") { adding = true }.buttonStyle(.link)
                Text("⌘/⇧-click selects several").font(.caption).foregroundStyle(.secondary)
                Spacer()
                SheetButtons(ok: "Insert", disabled: selection.isEmpty, cancel: { dismiss() }, action: commit)
            }
            .padding(10)
        }
        .frame(width: 520, height: 420)
        .sheet(isPresented: $adding) { AddReferenceSheet(project: project, tables: tables, done: { dismiss() }) }
        .task { files = await project.references(); searching = true }
        .onChange(of: query) { selection = entries.first.map { [$0.key] } ?? [] }
    }

    private func move(_ step: Int) {
        guard !entries.isEmpty else { return }
        let i = entries.firstIndex { selection.contains($0.key) }.map { $0 + step } ?? (step > 0 ? 0 : entries.count - 1)
        selection = [entries[min(max(i, 0), entries.count - 1)].key]
    }

    private func commit() {
        let keys = entries.map(\.key).filter(selection.contains)      // in list order
        guard !keys.isEmpty else { return }
        insert(keys)
    }
}
