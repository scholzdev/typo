import SwiftUI
import TypoKit
import TypstEngine

/// The Bookmarks navigator: the user's groups, then the other bookmarks by file, as in Xcode. Selecting a row reveals it.
struct BookmarksTab: View {
    let project: Project
    let model: SidebarModel
    @AppStorage(SettingsKey.bookmarkDetail) private var detail = 1
    @State private var snippets: [UUID: String] = [:]
    @State private var selection: Set<UUID> = []
    @State private var collapsed: Set<String> = []
    @State private var editing: Edit?
    @State private var text = ""
    @State private var confirmsRemoveAll = false

    private enum Edit { case title(UUID), note(UUID), renameGroup(String), newGroup(Set<UUID>) }

    var body: some View {
        let shown = project.sortedBookmarks.filter(matches)
        let loose = shown.filter { $0.group.isEmpty }
        let paths = loose.map(\.path).reduce(into: [RelPath]()) { if $0.last != $1 { $0.append($1) } }
        List(selection: $selection) {
            if project.bookmarks.isEmpty {
                ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
                                       description: Text("Choose Navigate \u{203A} Toggle Bookmark or click a line number to bookmark a line."))
            } else if shown.isEmpty {
                Text("No Matching Bookmarks").foregroundStyle(.secondary)
            }
            ForEach(project.bookmarkGroups.filter { g in shown.contains { $0.group == g } }, id: \.self) { group in
                Section(isExpanded: Binding(get: { !collapsed.contains(group) }, set: { if $0 { collapsed.remove(group) } else { collapsed.insert(group) } })) {
                    ForEach(shown.filter { $0.group == group }) { row($0) }
                } header: {
                    Label(group, systemImage: "folder").contextMenu {
                        Button("Rename Group\u{2026}", systemImage: "pencil") { text = group; editing = .renameGroup(group) }
                        Button("Delete Group", systemImage: "folder.badge.minus") { project.renameBookmarkGroup(group, to: "") }
                    }
                }
            }
            ForEach(paths, id: \.self) { path in
                Section(path.raw) {
                    ForEach(loose.filter { $0.path == path }) { row($0) }
                }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { menu($0) }
        .onChange(of: selection) { _, ids in
            if ids.count == 1, let b = project.bookmarks.first(where: { $0.id == ids.first }) { project.reveal(b) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        // A compile follows every edit, so the status change refreshes the lines' text.
        .task(id: SnippetKey(bookmarks: project.bookmarks, status: project.status)) { snippets = await project.bookmarkSnippets() }
        .alert(alertTitle, isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(alertField, text: $text)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) { editing = nil }
        }
        .confirmationDialog("Remove all bookmarks?", isPresented: $confirmsRemoveAll) {
            Button("Remove All", role: .destructive) { project.removeBookmarks { _ in true } }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private struct SnippetKey: Equatable { let bookmarks: [CodeBookmark]; let status: CompileStatus }

    private var alertTitle: String {
        switch editing {
        case .note: "Edit Note"
        case .renameGroup: "Rename Group"
        case .newGroup: "New Group"
        case .title, nil: "Rename Bookmark"
        }
    }

    private var alertField: String {
        switch editing {
        case .note: "Note"
        case .renameGroup, .newGroup: "Name"
        case .title, nil: "Title"
        }
    }

    private func snippet(_ b: CodeBookmark) -> String { project.openSnippet(b) ?? snippets[b.id] ?? "" }

    private func matches(_ b: CodeBookmark) -> Bool {
        if model.bookmarksIncompleteOnly && b.done { return false }
        let q = model.bookmarkFilter
        return q.isEmpty || [b.displayTitle, snippet(b), b.note, b.path.raw].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    private func row(_ b: CodeBookmark) -> some View {
        HStack(alignment: .top, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                FileIcon(kind: FileKind(path: b.path.raw)).opacity(b.done ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.displayTitle).lineLimit(1).strikethrough(b.done).foregroundStyle(b.done ? .secondary : .primary)
                    let line = snippet(b)
                    if !line.isEmpty { Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(lines: detail) }
                    if !b.note.isEmpty { Text(b.note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(lines: detail) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {               // also a click on the selected row; arrows go by `selection`
                if NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]) { project.reveal(b) }
            })
            Toggle(b.done ? "Mark as Incomplete" : "Mark as Complete", isOn: Binding(get: { b.done }, set: { v in project.updateBookmark(b.id) { $0.done = v } }))
                .toggleStyle(.checkbox).labelsHidden()
        }
        .tag(b.id)
    }

    /// The menu of the clicked row, or of the selection when the click was on it.
    @ViewBuilder private func menu(_ ids: Set<UUID>) -> some View {
        let picked = project.sortedBookmarks.filter { ids.contains($0.id) }
        if picked.count == 1, let b = picked.first {
            Button("Rename\u{2026}", systemImage: "pencil") { text = b.displayTitle; editing = .title(b.id) }
            Button("Edit Note\u{2026}", systemImage: "note.text") { text = b.note; editing = .note(b.id) }
            Button(b.done ? "Mark as Incomplete" : "Mark as Complete", systemImage: b.done ? "circle" : "checkmark.circle") {
                project.updateBookmark(b.id) { $0.done.toggle() }
            }
            Divider()
        }
        if !picked.isEmpty {
            Button("New Group with Selection", systemImage: "folder.badge.plus") { text = project.newBookmarkGroupName; editing = .newGroup(ids) }
            Menu("Move to Group", systemImage: "folder") {
                ForEach(project.bookmarkGroups, id: \.self) { g in Button(g) { project.moveBookmarks(ids, toGroup: g) } }
                if picked.contains(where: { !$0.group.isEmpty }) {
                    Divider()
                    Button("No Group") { project.moveBookmarks(ids, toGroup: "") }
                }
            }
            .disabled(project.bookmarkGroups.isEmpty)
            Divider()
            Button(picked.count == 1 ? "Remove Bookmark" : "Remove \(picked.count) Bookmarks", systemImage: "bookmark.slash", role: .destructive) {
                project.removeBookmarks { ids.contains($0.id) }
            }
        }
    }

    private func save() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch editing {
        case .title(let id): project.updateBookmark(id) { $0.title = value }
        case .note(let id): project.updateBookmark(id) { $0.note = value }
        case .renameGroup(let old) where !value.isEmpty:
            if collapsed.remove(old) != nil { collapsed.insert(value) }
            project.renameBookmarkGroup(old, to: value)
        case .newGroup(let ids) where !value.isEmpty: project.moveBookmarks(ids, toGroup: value)
        default: break
        }
        editing = nil
    }

    private var footer: some View {
        @Bindable var model = model
        return HStack(spacing: 6) {
            Menu {
                Button("Delete All Completed", systemImage: "checkmark.circle") { project.removeBookmarks(where: \.done) }
                    .disabled(!project.bookmarks.contains(where: \.done))
                Button("Remove All Bookmarks\u{2026}", systemImage: "trash") { confirmsRemoveAll = true }
                    .disabled(project.bookmarks.isEmpty)
            } label: { Image(systemName: "ellipsis.circle").font(.system(size: 13)).frame(width: 22, height: 22).contentShape(Rectangle()) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Bookmark Actions")
                .accessibilityLabel("Bookmark Actions")
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                TextField("Filter", text: $model.bookmarkFilter).textFieldStyle(.plain).accessibilityLabel("Filter Bookmarks")
                if !model.bookmarkFilter.isEmpty {
                    Button("Clear Filter", systemImage: "xmark.circle.fill") { model.bookmarkFilter = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Toggle("Incomplete Only", systemImage: model.bookmarksIncompleteOnly ? "checkmark.circle.fill" : "checkmark.circle", isOn: $model.bookmarksIncompleteOnly)
                    .toggleStyle(.button).labelStyle(.iconOnly).buttonStyle(.plain)
                    .foregroundStyle(model.bookmarksIncompleteOnly ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .help("Show Only Incomplete Bookmarks")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6).frame(height: 22)
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}
