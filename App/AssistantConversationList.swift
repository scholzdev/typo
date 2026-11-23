import SwiftUI
import TypoKit
import TypoAssistant

/// The sidebar in assistant mode: New Conversation, the conversations by date, and a collapsible Archive.
struct AssistantConversationList: View {
    @Bindable var model: AssistantModel
    @State private var showsArchive = false
    @State private var renaming: AssistantConversation?
    @State private var newTitle = ""
    @State private var deleting: AssistantConversation?

    var body: some View {
        let active = model.conversations.filter { !$0.archived }
        let archived = model.conversations.filter(\.archived)
        List(selection: Binding(get: { model.currentID }, set: { if let id = $0 { model.select(id) } })) {
            ForEach(Self.groups(active), id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { row($0) }
                }
            }
            if !archived.isEmpty {
                Section(isExpanded: $showsArchive) {
                    ForEach(archived) { row($0) }
                } header: {
                    Text("Archive")
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.conversations.isEmpty {
                ContentUnavailableView("No Conversations", systemImage: "sparkles", description: Text("Ask about your document to start one."))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Button { model.newConversation() } label: {
                Label("New Conversation", systemImage: "square.and.pencil").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .help("Starts a new conversation with the assistant")
        }
        .alert("Rename Conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") { if let c = renaming { model.rename(c.id, to: newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let c = deleting { model.delete(c.id) } }
        } message: {
            Text("The conversation is removed from this Mac. This cannot be undone.")
        }
    }

    private func row(_ c: AssistantConversation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(c.title).lineLimit(1)
            Text(c.updated, format: Calendar.current.isDateInToday(c.updated) ? .dateTime.hour().minute() : .dateTime.day().month().hour().minute())
                .font(.caption).foregroundStyle(.secondary)
        }
        .tag(c.id)
        .contextMenu {
            Button("Rename…") { newTitle = c.title; renaming = c }
            Button(c.archived ? "Unarchive" : "Archive") { model.setArchived(c.id, !c.archived) }
            Divider()
            Button("Delete…", role: .destructive) { deleting = c }
        }
    }

    private struct DateGroup { let title: String; let items: [AssistantConversation] }

    /// Today, Yesterday, Previous 7 Days, Older; newest first within each.
    private static func groups(_ items: [AssistantConversation]) -> [DateGroup] {
        let cal = Calendar.current
        func title(_ d: Date) -> String {
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInYesterday(d) { return "Yesterday" }
            if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: .now)).day, days < 7 { return "Previous 7 Days" }
            return "Older"
        }
        let sorted = items.sorted { $0.updated > $1.updated }
        var out: [DateGroup] = []
        for c in sorted {
            let t = title(c.updated)
            if out.last?.title == t { out[out.count - 1] = DateGroup(title: t, items: out[out.count - 1].items + [c]) } else { out.append(DateGroup(title: t, items: [c])) }
        }
        return out
    }
}

/// The sidebar in assistant mode, as in Xcode: the chat itself, with the conversations behind a button above it.
struct AssistantSidebar: View {
    @Bindable var model: AssistantModel
    @State private var showsList = false
    @State private var showsPermissions = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { showsList.toggle() } label: {
                    HStack(spacing: 4) {
                        Text(model.current?.title ?? "New Conversation").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show all conversations")
                .popover(isPresented: $showsList, arrowEdge: .bottom) {
                    AssistantConversationList(model: model).frame(width: 300, height: 420)
                }
                Spacer()
                Button("Permissions", systemImage: "checkmark.shield") { showsPermissions.toggle() }
                    .buttonStyle(.borderless).labelStyle(.iconOnly)
                    .help("What the assistant may do in this conversation")
                    .popover(isPresented: $showsPermissions, arrowEdge: .bottom) { AssistantPermissionsPopover(model: model) }
                Button("New Conversation", systemImage: "square.and.pencil") { model.newConversation() }
                    .buttonStyle(.borderless).labelStyle(.iconOnly)
                    .help("Starts a new conversation with the assistant")
            }
            .padding(.horizontal, 12).frame(height: 30)
            AssistantChatView(model: model)
        }
        .onChange(of: model.currentID) { showsList = false }
    }
}
