import Foundation
import TypstEngine

/// Completion inside a table cell, where there is no file and no engine: `@` offers labels and bibliography
/// keys, `#` offers the project's `#let` and imported names.
public struct CellCompletion: Sendable {
    public struct Request: Sendable, Equatable {
        public let trigger: Character          // "@" or "#"
        public let range: NSRange              // the typed name after the trigger, UTF-16
        public let typed: String
    }

    var labels: [String: String] = [:]         // label -> where it is defined
    var entries: [String: String] = [:]        // bibliography key -> "Authors (Year): Title" (may be empty)
    var names: [String] = []                   // in scope in the table's file
    /// Names defined by `#let` in other files, with the file to import them from.
    public private(set) var importable: [String: RelPath] = [:]

    public init() {}

    /// Only what the document can reach: labels of the files `main` includes or imports (directly or not), keys of the
    /// bibliographies those files load, and the names of `file` itself. Other files' `#let` names come with an import.
    public init(labels: LabelIndex, bibliography: [BibFile], sources: [(file: RelPath, text: String)], main: RelPath, file: RelPath?) {
        let text = Dictionary(sources.map { ($0.file, $0.text) }, uniquingKeysWith: { a, _ in a })
        let reachable = Self.reachable(from: main, text: text)
        let bibs = Set(reachable.flatMap { f in Self.bibliographies(in: text[f] ?? "").compactMap { Self.resolve($0, from: f) } })
        for (name, sites) in labels.definitions {
            if let site = sites.first(where: { reachable.contains($0.file) }) { self.labels[name] = "<\(name)> in \(site.file.raw)" }
        }
        for (key, sites) in labels.bibKeys where sites.contains(where: { bibs.contains($0.file) }) { entries[key] = "" }
        for f in bibliography where bibs.contains(f.id) { for e in f.entries { entries[e.key] = e.completionDetail } }
        let own = Set(file.flatMap { text[$0] }.map { Self.letNames(in: $0) } ?? [])
        names = own.sorted()
        for (f, t) in text where f != file && FileKind.isTypst(f.raw) {
            for n in Self.letNames(in: t, importsToo: false) where !own.contains(n) && importable[n] == nil { importable[n] = f }
        }
    }

    /// Files reached from `main` through `#include` and `#import` of a quoted path.
    public static func reachable(from main: RelPath, text: [RelPath: String]) -> Set<RelPath> {
        var seen: Set<RelPath> = [main], queue = [main]
        while let f = queue.popLast() {
            for m in (text[f] ?? "").matches(of: /#(?:include|import)\s+"([^"\n]+)"/) {
                guard let target = resolve(String(m.1), from: f), !seen.contains(target) else { continue }
                seen.insert(target)
                queue.append(target)
            }
        }
        return seen
    }

    /// The quoted paths of `bibliography(...)` calls: one path or an array of them.
    // shortcut: a path held in a variable is not followed; upgrade with the syntax tree if that matters.
    static func bibliographies(in text: String) -> [String] {
        text.matches(of: /bibliography\(\s*(\([^)]*\)|"[^"\n]*")/).flatMap { m in String(m.1).matches(of: /"([^"\n]+)"/).map { String($0.1) } }
    }

    /// A Typst path as written in `from`: "/x" is from the project root, anything else from `from`'s folder.
    static func resolve(_ path: String, from: RelPath) -> RelPath? {
        guard !path.hasPrefix("@") else { return nil }          // a package
        var parts = path.hasPrefix("/") ? [] : (from.parent?.raw.split(separator: "/").map(String.init) ?? [])
        for p in path.split(separator: "/") {
            if p == "." { continue }
            if p == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() } else { parts.append(String(p)) }
        }
        return RelPath(parts.joined(separator: "/"))
    }

    /// The path to write in `from` to reach `target`.
    public static func relativePath(to target: RelPath, from: RelPath) -> String {
        let base = from.parent?.raw.split(separator: "/").map(String.init) ?? []
        let goal = target.raw.split(separator: "/").map(String.init)
        var common = 0
        while common < base.count, common < goal.count - 1, base[common] == goal[common] { common += 1 }
        return (Array(repeating: "..", count: base.count - common) + goal[common...]).joined(separator: "/")
    }

