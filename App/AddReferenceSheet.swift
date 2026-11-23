import SwiftUI
import TypoKit
import TypstEngine

/// "Add Reference…": looks a DOI, arXiv ID or ISBN up, shows the entry, and appends it to a .bib of the project.
struct AddReferenceSheet: View {
    let project: Project
    let tables: TableEditing
    /// Runs after the reference was added or cited, e.g. to close a sheet underneath.
    var done: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var fetching = false
    @State private var error: String?
    @State private var draft: ReferenceDraft?
    @State private var usedKeys: Set<String> = []
    @State private var keyText = ""
    @State private var candidates: [RelPath] = []
    @State private var target: RelPath?
    @State private var appendBibliography = true
    @State private var insertCitation = true
    /// The project's entry for the same work, if any: adding it again would make a duplicate.
    @State private var existing: (key: String, file: RelPath)?

    /// The draft under the key in the field, or why that key is not acceptable.
    private var keyed: Result<ReferenceDraft, ReferenceError>? {
        guard let draft else { return nil }
        return Result { try draft.rekeyed(keyText, usedKeys: usedKeys) }.mapError { $0 as! ReferenceError }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Reference").font(.headline)
            HStack {
                TextField("DOI, arXiv ID or ISBN", text: $input, prompt: Text("10.1145/3591280, arXiv:1706.03762 or 978-0-201-03801-9"))
                    .textFieldStyle(.roundedBorder).onSubmit(fetch)
                Button("Fetch", action: fetch).buttonStyle(.glass).disabled(fetching || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if fetching { ProgressView().controlSize(.small) }
            if let error { Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            if let draft {
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.entry.title).font(.body.bold()).textSelection(.enabled)
                        Text([draft.entry.authors, draft.entry.year.map(String.init) ?? "", draft.entry.kind].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                if let existing {
                    Label("Already in \(existing.file.raw) as “\(existing.key)”.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                    if tables.editor != nil { Button("Cite @\(existing.key) instead") { cite(existing.key) } }
                }
                LabeledContent("Key") {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Key", text: $keyText).labelsHidden().font(.body.monospaced()).textFieldStyle(.roundedBorder)
                        if case .failure(let e) = keyed { Text(e.localizedDescription).font(.caption).foregroundStyle(.red) }
                    }
                }
                targetControls
                Toggle("Insert citation at cursor", isOn: $insertCitation).disabled(tables.editor == nil)
            }
            HStack {
                Spacer()
                SheetButtons(ok: "Add", disabled: !{ if case .success = keyed { true } else { false } }(), cancel: { dismiss() }, action: add)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { (candidates, target) = (project.referenceTargets().candidates, project.referenceTargets().preferred) }
    }

    @ViewBuilder private var targetControls: some View {
        if candidates.count > 1 {
            Picker("Add to", selection: $target) {
                ForEach(candidates, id: \.self) { Text($0.raw).tag(Optional($0)) }
            }
        } else if let only = candidates.first {
            LabeledContent("Add to") { Text(only.raw) }
        } else {
            LabeledContent("Add to") { Text("refs.bib (new file)") }
            Toggle("Add #bibliography(\"refs.bib\") to \(project.main.name)", isOn: $appendBibliography)
        }
    }

    private func fetch() {
        guard !fetching else { return }
        guard let id = ReferenceID.parse(input) else { error = "Enter a DOI (10.xxxx/…), an arXiv ID (2101.00001) or a valid ISBN-10 or ISBN-13."; return }
        fetching = true; error = nil; draft = nil; existing = nil
        Task {
            usedKeys = await project.usedReferenceKeys()
            do {
                let d = try await ReferenceLookup.fetch(id, usedKeys: usedKeys)
                draft = d; keyText = d.key
                existing = project.existingReference(for: d)
            } catch {
                self.error = error.localizedDescription
            }
            fetching = false
        }
    }

    private func cite(_ key: String) {
        dismiss(); done()
        DispatchQueue.main.async { tables.editor?.insertText { BibliographyFile.citation(key, mode: $0) } }
    }

    private func add() {
        guard case .success(let d) = keyed else { return }
        let cite = insertCitation && tables.editor != nil
        Task {
            do {
                try await project.addReference(d, to: candidates.isEmpty ? nil : target, appendBibliography: appendBibliography)
                dismiss(); done()
                if cite { DispatchQueue.main.async { tables.editor?.insertText { BibliographyFile.citation(d.key, mode: $0) } } }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
