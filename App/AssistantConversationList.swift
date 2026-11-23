import SwiftUI
import UniformTypeIdentifiers
import TypoKit
import TypoAssistant

/// The sidebar in assistant mode, like Xcode's: New Conversation and New Group, the conversations with their groups,
/// and Archive at the bottom. The conversation itself fills the editor area.
struct AssistantConversationList: View {
    @Bindable var model: AssistantModel
    @State private var selection: Set<UUID> = []
    @State private var renaming: AssistantConversation?
    @State private var newTitle = ""
    @State private var deleting: AssistantConversation?
    @State private var renamingGroup: UUID?
    @State private var groupName = ""
    @FocusState private var groupFieldFocused: Bool

    var body: some View {
        let byID = Dictionary(model.conversations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let live = { (ids: [UUID]) in ids.compactMap { byID[$0] }.filter { !$0.archived } }
        let archived = model.conversations.filter(\.archived).sorted { $0.updated > $1.updated }
        List(selection: $selection) {
            ForEach(model.layout.groups) { g in
                DisclosureGroup(isExpanded: Binding(get: { g.expanded }, set: { model.layout.setExpanded(g.id, $0) })) {
                    ForEach(live(g.items)) { row($0) }
                        .onMove { from, to in move(live(g.items), from, to, group: g.id) }
                } label: {
                    groupLabel(g)
                }
                .dropDestination(for: String.self) { items, _ in drop(items, into: g.id) }
            }
            ForEach(live(model.layout.order)) { row($0) }
                .onMove { from, to in move(live(model.layout.order), from, to, group: nil) }
            if !archived.isEmpty {
                DisclosureGroup(isExpanded: $model.layout.archiveExpanded) {
                    ForEach(archived) { row($0) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, s in if s.count == 1, let id = s.first { model.select(id) } }
        .onChange(of: model.currentID, initial: true) { _, id in
            if let id, !selection.contains(id) { selection = [id] } else if id == nil, selection.count == 1 { selection = [] }
        }
        .overlay {
            if model.conversations.isEmpty {
                ContentUnavailableView("No Conversations", systemImage: "sparkles", description: Text("Ask about your document to start one."))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                capsule("New Conversation", "square.and.pencil", help: "Starts a new conversation with the assistant") { model.newConversation(); selection = [] }
                capsule("New Group", "folder.badge.plus", help: "Adds a group to sort conversations into") { newGroup(with: []) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .alert("Rename Conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") { if let c = renaming { model.rename(c.id, to: newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let c = deleting { model.delete(c.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to permanently delete “\(deleting?.title ?? "")”? This cannot be undone.")
        }
    }

    private func capsule(_ title: String, _ symbol: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(.quaternary.opacity(0.7), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private func groupLabel(_ g: AssistantConversationLayout.Group) -> some View {
        if renamingGroup == g.id {
            TextField("Group Name", text: $groupName)
                .focused($groupFieldFocused)
                .onSubmit { commitGroupName() }
                .onChange(of: groupFieldFocused) { _, f in if !f { commitGroupName() } }
        } else {
            Label(g.name, systemImage: "folder")
                .contextMenu {
                    Button("Rename Group") { groupName = g.name; renamingGroup = g.id; groupFieldFocused = true }
                    Divider()
                    Button("Delete Group") { model.layout.deleteGroup(g.id) }
                }
        }
    }

    private func commitGroupName() {
        if let id = renamingGroup { model.layout.renameGroup(id, to: groupName) }
        renamingGroup = nil
    }

    private func newGroup(with items: [UUID]) {
        let id = model.layout.newGroup(named: "New Group", with: items)
        groupName = "New Group"
        renamingGroup = id
        groupFieldFocused = true
    }

    private func move(_ shown: [AssistantConversation], _ from: IndexSet, _ to: Int, group: UUID?) {
        let before = to < shown.count ? shown[to].id : nil
        for i in from { model.layout.move(shown[i].id, to: group, before: before) }
    }

    private func drop(_ items: [String], into group: UUID?) -> Bool {
        let ids = items.compactMap(UUID.init)
        ids.forEach { model.layout.move($0, to: group) }
        return !ids.isEmpty
    }

    private func row(_ c: AssistantConversation) -> some View {
        AssistantConversationRow(conversation: c, status: model.status(of: c.id), unread: model.layout.unread.contains(c.id))
            .tag(c.id)
            .draggable(c.id.uuidString)
            .contextMenu {
                Button("Rename Conversation") { newTitle = c.title; renaming = c }
                Button("New Group from Selection") { newGroup(with: selection.contains(c.id) ? Array(selection) : [c.id]) }
                if !model.layout.groups.isEmpty {
                    Menu("Move to Group") {
                        ForEach(model.layout.groups) { g in Button(g.name) { model.layout.move(c.id, to: g.id) } }
                        if model.layout.group(of: c.id) != nil {
                            Divider()
                            Button("No Group") { model.layout.move(c.id, to: nil, before: model.layout.order.first) }
                        }
                    }
                }
                Divider()
                Button(c.archived ? "Unarchive Conversation" : "Archive Conversation") { model.setArchived(c.id, !c.archived) }
                Divider()
                Button("Delete Conversation", role: .destructive) { deleting = c }
            }
    }
}

/// Title, then the status (Blocked, Working, Failed…) or when it was last active; a dot while unread.
struct AssistantConversationRow: View {
    let conversation: AssistantConversation
    let status: AssistantConversationStatus
    let unread: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title).lineLimit(1).fontWeight(unread ? .semibold : .regular)
                subtitle.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if unread {
                Circle().fill(.blue).frame(width: 7, height: 7).accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var subtitle: some View {
        switch status {
        case .blocked:
            HStack(spacing: 5) {
                Label("Blocked", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.black.opacity(0.75))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.yellow, in: Capsule())
                Text("Permission Required")
            }
        case .working, .responding:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(status == .working ? "Working" : "Responding")
            }
        case .failed:
            Text("Failed").foregroundStyle(.red)
        case .stopped:
            Text("Stopped")
        case .idle:
            Text(Self.relative(conversation.updated))
        }
    }

    /// "Today, 21:57", "Yesterday, 09:10", else the date with the time.
    static func relative(_ d: Date) -> String {
        let cal = Calendar.current, time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "Today, \(time)" }
        if cal.isDateInYesterday(d) { return "Yesterday, \(time)" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }
}
