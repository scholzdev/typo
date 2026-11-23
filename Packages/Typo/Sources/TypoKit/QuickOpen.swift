import Foundation
import TypstEngine

/// One thing Open Quickly (⇧⌘O) can open: a project file, a symbol of the project's files, a bookmark, or a Typst built-in.
public struct QuickOpenItem: Hashable, Sendable {
    public enum Kind: Hashable, Sendable, Codable {
        case file, heading(level: Int), label, function, variable, bibKey, builtin, bookmark(UUID)

        /// How much a text match of this kind counts: project symbols above built-ins, as in Xcode.
        var weight: Double {
            switch self {
            case .file: 1
            case .heading, .function, .bookmark: 0.95
            case .label: 0.9
            case .variable, .bibKey: 0.85
            case .builtin: 0.7
            }
        }
    }

    public let kind: Kind
    public let name: String
    /// Nil for a built-in.
    public let file: RelPath?
    /// What opening selects: the symbol's name in `file`; empty for files and built-ins.
    public let range: NSRange
    /// 1-based line of `range`; 0 for files and built-ins.
    public let line: Int
    /// The row's subtitle when not empty: a bookmark's line text.
    public let detail: String

    public init(kind: Kind, name: String, file: RelPath?, range: NSRange = NSRange(location: 0, length: 0), line: Int = 0, detail: String = "") {
        self.kind = kind; self.name = name; self.file = file; self.range = range; self.line = line; self.detail = detail
    }

    /// What the recents remember of a chosen item.
    public struct Identity: Codable, Hashable, Sendable {
        let kind: Kind, file: RelPath?, name: String, line: Int
        /// Without the line, which edits above the item change.
        var loose: Identity { Identity(kind: kind, file: file, name: name, line: 0) }
    }

    public var identity: Identity { Identity(kind: kind, file: file, name: name, line: line) }
}

/// A ranked row: the item, the characters of its name the query matched (for bold), and the same-named items it stands for.
public struct QuickOpenResult: Hashable, Sendable, Identifiable {
    public let item: QuickOpenItem
    public let matched: [NSRange]
    public var alternates: [QuickOpenItem] = []
    /// Set by a "file:line[:column]" query.
    public var line: Int?
    public var column: Int?
    let score: Double
    public var id: Self { self }

    /// The alternate `i` as a row of its own.
    public func alternate(_ i: Int) -> QuickOpenResult { QuickOpenResult(item: alternates[i], matched: matched, score: score) }
}

/// A row of the list: a result, or one of its alternates while its group is expanded.
public struct QuickOpenLine: Hashable, Sendable {
    public let result: Int
    public let alternate: Int?
}

/// Open Quickly's index and ranking (design/14h): subsequence matching like Xcode's.
public enum QuickOpen {
    static let limit = 200

    /// Every `items` whose name the query matches as a subsequence, best first. Text score × kind weight, plus a bonus
    /// of up to 15 for the items in `recent` (most recent first; see `QuickOpenRecents`) and the `open` files. Symbols of one name and kind
    /// collapse into one row with alternates. An empty query lists the recent items that still exist, then the `open`
    /// files. A "name:line[:column]" query puts the matching files at that line first.
    public static func results(_ query: String, items: [QuickOpenItem], recent: [QuickOpenItem.Identity], open: [RelPath] = []) -> [QuickOpenResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return recentItems(items, recent: recent, open: open).map { QuickOpenResult(item: $0, matched: [], score: 0) } }
        let rank = Dictionary(recent.enumerated().map { ($1.loose, $0) }, uniquingKeysWith: { a, _ in a })
        let tabs = Dictionary(open.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func scored(_ q: String, files only: Bool) -> [QuickOpenResult] {
            var out: [QuickOpenResult] = []
            for item in items where !only || item.kind == .file {
                var m = fuzzy(q, item.name)
                if m == nil, item.kind == .file, let f = item.file, let p = fuzzy(q, f.raw) { m = (p.score / 2, []) }
                guard let m else { continue }
                let chosen = rank[item.identity.loose].map { max(0, 15 - Double($0) / 2) } ?? 0
                let tab = item.kind == .file ? item.file.flatMap { tabs[$0] }.map { max(0, 15 - 3 * Double($0)) } ?? 0 : 0
                let bonus = max(chosen, tab)
                out.append(QuickOpenResult(item: item, matched: m.matched, score: m.score * item.kind.weight + bonus))
            }
            return out.sorted { ($0.score, -$0.item.name.utf16.count, $1.item.name) > ($1.score, -$1.item.name.utf16.count, $0.item.name) }
        }
        var located: [QuickOpenResult] = []
        if let loc = location(q) {
            located = scored(loc.query, files: true).prefix(10).map { var r = $0; r.line = loc.line; r.column = loc.column; return r }
        }
        var groups: [String: Int] = [:]
        var out: [QuickOpenResult] = []
        for r in scored(q, files: false) {
            if r.item.kind != .file {
                let key = "\(r.item.kind)\u{0}\(r.item.name)"
                if let i = groups[key] { out[i].alternates.append(r.item); continue }
                groups[key] = out.count
            }
            out.append(r)
            if out.count >= limit { break }
        }
        return located + out
    }

