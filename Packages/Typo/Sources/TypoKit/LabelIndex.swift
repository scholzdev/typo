import Foundation
import TypstEngine

public struct LabelSite: Sendable, Hashable {
    public let file: RelPath
    /// The whole token: `<intro>` or `@intro`, or the bibliography key itself.
    public let token: NSRange
    /// Only the name inside the token.
    public let name: NSRange
}

public enum LabelKind: Sendable { case definition, reference, bibKey }

public struct LabelHit: Sendable, Equatable {
    public let name: String
    public let kind: LabelKind
    public let site: LabelSite
}

/// Every label definition (`<x>`), reference (`@x`) and bibliography key of a project's text files.
public struct LabelIndex: Sendable {
    public private(set) var definitions: [String: [LabelSite]] = [:]
    public private(set) var references: [String: [LabelSite]] = [:]
    public private(set) var bibKeys: [String: [LabelSite]] = [:]

    /// Files in the given order; each text is the open buffer's if any, else disk (the caller decides).
    public static func build(_ sources: [(file: RelPath, text: String)]) -> LabelIndex {
        var index = LabelIndex()
        for (file, text) in sources {
            if FileKind.isTypst(file.raw) { index.scanTypst(file, text) }
            else if BibliographyFile.isBibliography(file.raw) { index.scanBib(file, text) }
        }
        return index
    }

    public static func isValidName(_ s: String) -> Bool { !s.isEmpty && s.unicodeScalars.allSatisfy(isNameScalar) }

    private static func isNameScalar(_ c: Unicode.Scalar) -> Bool {
        CharacterSet.alphanumerics.contains(c) || "_-.:".unicodeScalars.contains(c)
    }

