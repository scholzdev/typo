import Foundation
import TypoKit
import TypstEngine

/// How the sidebar arranges one project's conversations: named groups, the order of the ungrouped ones, which are
/// unread, and which disclosures are open. Archived conversations keep their place here; the list shows them under Archive.
public struct AssistantConversationLayout: Codable, Equatable, Sendable {
    public struct Group: Codable, Equatable, Identifiable, Sendable {
        public var id = UUID()
        public var name: String
        public var items: [UUID]
        public var expanded = true
        public init(name: String, items: [UUID]) { self.name = name; self.items = items }
    }

    public var groups: [Group] = []
    /// The conversations outside any group, as listed.
    public var order: [UUID] = []
    public var unread: Set<UUID> = []
    public var archiveExpanded = false

    public init() {}

    /// The group holding `id`, if any.
    public func group(of id: UUID) -> UUID? { groups.first { $0.items.contains(id) }?.id }

    /// Drops ids that no longer exist and puts the new ones on top, newest first as `ids` lists them.
    public mutating func reconcile(_ ids: [UUID]) {
        let known = Set(ids)
        order.removeAll { !known.contains($0) }
        for i in groups.indices { groups[i].items.removeAll { !known.contains($0) } }
        unread.formIntersection(known)
        let placed = Set(order).union(groups.flatMap(\.items))
        order.insert(contentsOf: ids.filter { !placed.contains($0) }, at: 0)
    }

    /// A new conversation goes on top of the ungrouped ones.
    public mutating func add(_ id: UUID) {
        remove(id)
        order.insert(id, at: 0)
    }

    public mutating func remove(_ id: UUID) {
        order.removeAll { $0 == id }
        for i in groups.indices { groups[i].items.removeAll { $0 == id } }
        unread.remove(id)
    }

    /// A new group on top holding `items` (taken from wherever they were); returns its id.
    @discardableResult public mutating func newGroup(named name: String, with items: [UUID] = []) -> UUID {
        for id in items {
            order.removeAll { $0 == id }
            for i in groups.indices { groups[i].items.removeAll { $0 == id } }
        }
        let g = Group(name: name, items: items)
        groups.insert(g, at: 0)
        return g.id
    }

    public mutating func renameGroup(_ id: UUID, to name: String) {
        let t = name.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].name = t
    }

    /// The group goes; its conversations return to the top of the ungrouped ones.
    public mutating func deleteGroup(_ id: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        order.insert(contentsOf: groups.remove(at: i).items, at: 0)
    }

    /// Moves `id` into `group` (nil: ungrouped) before the conversation `before`, or to the end.
    public mutating func move(_ id: UUID, to group: UUID?, before: UUID? = nil) {
        guard id != before else { return }
        if let group, !groups.contains(where: { $0.id == group }) { return }
        order.removeAll { $0 == id }
        for i in groups.indices { groups[i].items.removeAll { $0 == id } }
        func insert(_ list: inout [UUID]) {
            if let before, let at = list.firstIndex(of: before) { list.insert(id, at: at) } else { list.append(id) }
        }
        if let group, let i = groups.firstIndex(where: { $0.id == group }) { insert(&groups[i].items) } else { insert(&order) }
    }

    public mutating func setExpanded(_ group: UUID, _ expanded: Bool) {
        if let i = groups.firstIndex(where: { $0.id == group }) { groups[i].expanded = expanded }
    }
}

/// Stores a project's layout under "Tympan.conversations.<project id>", like the bookmarks.
public struct AssistantConversationLayoutStore: Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String

    public init(_ id: ProjectID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "Tympan.conversations.\(id.raw)"
    }

    public func load() -> AssistantConversationLayout {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AssistantConversationLayout.self, from: $0) } ?? AssistantConversationLayout()
    }

    public func save(_ layout: AssistantConversationLayout) {
        if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: key) }
    }
}

/// What a conversation is doing, for its row in the sidebar. Only the running turn's conversation is ever more than idle,
/// failed or stopped.
public enum AssistantConversationStatus: Equatable, Sendable {
    case idle, working, planning, responding, blocked, failed, stopped

    /// `running`: its turn streams; `blocked`: a permission waits; `planning`: see `AssistantPlan.isPlanning`;
    /// `answering`: answer text arrives; `failed` / `stopped`: how its last turn ended.
    public static func of(running: Bool, blocked: Bool, planning: Bool = false, answering: Bool, failed: Bool, stopped: Bool) -> Self {
        if running { return blocked ? .blocked : planning ? .planning : answering ? .responding : .working }
        return failed ? .failed : stopped ? .stopped : .idle
    }
}