    /// The recent items that still exist (of several with one name, the one nearest the remembered line), then the
    /// `open` files not among them.
    static func recentItems(_ items: [QuickOpenItem], recent: [QuickOpenItem.Identity], open: [RelPath]) -> [QuickOpenItem] {
        let wanted = Set(recent.map(\.loose))
        let byKey = Dictionary(grouping: items.filter { wanted.contains($0.identity.loose) }, by: \.identity.loose)
        var out = recent.compactMap { r in byKey[r.loose]?.min { abs($0.line - r.line) < abs($1.line - r.line) } }
        out += open.map { QuickOpenItem(kind: .file, name: $0.name, file: $0) }
        var seen = Set<QuickOpenItem.Identity>()
        return out.filter { seen.insert($0.identity.loose).inserted }
    }

    /// The rows of `results` with the groups in `expanded` (result indices) showing their alternates.
    public static func rows(_ results: [QuickOpenResult], expanded: Set<Int>) -> [QuickOpenLine] {
        results.indices.flatMap { i in
            [QuickOpenLine(result: i, alternate: nil)] + (expanded.contains(i) ? results[i].alternates.indices.map { QuickOpenLine(result: i, alternate: $0) } : [])
        }
    }

    /// Scores `name` for `query` (spaces ignored, case-insensitive): nil unless every query character appears in order.
    /// Each matched character earns more at the start, at a word start (after a delimiter or a lower→upper step) and
    /// right after the previous match; a shorter name wins a tie. `matched`: UTF-16 runs of `name`.
    public static func fuzzy(_ query: String, _ name: String) -> (score: Double, matched: [NSRange])? {
        let q = query.utf16.filter { $0 != 32 }.map(fold)
        let raw = Array(name.utf16), n = raw.map(fold)
        let m = q.count, len = n.count
        guard m > 0, m <= len else { return nil }
        func bonus(_ j: Int) -> Int {
            if j == 0 { return 10 }
            let p = raw[j - 1]
            if !isWordUnit(p) { return 8 }
            if isUpper(raw[j]) && !isUpper(p) { return 7 }
            return 0
        }
        let none = Int.min / 2
        var score = [[Int]](repeating: [Int](repeating: none, count: len), count: m)
        var parent = [[Int]](repeating: [Int](repeating: -1, count: len), count: m)
        for i in 0..<m {
            var best = none, bestAt = -1             // the best of row i-1 at positions < j-1
            for j in i..<len {
                if i > 0, j >= 2, score[i - 1][j - 2] > best { best = score[i - 1][j - 2]; bestAt = j - 2 }
                guard n[j] == q[i] else { continue }
                if i == 0 { score[0][j] = 1 + bonus(j); continue }
                let run = score[i - 1][j - 1] > none ? score[i - 1][j - 1] + 6 : none
                let gap = best > none ? best - 1 : none
                guard max(run, gap) > none else { continue }
                score[i][j] = max(run, gap) + 1 + bonus(j)
                parent[i][j] = run >= gap ? j - 1 : bestAt
            }
        }
        guard let end = (0..<len).max(by: { score[m - 1][$0] < score[m - 1][$1] }), score[m - 1][end] > none else { return nil }
        var positions = [end]
        for i in stride(from: m - 1, to: 0, by: -1) { positions.append(parent[i][positions.last!]) }
        var matched: [NSRange] = []
        for p in positions.reversed() {
            if let last = matched.last, NSMaxRange(last) == p { matched[matched.count - 1].length += 1 } else { matched.append(NSRange(location: p, length: 1)) }
        }
        let exact = m == len ? 20 : 0
        return (Double(score[m - 1][end] + exact) - Double(len) / 10, matched)
    }