    private mutating func scanTypst(_ file: RelPath, _ text: String) {
        let ns = text as NSString
        let mirror = SyntaxMirror(text)
        for t in mirror.spans(in: NSRange(location: 0, length: ns.length)) {
            switch t.tag {
            case .label where t.range.length > 2:
                let site = LabelSite(file: file, token: t.range, name: NSRange(location: t.range.location + 1, length: t.range.length - 2))
                let name = ns.substring(with: site.name)
                // Markup attaches a label; in code (`#cite(<k>)`, `#show <k>: …`, `#let l = <k>`) it names a target.
                if mirror.mode(at: t.range.location + 1) == .code { references[name, default: []].append(site) } else { definitions[name, default: []].append(site) }
            case .ref where ns.substring(with: t.range).hasPrefix("@"):
                // A supplement's text is tagged `.ref` too; only spans that start with `@` are references.
                var n = 1
                while t.range.location + n < NSMaxRange(t.range), Self.isNameScalar(Unicode.Scalar(ns.character(at: t.range.location + n)) ?? " ") { n += 1 }
                while n > 1, [".", ":"].contains(ns.substring(with: NSRange(location: t.range.location + n - 1, length: 1))) { n -= 1 }
                guard n > 1 else { continue }
                let site = LabelSite(file: file, token: NSRange(location: t.range.location, length: n), name: NSRange(location: t.range.location + 1, length: n - 1))
                references[ns.substring(with: site.name), default: []].append(site)
            case .string where t.range.length > 2:
                // `label("x")`: a label by string. `#label("x")` in markup attaches one; anywhere else it names a target. (`ref("x")` is a type error.)
                let at = t.range.location
                guard at >= 6, ns.substring(with: NSRange(location: at - 6, length: 6)) == "label(" else { continue }
                let lead = at >= 7 ? ns.character(at: at - 7) : 0
                guard !(Unicode.Scalar(lead).map { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" } ?? false) else { continue }
                let site = LabelSite(file: file, token: t.range, name: NSRange(location: at + 1, length: t.range.length - 2))
                let name = ns.substring(with: site.name)
                guard !name.contains("\\") else { continue }
                if lead == 35 { definitions[name, default: []].append(site) } else { references[name, default: []].append(site) }
            default: break
            }
        }
    }

    private static let bibtexKey = try! NSRegularExpression(pattern: #"^[ \t]*@(?!comment\b|string\b|preamble\b)\w+[ \t\r\n]*[{(][ \t\r\n]*([^,\s{}()]+)[ \t]*,"#, options: [.anchorsMatchLines, .caseInsensitive])
    private static let yamlKey = try! NSRegularExpression(pattern: #"^([^\s#\-:'"][^\s:]*):(?:\s|$)"#, options: [.anchorsMatchLines])

    private mutating func scanBib(_ file: RelPath, _ text: String) {
        let ns = text as NSString
        let re = file.raw.lowercased().hasSuffix(".bib") ? Self.bibtexKey : Self.yamlKey
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let r = m.range(at: 1)
            bibKeys[ns.substring(with: r), default: []].append(LabelSite(file: file, token: r, name: r))
        }
    }

    /// The label, reference or bibliography key under `offset` (the end of a token counts).
    public func hit(in file: RelPath, at offset: Int) -> LabelHit? {
        func find(_ table: [String: [LabelSite]], _ kind: LabelKind) -> LabelHit? {
            for (name, sites) in table {
                if let s = sites.first(where: { $0.file == file && $0.token.location <= offset && offset <= NSMaxRange($0.token) }) { return LabelHit(name: name, kind: kind, site: s) }
            }
            return nil
        }
        return find(definitions, .definition) ?? find(references, .reference) ?? find(bibKeys, .bibKey)
    }

    /// Where `name` is defined: its first label (with how many there are), else its bibliography entry.
    public func target(of name: String) -> (site: LabelSite, count: Int)? {
        if let d = definitions[name], let first = d.first { return (first, d.count) }
        if let b = bibKeys[name], let first = b.first { return (first, b.count) }
        return nil
    }

    /// What renaming `name` touches: the label definitions, or else the bibliography keys, plus every reference.
    public func renameSites(of name: String) -> (defs: [LabelSite], refs: [LabelSite]) {
        let defs = definitions[name].map { $0 } ?? bibKeys[name] ?? []
        return (defs, references[name] ?? [])
    }

    public func renameSummary(of name: String) -> String {
        let (d, r) = renameSites(of: name)
        let files = Set((d + r).map(\.file)).count
        func n(_ k: Int, _ s: String) -> String { "\(k) \(s)\(k == 1 ? "" : "s")" }
        return "\(n(d.count, d.count == 0 || definitions[name] != nil ? "definition" : "key")) and \(n(r.count, "reference")) in \(n(files, "file"))"
    }

    /// A message when `new` cannot replace `old`; nil when it can.
    public func validate(_ new: String, replacing old: String) -> String? {
        if new.isEmpty { return "The name can't be empty." }
        if !Self.isValidName(new) { return "Use letters, digits, _ - . or : only." }
        if new == old { return "That is the current name." }
        if definitions[new] != nil || bibKeys[new] != nil { return "“\(new)” is already used." }
        return nil
    }

    /// Replacements, per file, that turn every definition and reference of `old` into `new`.
    public func rename(_ old: String, to new: String) -> [RelPath: [Replacement]] {
        let (d, r) = renameSites(of: old)
        var out: [RelPath: [Replacement]] = [:]
        for s in d + r { out[s.file, default: []].append(Replacement(range: s.name, text: new)) }
        return out
    }
}

public struct TodoItem: Sendable, Equatable, Identifiable {
    public let file: RelPath
    /// The marker through the end of its comment line.
    public let range: NSRange
    public let marker: String
    public let text: String
    public let line: Int
    public var id: String { "\(file.raw):\(range.location)" }
}

public enum TodoScan {
    static let marker = try! NSRegularExpression(pattern: #"\b(TODO|FIXME|XXX)\b"#)

    public static func items(in file: RelPath, text: String) -> [TodoItem] {
        let ns = text as NSString
        var out: [TodoItem] = []
        var line = 1, counted = 0
        for t in TypstSyntax.tokens(in: text) where t.tag == .comment {
            for m in marker.matches(in: text, range: t.range) {
                var contentsEnd = 0
                ns.getLineStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: m.range.location, length: 0))
                let r = NSRange(location: m.range.location, length: min(contentsEnd, NSMaxRange(t.range)) - m.range.location)
                var body = ns.substring(with: NSRange(location: NSMaxRange(m.range), length: max(0, NSMaxRange(r) - NSMaxRange(m.range))))
                if body.hasSuffix("*/"), ns.substring(with: t.range).hasPrefix("/*") { body.removeLast(2) }
                body = body.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
                for i in counted..<m.range.location where ns.character(at: i) == 10 { line += 1 }
                counted = m.range.location
                out.append(TodoItem(file: file, range: r, marker: ns.substring(with: m.range), text: body, line: line))
            }
        }
        return out
    }
}

extension Project {
    func textSources(where keep: (String) -> Bool) -> [SearchSource] {
        allFiles.filter { keep($0.raw) }.map { f in buffers[f].map { SearchSource.text(f, $0.storage.string) } ?? .disk(f, url(for: f)) }
    }

    /// Labels, references and bibliography keys of the whole project; open buffers' unsaved text wins over disk.
    public func labelIndex() async -> LabelIndex {
        let sources = textSources { FileKind.isTypst($0) || BibliographyFile.isBibliography($0) }
        return await Self.buildIndex(sources)
    }

    @concurrent private static func buildIndex(_ sources: [SearchSource]) async -> LabelIndex {
        LabelIndex.build(sources.compactMap(\.loaded))
    }

    /// TODO, FIXME and XXX comments of every `.typ` file. `cache` (text and items per file, returned updated)
    /// lets unchanged files skip the parse.
    public func todos(cache: [RelPath: TodoCacheEntry]) async -> (items: [TodoItem], cache: [RelPath: TodoCacheEntry]) {
        await Self.scanTodos(textSources { FileKind.isTypst($0) }, cache)
    }

    @concurrent private static func scanTodos(_ sources: [SearchSource], _ cache: [RelPath: TodoCacheEntry]) async -> (items: [TodoItem], cache: [RelPath: TodoCacheEntry]) {
        var next: [RelPath: TodoCacheEntry] = [:]
        var items: [TodoItem] = []
        for (file, text) in sources.compactMap(\.loaded) {
            let entry = cache[file].flatMap { $0.text == text ? $0 : nil } ?? TodoCacheEntry(text: text, items: TodoScan.items(in: file, text: text))
            next[file] = entry
            items += entry.items
        }
        return (items, next)
    }
}

public struct TodoCacheEntry: Sendable { let text: String; let items: [TodoItem] }

extension SearchSource {
    var loaded: (file: RelPath, text: String)? {
        switch self {
        case .text(let f, let t): return (f, t)
        case .disk(let f, let url): return (try? String(contentsOf: url, encoding: .utf8)).map { (f, $0) }
        }
    }
}
