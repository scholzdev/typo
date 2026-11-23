import Foundation
import Observation

/// A snippet the user wrote in the Settings; `body` is in `Snippet` syntax (`${1:name}`, `${0}`, mirrored numbers).
public struct UserSnippet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var summary: String
    /// Completion trigger, may be empty.
    public var prefix: String
    public var body: String
    /// Goes on its own lines rather than inline at the caret.
    public var isBlock: Bool

    public init(id: UUID = UUID(), title: String = "New Snippet", summary: String = "", prefix: String = "", body: String = "", isBlock: Bool = true) {
        self.id = id; self.title = title; self.summary = summary; self.prefix = prefix; self.body = body; self.isBlock = isBlock
    }

    /// The library entry (category "User").
    public var librarySnippet: LibrarySnippet {
        LibrarySnippet(id: Self.libraryID(id), title: title.isEmpty ? "Untitled" : title, summary: summary, category: Self.category,
                       symbol: "curlybraces", apply: body, isBlock: isBlock)
    }

    public static let category = "User"
    public static func libraryID(_ id: UUID) -> String { "user-\(id.uuidString)" }
}

/// The user's snippets, saved as JSON in UserDefaults.
@MainActor @Observable public final class UserSnippetStore {
    public static let category = UserSnippet.category
    public static let defaultsKey = "userSnippets"
    public static let shared = UserSnippetStore()

    public private(set) var snippets: [UserSnippet]
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snippets = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode([UserSnippet].self, from: $0) } ?? []
    }

    @discardableResult public func add(_ snippet: UserSnippet = UserSnippet()) -> UserSnippet {
        snippets.append(snippet)
        save()
        return snippet
    }

    public func update(_ snippet: UserSnippet) {
        guard let i = snippets.firstIndex(where: { $0.id == snippet.id }), snippets[i] != snippet else { return }
        snippets[i] = snippet
        save()
    }

    public func delete(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    public func librarySnippet(for snippet: UserSnippet) -> LibrarySnippet { snippet.librarySnippet }

    /// The library entry for an id like "user-<uuid>".
    public func librarySnippet(withID id: String) -> LibrarySnippet? { snippets.first { UserSnippet.libraryID($0.id) == id }?.librarySnippet }

    /// Snippets whose non-empty prefix starts with `typed` (case-insensitive), exact matches first.
    public func completions(matching typed: String) -> [UserSnippet] {
        let t = typed.lowercased()
        guard !t.isEmpty else { return [] }
        let hits = snippets.filter { !$0.prefix.isEmpty && $0.prefix.lowercased().hasPrefix(t) }
        return hits.filter { $0.prefix.lowercased() == t } + hits.filter { $0.prefix.lowercased() != t }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snippets) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