    private static func fold(_ u: UInt16) -> UInt16 {
        guard let s = Unicode.Scalar(u) else { return u }
        let l = s.properties.lowercaseMapping.utf16
        return l.count == 1 ? l.first! : u
    }
    private static func isUpper(_ u: UInt16) -> Bool { Unicode.Scalar(u)?.properties.isUppercase ?? false }
    private static func isWordUnit(_ u: UInt16) -> Bool { Unicode.Scalar(u).map { $0.properties.isAlphabetic || $0.properties.numericType != nil } ?? true }

    /// "main:42" or "main.typ:42:7": the file part and the position; nil unless the part after the last colon is a number.
    /// (Labels may hold colons, so "fig:intro" stays a name search.)
    public static func location(_ query: String) -> (query: String, line: Int, column: Int?)? {
        guard let m = query.wholeMatch(of: /(.+?):(\d+)(?::(\d+))?/), let line = Int(m.2), line > 0 else { return nil }
        return (String(m.1), line, m.3.flatMap { Int($0) })
    }

    /// Go to Line's input: "42", "42:7" (column), "+10" / "-10" (relative to `current`); nil when it is none of these.
    public static func lineTarget(_ input: String, current: Int) -> (line: Int, column: Int?)? {
        let s = input.trimmingCharacters(in: .whitespaces)
        if let m = s.wholeMatch(of: /([+-])(\d+)/), let d = Int(m.2) { return (max(1, m.1 == "+" ? current + d : current - d), nil) }
        guard let m = s.wholeMatch(of: /(\d+)(?::(\d+))?/), let line = Int(m.1), line > 0 else { return nil }
        return (line, m.2.flatMap { Int($0) })
    }

    /// What Go to Line selects: the whole line without its break, or a caret at `column` (1-based, clamped to the line).
    public static func range(ofLine line: Int, column: Int?, in text: String) -> NSRange {
        let ns = text as NSString
        let start = EditorLocation.offset(ofLine: line, in: text)
        var end = start
        while end < ns.length, ![10, 13].contains(ns.character(at: end)) { end += 1 }
        guard let column else { return NSRange(location: start, length: end - start) }
        return NSRange(location: min(start + max(column - 1, 0), end), length: 0)
    }

    /// Headings, label definitions, top-level `#let` functions and variables of `.typ` files, and bibliography keys.
    static func symbols(_ sources: [(file: RelPath, text: String)]) -> [QuickOpenItem] {
        var out: [QuickOpenItem] = []
        let starts = Dictionary(sources.map { ($0.file, lineStarts($0.text as NSString)) }, uniquingKeysWith: { a, _ in a })
        func item(_ kind: QuickOpenItem.Kind, _ name: String, _ file: RelPath, _ r: NSRange) -> QuickOpenItem {
            let line = (starts[file]?.lastIndex { $0 <= r.location } ?? 0) + 1
            return QuickOpenItem(kind: kind, name: name, file: file, range: r, line: line)
        }
        let labels = LabelIndex.build(sources)
        for (name, sites) in labels.definitions { out += sites.map { item(.label, name, $0.file, $0.name) } }
        for (name, sites) in labels.bibKeys { out += sites.map { item(.bibKey, name, $0.file, $0.name) } }
        for (file, text) in sources where FileKind.isTypst(file.raw) {
            let ns = text as NSString
            let mirror = SyntaxMirror(text)
            for c in Folding.candidates(ns) where mirror.spans(in: NSRange(location: c.marker, length: 1)).contains(where: { $0.tag == .heading && $0.range.location == c.marker }) {
                var start = c.marker + c.level
                while start < ns.length, [32, 9].contains(ns.character(at: start)) { start += 1 }
                let lineEnd = NSMaxRange(ns.lineRange(for: NSRange(location: start, length: 0)))
                let title = ns.substring(with: NSRange(location: start, length: lineEnd - start))
                    .replacing(/\s*<[^<>\s]+>\s*$/, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                out.append(item(.heading(level: c.level), title, file, NSRange(location: start, length: title.utf16.count)))
            }
            for d in Bridge.bindings(in: text).defs where d.top && (d.kind == "func" || d.kind == "let") && d.range.count == 2 {
                out.append(item(d.kind == "func" ? .function : .variable, d.name, file, NSRange(location: d.range[0], length: d.range[1] - d.range[0])))
            }
        }
        return out
    }

    /// One item per bookmark, named as the navigator names it, with its line's text from `snippets` underneath.
    static func bookmarks(_ bookmarks: [CodeBookmark], snippets: [UUID: String]) -> [QuickOpenItem] {
        bookmarks.map { QuickOpenItem(kind: .bookmark($0.id), name: $0.displayTitle, file: $0.path, line: $0.isFile ? 0 : $0.line + 1, detail: snippets[$0.id] ?? "") }
    }

    /// The Typst functions and syntax of the bundled reference (`TypstDocs`), opening in the docs panel.
    public static let builtins: [QuickOpenItem] = TypstDocs.all.map { QuickOpenItem(kind: .builtin, name: $0.name, file: nil) }

    private static func lineStarts(_ ns: NSString) -> [Int] {
        var out = [0]
        for i in 0..<ns.length where ns.character(at: i) == 10 { out.append(i + 1) }
        return out
    }

    /// Paths whose text contains every word of `query` (case-insensitive); name matches come before folder matches,
    /// otherwise the given order stays.
    public static func filter(paths: [RelPath], query: String) -> [RelPath] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return paths }
        let hits = paths.filter { p in let s = p.raw.lowercased(); return words.allSatisfy(s.contains) }
        let inName = hits.filter { p in let n = p.name.lowercased(); return words.allSatisfy(n.contains) }
        return inName + hits.filter { !inName.contains($0) }
    }
}

