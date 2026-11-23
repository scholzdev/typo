import Foundation
import Observation
import TypstEngine

public enum SymbolCatalog {
    /// Static: the same list for every project.
    public static let all: [TypstSymbol] = Bridge.symbols()

    /// What a click inserts at a caret in `mode`: math `alpha`, markup `#sym.alpha`, code `sym.alpha` (emoji
    /// likewise with `emoji.`). Inside a string, raw or comment the character itself.
    public static func insertion(for s: TypstSymbol, mode: SyntaxMode) -> String {
        let path = s.id
        return switch mode {
        case .math: s.isEmoji ? path : s.name
        case .markup: "#" + path
        case .code: path
        case .text: s.text
        }
    }

    /// `recent` ids first (most recent first), then the rest in catalog order; a query keeps names containing it
    /// and symbols whose character is the query.
    public static func filter(_ list: [TypstSymbol], query: String, recent: [String]) -> [TypstSymbol] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = q.isEmpty ? list : list.filter { $0.name.lowercased().contains(q) || $0.text == query }
        let rank = Dictionary(recent.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return hits.enumerated().sorted { a, b in
            switch (rank[a.element.id], rank[b.element.id]) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            default: a.offset < b.offset
            }
        }.map(\.element)
    }
}

/// Recently inserted symbol ids, most recent first, persisted in UserDefaults.
@MainActor @Observable public final class RecentSymbols {
    public private(set) var ids: [String]
    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "TypstCore.recentSymbols"
    static let capacity = 40

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = defaults.stringArray(forKey: Self.key) ?? []
    }

    public func use(_ s: TypstSymbol) {
        ids.removeAll { $0 == s.id }
        ids.insert(s.id, at: 0)
        if ids.count > Self.capacity { ids.removeLast(ids.count - Self.capacity) }
        defaults.set(ids, forKey: Self.key)
    }
}
