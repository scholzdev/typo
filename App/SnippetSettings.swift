import SwiftUI
import TypoKit

/// The Snippets pane of the Settings: the user's snippets with their tab-stop syntax.
struct SnippetSettings: View {
    @State private var store = UserSnippetStore.shared
    @State private var selection: UUID?
    @AppStorage(SettingsKey.editedSnippet) private var requested = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(store.snippets, selection: $selection) { s in
                    HStack {
                        Text(s.title.isEmpty ? String(localized: "Untitled") : s.title).lineLimit(1)
                        Spacer()
                        if !s.prefix.isEmpty {
                            Text(s.prefix).font(.caption.monospaced()).padding(.horizontal, 5)
                                .background(Capsule().fill(Color.secondary.opacity(0.18)))
                        }
                    }
                    .tag(s.id)
                }
                Divider()
                HStack(spacing: 2) {
                    Button { selection = store.add().id } label: { Image(systemName: "plus") }.help("Add a snippet")
                    Button { if let selection { self.selection = nil; store.delete(selection) } } label: { Image(systemName: "minus") }
                        .disabled(selection == nil).help("Delete the snippet")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 190)
            Divider()
            Group {
                if let id = selection, let snippet = store.snippets.first(where: { $0.id == id }) {
                    SnippetEditor(snippet: snippet) { store.update($0) }.id(id)
                } else {
                    Text("Select or add a snippet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: consumeRequest)
        .onChange(of: requested) { consumeRequest() }
    }

    /// "Edit…" in the library asks for a snippet by its library id.
    private func consumeRequest() {
        guard !requested.isEmpty else { return }
        if let s = store.snippets.first(where: { UserSnippet.libraryID($0.id) == requested }) { selection = s.id }
        requested = ""
    }
}

private struct SnippetEditor: View {
    @State var snippet: UserSnippet
    let save: (UserSnippet) -> Void

    var body: some View {
        Form {
            TextField("Title", text: $snippet.title)
            TextField("Summary", text: $snippet.summary)
            TextField("Prefix", text: $snippet.prefix, prompt: Text("Completion trigger, optional"))
            Picker("Placement", selection: $snippet.isBlock) {
                Text("Own line").tag(true)
                Text("Inline").tag(false)
            }
            LabeledContent("Body") {
                TextEditor(text: $snippet.body)
                    .font(.system(.callout, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .frame(height: 110)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            }
            Text("`${1:name}` is a tab stop with a default, `${1}` again mirrors it, `${}` and `${name}` are stops after the numbered ones, `${0}` is where the caret ends. A `$` without a brace is literal.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Preview") {
                Text(snippet.librarySnippet.plainText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onChange(of: snippet) { _, new in save(new) }
    }
}