    /// Where new imports go: after the file's last `#import` line at line start, else at the very top.
    public static func importInsertionPoint(in text: String) -> Int {
        guard let last = text.matches(of: /(?m)^#import[^\n]*\n?/).last else { return 0 }
        return text.utf16.distance(from: text.utf16.startIndex, to: last.range.upperBound.samePosition(in: text.utf16) ?? text.utf16.endIndex)
    }

    /// `#import` lines `file` needs for the `#name`s in `cells` that it does not define or import itself.
    public func missingImports(cells: [String], file: RelPath) -> String {
        let used = Set(cells.flatMap { $0.matches(of: /#([\p{L}_][\p{L}\p{N}_-]*)/).map { String($0.1) } })
        let need = Dictionary(grouping: used.filter { !names.contains($0) && importable[$0] != nil }, by: { importable[$0]! })
        return need.keys.sorted { $0.raw < $1.raw }.map { f in
            "#import \"\(Self.relativePath(to: f, from: file))\": \(need[f]!.sorted().joined(separator: ", "))\n"
        }.joined()
    }

    /// The trigger and name typed just before `caret` (UTF-16), or nil when the caret is not in one.
    public static func request(in text: String, caret: Int) -> Request? {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return nil }
        func scalar(_ i: Int) -> Unicode.Scalar { Unicode.Scalar(ns.character(at: i)) ?? " " }
        var start = caret
        while start > 0, isName(scalar(start - 1), allowing: ".:") { start -= 1 }
        guard start > 0 else { return nil }
        let trigger = scalar(start - 1)
        guard trigger == "@" || trigger == "#" else { return nil }
        if trigger == "#", ns.substring(with: NSRange(location: start, length: caret - start)).contains(where: { ".:".contains($0) }) { return nil }
        if start > 1, CharacterSet.alphanumerics.contains(scalar(start - 2)) { return nil }   // `a@b`, not a reference
        let range = NSRange(location: start, length: caret - start)
        return Request(trigger: Character(trigger), range: range, typed: ns.substring(with: range))
    }

    private static func isName(_ c: Unicode.Scalar, allowing extra: String) -> Bool {
        CharacterSet.alphanumerics.contains(c) || "_-".unicodeScalars.contains(c) || extra.unicodeScalars.contains(c)
    }

    /// Names bound by `#let` at the start of a line (indentation allowed) and by `#import "m": a, b as c`.
    // shortcut: line-based, so a `#let` inside a block at line start counts and a multi-line import list is cut at the line end; upgrade to the syntax tree when scopes matter.
    public static func letNames(in text: String, importsToo: Bool = true) -> [String] {
        var out: [String] = []
        for m in text.matches(of: /(?m)^[ \t]*#let[ \t]+([\p{L}_][\p{L}\p{N}_-]*)/) { out.append(String(m.1)) }
        guard importsToo else { return out }
        for m in text.matches(of: /(?m)#import\s+(?:"[^"\n]*"|[^:\n"]+)(?:\s+as\s+[\p{L}_][\p{L}\p{N}_-]*)?\s*:\s*([^\n]+)/) {
            for part in m.1.split(separator: ",") {
                let item = part.split(separator: " ").last.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: "()")) ?? ""
                if item.wholeMatch(of: /[\p{L}_][\p{L}\p{N}_-]*/) != nil { out.append(item) }
            }
        }
        return out
    }

    /// Matching names, prefix matches first, then alphabetical.
    public func items(for request: Request) -> [CompletionItem] {
        let all: [CompletionItem]
        if request.trigger == "@" {
            let merged = labels.merging(entries.filter { !$0.value.isEmpty || labels[$0.key] == nil }) { _, bib in bib }
            all = merged.map { CompletionItem(kind: .label, label: $0.key, apply: $0.key, detail: $0.value.isEmpty ? nil : $0.value) }
        } else {
            all = names.map { CompletionItem(kind: .constant, label: $0, apply: $0, detail: nil) }
                + importable.filter { !names.contains($0.key) }.map { CompletionItem(kind: .constant, label: $0.key, apply: $0.key, detail: "Imports it from \($0.value.raw)") }
        }
        let typed = request.typed.lowercased()
        let hits = all.filter { typed.isEmpty || !CompletionMatch.indices(of: request.typed, in: $0.label).isEmpty }
        return hits.sorted {
            let a = $0.label.lowercased().hasPrefix(typed), b = $1.label.lowercased().hasPrefix(typed)
            return a != b ? a : $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }
}

extension Project {
    /// Everything cell completion needs for a table in `file`, read once when a table editor opens.
    public func cellCompletion(for file: RelPath?) async -> CellCompletion {
        let sources = textSources { FileKind.isTypst($0) }.compactMap(\.loaded)
        return CellCompletion(labels: await labelIndex(), bibliography: await references(), sources: sources, main: main, file: file)
    }
}

extension TableCode {
    /// `text` with the table rewritten for cell (`row`, `column`) holding `cellText`, and where `caret` (UTF-16, in the cell
    /// text) lands in it. Nil when the cell or caret is out of range.
    public static func splice(_ model: TableModel, row: Int, column: Int, text cellText: String, caret: Int, into text: String) -> (text: String, cursor: Int)? {
        let cell = cellText as NSString
        guard row >= 0, row < model.rowCount, column >= 0, column < model.columns.count, caret >= 0, caret <= cell.length else { return nil }
        let mark = "\u{E000}"                       // a private-use character survives `escape` and marks the caret
        var m = model
        m.setText(cell.substring(to: caret) + mark + cell.substring(from: caret), row: row, column: column)
        guard let e = edit(m, in: text) else { return nil }
        let r = e.replacement as NSString
        let at = r.range(of: mark)
        guard at.location != NSNotFound else { return nil }
        return ((text as NSString).replacingCharacters(in: e.range, with: r.replacingCharacters(in: at, with: "")), e.range.location + at.location)
    }
}

/// Resumes once with the first of two answers.
private final class FirstAnswer<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    init(_ c: CheckedContinuation<T?, Never>) { continuation = c }
    func resume(_ v: T?) {
        lock.lock(); let c = continuation; continuation = nil; lock.unlock()
        c?.resume(returning: v)
    }
}

extension Project {
    /// Completions for the table cell (`row`, `column`) with `cellText` and `caret` (UTF-16 in the cell): the cell is spliced
    /// into `buffer` (the text of `file`) at the table's range and typst-ide completes there, so scope, imports and labels
    /// are the engine's. `fallback`'s items (labels, bibliography keys, `#let` names, names to import) are merged in, and
    /// are all there is when the engine fails or takes over `timeout`. The editor's active completion list is not touched.
    public func completeCell(_ model: TableModel, row: Int, column: Int, text cellText: String, caret: Int, request: CellCompletion.Request,
                             in file: RelPath, buffer: String, fallback: CellCompletion, timeout: Duration = .milliseconds(200)) async -> [CompletionItem] {
        let local = fallback.items(for: request)
        guard let s = TableCode.splice(model, row: row, column: column, text: cellText, caret: caret, into: buffer) else { return local }
        let list: CompletionList? = await withCheckedContinuation { c in
            let once = FirstAnswer<CompletionList>(c)
            Task { once.resume(await self.complete(text: s.text, in: file, at: s.cursor, explicit: request.trigger == "#")) }
            Task { try? await Task.sleep(for: timeout); once.resume(nil) }
        }
        // The cell replaces `request.range`; a list that starts elsewhere would splice wrongly.
        guard let list, list.from == s.cursor - request.range.length else { return local }
        let engine = list.items.map { CompletionItem(kind: $0.kind, label: $0.label, apply: $0.apply.map { Snippet.parse($0).text }, detail: $0.detail) }
        let seen = Set(engine.map(\.label))
        return engine + local.filter { !seen.contains($0.label) }
    }
}
