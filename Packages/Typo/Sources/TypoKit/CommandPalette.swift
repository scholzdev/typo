import Foundation

/// One row of the command palette: a menu command as the palette sees it.
public struct PaletteEntry: Hashable, Sendable {
    /// Stable, e.g. "Format/Bold".
    public let id: String
    public let title: String
    /// The menu the command lives in, e.g. "Format"; also matched.
    public let menu: String
    public let isEnabled: Bool

    public init(id: String, title: String, menu: String, isEnabled: Bool = true) {
        self.id = id; self.title = title; self.menu = menu; self.isEnabled = isEnabled
    }
}

/// The command palette's search (⇧⌘P).
public enum CommandPalette {
    /// Enabled entries whose "menu title" contains every word of `query` (case- and diacritic-insensitive).
    /// Ranking: title has a word starting with the first query word, then other title matches, then menu-only matches;
    /// ties keep `recent` order first, then the given order. Empty query: recently used first, then the rest in the given order.
    public static func filter(_ entries: [PaletteEntry], query: String, recent: [String] = []) -> [PaletteEntry] {
        let enabled = entries.filter(\.isEnabled)
        let rank = Dictionary(recent.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        // (tier, recency, position): lower sorts first.
        var keyed: [(tier: Int, recency: Int, position: Int, entry: PaletteEntry)] = []
        for (position, entry) in enabled.enumerated() {
            let recency = rank[entry.id] ?? Int.max
            guard let first = words.first else { keyed.append((0, recency, position, entry)); continue }
            let title = fold(entry.title)
            let all = title + " " + fold(entry.menu)
            guard words.allSatisfy(all.contains) else { continue }
            let tier: Int
            if words.allSatisfy(title.contains) {
                tier = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(first) } ? 0 : 1
            } else {
                tier = 2
            }
            keyed.append((tier, recency, position, entry))
        }
        return keyed.sorted { ($0.tier, $0.recency, $0.position) < ($1.tier, $1.recency, $1.position) }.map(\.entry)
    }

    /// `recent` with `id` moved to the front, at most `limit` ids.
    public static func remember(_ id: String, in recent: [String], limit: Int = 8) -> [String] {
        Array(([id] + recent.filter { $0 != id }).prefix(max(limit, 0)))
    }

    private static func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
}
