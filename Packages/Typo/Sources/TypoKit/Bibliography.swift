import Foundation
import TypstEngine

/// One bibliography file of the project: its entries, or the parse error instead.
public struct BibFile: Identifiable, Sendable, Equatable {
    public let id: RelPath
    public let entries: [BibEntry]
    public let error: String?
}

public enum BibliographyFile {
    /// `.bib` and hayagriva `.yml`/`.yaml`.
    public static func isBibliography(_ path: String) -> Bool { ["bib", "yml", "yaml"].contains((path as NSString).pathExtension.lowercased()) }

    static func parse(_ file: RelPath, text: String) -> BibFile {
        let r = Bridge.bibliography(text, yaml: !file.raw.lowercased().hasSuffix(".bib"))
        return BibFile(id: file, entries: r.entries, error: r.error)
    }

    /// What a click inserts at a caret in `mode`: `@key` in markup, `cite(<key>)` in code (and math).
    /// Inside a string, raw or comment, the plain `@key`.
    public static func citation(_ key: String, mode: SyntaxMode) -> String {
        switch mode {
        case .code, .math: "cite(<\(key)>)"
        case .markup, .text: "@\(key)"
        }
    }

    /// Several citations in one go: `@a @b`, or `cite(<a>), cite(<b>)` in code, where juxtaposition is not valid.
    public static func citations(_ keys: [String], mode: SyntaxMode) -> String {
        keys.map { citation($0, mode: mode) }.joined(separator: mode == .code ? ", " : " ")
    }
}

extension BibEntry {
    /// The References tab's and the citation picker's filter; an empty query matches everything.
    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || [key, title, authors, year.map(String.init) ?? "", kind].contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// "Authors (Year): Title", the parts that exist.
    var completionDetail: String {
        let who = authors.isEmpty ? "" : authors + (year == nil ? "" : " ")
        let head = who + (year.map { "(\($0))" } ?? "")
        return [head, title].filter { !$0.isEmpty }.joined(separator: ": ")
    }
}

extension Project {
    /// Label items that are bibliography keys get "Authors (Year): Title" instead of typst-ide's bare title.
    /// The parse is cached per `bibliographyRevision`.
    func enrichedWithBibliography(_ items: [CompletionItem]) async -> [CompletionItem] {
        guard items.contains(where: { $0.kind == .label }) else { return items }
        if bibIndex?.revision != bibliographyRevision {
            let revision = bibliographyRevision
            let entries = await references().flatMap(\.entries)
            bibIndex = (revision, Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        guard let index = bibIndex?.entries, !index.isEmpty else { return items }
        return items.map { item in
            guard item.kind == .label, let e = index[item.label] else { return item }
            return CompletionItem(kind: .label, label: item.label, apply: item.apply, detail: e.completionDetail)
        }
    }
}