extension TypstDocs {
    /// The bundled entry `name` as the docs panel shows it: the description and the example.
    public static func doc(_ name: String) -> (doc: BuiltinDoc, signature: String)? {
        guard let e = all.first(where: { $0.name == name }) else { return nil }
        return (BuiltinDoc(name: e.name, docs: "\(e.about)\n\n```typst\n\(e.example)\n```", url: nil), e.signature)
    }
}

extension Project {
    /// Open Quickly's items: the file tree's files, the symbols of its Typst and bibliography files (open buffers'
    /// unsaved text wins over disk), the bookmarks, and the built-ins.
    public func quickOpenItems() async -> [QuickOpenItem] {
        let files = allFiles.map { QuickOpenItem(kind: .file, name: $0.name, file: $0) }
        let sources = textSources { FileKind.isTypst($0) || BibliographyFile.isBibliography($0) }
        let marks = QuickOpen.bookmarks(sortedBookmarks, snippets: await bookmarkSnippets())
        return await files + Self.buildSymbols(sources) + marks + QuickOpen.builtins
    }

    @concurrent private static func buildSymbols(_ sources: [SearchSource]) async -> [QuickOpenItem] {
        QuickOpen.symbols(sources.compactMap(\.loaded))
    }

    /// Opens `file` with `line` selected (or the caret at `column`), from the open buffer's text or else the disk's.
    public func showLine(_ file: RelPath, line: Int, column: Int?) {
        guard let text = buffers[file]?.storage.string ?? (try? String(contentsOf: url(for: file), encoding: .utf8)) else { return }
        show(file, range: QuickOpen.range(ofLine: line, column: column, in: text), flash: true)
    }
}

/// Stores the Open Quickly results chosen in one project under "Tympan.quickOpenRecents.<project id>", most recent first.
public struct QuickOpenRecents: Sendable {
    static let limit = 30
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String

    public init(_ id: ProjectID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // persisted key, kept from the app's old name so saved data survives
        key = "Tympan.quickOpenRecents.\(id.raw)"
    }

    public func load() -> [QuickOpenItem.Identity] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([QuickOpenItem.Identity].self, from: $0) } ?? []
    }

    /// Puts `item` first, in place of an older entry for it; returns the new list.
    @discardableResult public func record(_ item: QuickOpenItem) -> [QuickOpenItem.Identity] {
        let new = Array(([item.identity] + load().filter { $0.loose != item.identity.loose }).prefix(Self.limit))
        defaults.set(try? JSONEncoder().encode(new), forKey: key)
        return new
    }

    public func clear() { defaults.removeObject(forKey: key) }
}
