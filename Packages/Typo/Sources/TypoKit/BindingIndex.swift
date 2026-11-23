import Foundation
import TypstEngine

public struct BindingSite: Sendable, Equatable, Hashable {
    public let file: RelPath
    public let range: NSRange
}

/// The identity of one definition: its file, name and the range of its name.
public struct BindingSymbol: Sendable, Hashable {
    public let file: RelPath
    public let name: String
    public let defRange: NSRange
    public var site: BindingSite { BindingSite(file: file, range: defRange) }
}

/// Every `#let` binding, function parameter and import of a project's Typst files, with what each use resolves to.
/// Syntactic: scopes and imports are read from the syntax tree, nothing is evaluated.
public struct BindingIndex: Sendable {
    fileprivate struct Def {
        let name: String
        let range: NSRange
        let kind: String
        let scope: NSRange
        let top: Bool
        let implicit: Bool
    }
    fileprivate struct Item { let name: String; let nameRange: NSRange; let aliasRange: NSRange? }
    fileprivate struct Import { let target: RelPath?; let items: [Item]; let wildcard: Bool; let scope: NSRange; let moduleRange: NSRange? }
    fileprivate struct Occurrence { let name: String; let range: NSRange; let module: String? }
    fileprivate struct File {
        var defs: [Def] = []
        var byName: [String: [Def]] = [:]
        var occurrences: [Occurrence] = []
        var imports: [Import] = []
        var paths: [NSRange] = []
    }
    fileprivate var files: [RelPath: File] = [:]
    private var order: [RelPath] = []

    /// Typst files in the given order; each text is the open buffer's if any, else disk (the caller decides).
    public static func build(_ sources: [(file: RelPath, text: String)]) -> BindingIndex {
        var index = BindingIndex()
        for (file, text) in sources where FileKind.isTypst(file.raw) {
            index.files[file] = scan(file, Bridge.bindings(in: text))
            index.order.append(file)
        }
        return index
    }

    private static func ns(_ r: [Int]) -> NSRange { r.count == 2 ? NSRange(location: r[0], length: max(0, r[1] - r[0])) : NSRange(location: 0, length: 0) }

    private static func scan(_ file: RelPath, _ raw: RawBindings) -> File {
        var f = File()
        f.defs = raw.defs.map { Def(name: $0.name, range: ns($0.range), kind: $0.kind, scope: ns($0.scope), top: $0.top, implicit: $0.implicit ?? false) }
        for d in f.defs { f.byName[d.name, default: []].append(d) }
        f.occurrences = raw.uses.map { Occurrence(name: $0.name, range: ns($0.range), module: nil) } + raw.fields.map { Occurrence(name: $0.name, range: ns($0.range), module: $0.module) }
        f.imports = raw.imports.map { i in
            Import(target: resolvePath(i.path, from: file), items: i.items.map { Item(name: $0.name, nameRange: ns($0.nameRange), aliasRange: $0.aliasRange.map(ns)) },
                   wildcard: i.wildcard, scope: ns(i.scope), moduleRange: i.moduleAlias.map { ns($0.range) })
        }
        f.paths = raw.imports.map { ns($0.pathRange) }
        return f
    }

    /// `a.typ` and `../lib/x.typ` against the importing file's folder, `/x.typ` against the project root. Packages (`@…`) have no file here.
    static func resolvePath(_ path: String, from file: RelPath) -> RelPath? {
        guard !path.isEmpty, !path.hasPrefix("@") else { return nil }
        var parts: [Substring] = path.hasPrefix("/") ? [] : (file.parent?.raw.split(separator: "/") ?? [])
        for p in path.split(separator: "/") {
            switch p {
            case ".": continue
            case "..": if parts.popLast() == nil { return nil }
            default: parts.append(p)
            }
        }
        return RelPath(parts.joined(separator: "/"))
    }

    // MARK: Resolution

    private func def(_ file: RelPath, at range: NSRange) -> Def? { files[file]?.defs.first { $0.range == range } }

    /// The definition a plain name means at `offset`: the innermost visible one (latest scope start).
    private func visible(_ name: String, in file: RelPath, at offset: Int) -> Def? {
        files[file]?.byName[name]?.filter { $0.scope.location <= offset && offset <= NSMaxRange($0.scope) }.max { $0.scope.location < $1.scope.location }
    }

    /// The last top-level definition of `name` in `file`: what `import` and `module.name` see.
    private func exported(_ name: String, in file: RelPath) -> Def? {
        files[file]?.byName[name]?.last { $0.top && !$0.implicit }
    }

    private func symbol(_ file: RelPath, _ d: Def) -> BindingSymbol { BindingSymbol(file: file, name: d.name, defRange: d.range) }

    /// A plain import item is only another name for the definition in the imported file; follow it there.
    private func follow(_ file: RelPath, _ d: Def, depth: Int = 0) -> BindingSymbol {
        guard d.kind == "import", depth < 8,
              let imp = files[file]?.imports.first(where: { $0.items.contains { $0.nameRange == d.range } }),
              let target = imp.target, let remote = exported(d.name, in: target) else { return symbol(file, d) }
        return follow(target, remote, depth: depth + 1)
    }

    private func resolve(_ name: String, in file: RelPath, at offset: Int) -> BindingSymbol? {
        if let d = visible(name, in: file, at: offset) { return follow(file, d) }
        let wild = files[file]?.imports.filter { $0.wildcard && $0.scope.location <= offset && offset <= NSMaxRange($0.scope) }.sorted { $0.scope.location > $1.scope.location } ?? []
        for imp in wild {
            if let target = imp.target, let remote = exported(name, in: target) { return follow(target, remote) }
        }
        return nil
    }

    private func resolveField(_ module: String, _ name: String, in file: RelPath, at offset: Int) -> BindingSymbol? {
        guard let m = visible(module, in: file, at: offset), m.kind == "module",
              let imp = files[file]?.imports.first(where: { $0.moduleRange == m.range }),
              let target = imp.target, let remote = exported(name, in: target) else { return nil }
        return follow(target, remote)
    }

    private func resolve(_ o: Occurrence, in file: RelPath) -> BindingSymbol? {
        o.module.map { resolveField($0, o.name, in: file, at: o.range.location) } ?? resolve(o.name, in: file, at: o.range.location)
    }

    private static func hit(_ r: NSRange, _ offset: Int) -> Bool { r.location <= offset && offset <= NSMaxRange(r) }
    private static func strictHit(_ r: NSRange, _ offset: Int) -> Bool { r.location <= offset && offset < NSMaxRange(r) }

    /// The definition under `offset` (an import item names the definition in the imported file), or the one a use there resolves to.
    public func symbol(in file: RelPath, at offset: Int) -> BindingSymbol? {
        guard let f = files[file] else { return nil }
        for test in [Self.strictHit, Self.hit] {
            if let d = f.defs.first(where: { test($0.range, offset) }) { return follow(file, d) }
            for imp in f.imports { for i in imp.items where i.aliasRange != nil && test(i.nameRange, offset) {
                guard let target = imp.target, let remote = exported(i.name, in: target) else { return nil }
                return follow(target, remote)
            } }
            if let o = f.occurrences.first(where: { test($0.range, offset) }) { return resolve(o, in: file) }
        }
        return nil
    }

    /// True when `offset` is on an identifier, import path or definition of the file, whether or not it resolves (a standard library name does not).
    public func hasSite(in file: RelPath, at offset: Int) -> Bool {
        guard let f = files[file] else { return false }
        return f.defs.contains { Self.hit($0.range, offset) } || f.occurrences.contains { Self.hit($0.range, offset) } || f.paths.contains { Self.strictHit($0, offset) }
    }

    // MARK: Quick fix support

    /// Names of the file's top-level definitions that other files can import.
    func exportedNames(in file: RelPath) -> [String] {
        guard let f = files[file] else { return [] }
        return Array(Set(f.defs.filter { $0.top && !$0.implicit }.map(\.name)))
    }

    /// Every name a plain use at `offset` would find: visible definitions plus what wildcard imports bring in.
    func visibleNames(in file: RelPath, at offset: Int) -> [String] {
        guard let f = files[file] else { return [] }
        var names = Set(f.defs.filter { $0.scope.location <= offset && offset <= NSMaxRange($0.scope) }.map(\.name))
        for imp in f.imports where imp.wildcard && imp.scope.location <= offset && offset <= NSMaxRange(imp.scope) {
            if let t = imp.target { names.formUnion(exportedNames(in: t)) }
        }
        return Array(names)
    }

    /// The file's imports as quick fixes need them: where the item list ends (nil for a wildcard or module import) and how far the import's scope reaches.
    func importSites(in file: RelPath) -> [(target: RelPath?, wildcard: Bool, itemsEnd: Int?, pathEnd: Int, scopeEnd: Int)] {
        guard let f = files[file] else { return [] }
        return zip(f.imports, f.paths).map { imp, path in
            let end = imp.items.map { max(NSMaxRange($0.nameRange), $0.aliasRange.map(NSMaxRange) ?? 0) }.max()
            return (imp.target, imp.wildcard, end, NSMaxRange(path), NSMaxRange(imp.scope))
        }
    }

    // MARK: References and rename

    /// Every use project-wide that resolves to `s`, including import item names and `module.name` fields; not the definition itself.
    public func references(of s: BindingSymbol) -> [BindingSite] {
        var out: [BindingSite] = []
        for file in order {
            guard let f = files[file] else { continue }
            for o in f.occurrences where o.name == s.name {
                let site = BindingSite(file: file, range: o.range)
                if site != s.site, resolve(o, in: file) == s { out.append(site) }
            }
            for imp in f.imports {
                guard let target = imp.target, let remote = exported(s.name, in: target), follow(target, remote) == s else { continue }
                for i in imp.items where i.name == s.name {
                    let site = BindingSite(file: file, range: i.nameRange)
                    if site != s.site { out.append(site) }
                }
            }
        }
        return out
    }

    /// The definition followed by its references.
    public func sites(of s: BindingSymbol) -> [BindingSite] { [s.site] + references(of: s) }

    /// Replacements, per file, that turn the definition and every reference of `s` into `new`.
    public func rename(_ s: BindingSymbol, to new: String) -> [RelPath: [Replacement]] {
        var out: [RelPath: [Replacement]] = [:]
        for site in sites(of: s) { out[site.file, default: []].append(Replacement(range: site.range, text: new)) }
        return out
    }

    public func renameSummary(of s: BindingSymbol) -> String {
        let refs = references(of: s)
        let files = Set(refs.map(\.file) + [s.file]).count
        func n(_ k: Int, _ w: String) -> String { "\(k) \(w)\(k == 1 ? "" : "s")" }
        return "1 definition and \(n(refs.count, "reference")) in \(n(files, "file"))"
    }

    private static let keywords: Set<String> = ["let", "set", "show", "if", "else", "for", "while", "in", "as", "import", "include", "return", "break", "continue", "not", "and", "or", "none", "auto", "true", "false", "context"]

    public static func isValidIdentifier(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, first == "_" || CharacterSet.letters.contains(first) else { return false }
        return s.unicodeScalars.dropFirst().allSatisfy { $0 == "_" || $0 == "-" || CharacterSet.alphanumerics.contains($0) }
    }

    /// False for a name the file picks by its stem (`import "a.typ"`): renaming it would not change the file.
    public func isRenameable(_ s: BindingSymbol) -> Bool { !(def(s.file, at: s.defRange)?.implicit ?? false) }

    /// A message when `new` cannot replace the symbol's name; nil when it can.
    public func validate(_ new: String, for s: BindingSymbol) -> String? {
        if new.isEmpty { return "The name can't be empty." }
        if !Self.isValidIdentifier(new) { return "Use letters, digits, _ and - only, starting with a letter or _." }
        if Self.keywords.contains(new) { return "“\(new)” is a keyword." }
        if new == s.name { return "That is the current name." }
        if !isRenameable(s) { return "This name comes from the file's name." }
        for site in sites(of: s) {
            if resolve(new, in: site.file, at: site.range.location) != nil { return "“\(new)” is already used." }
        }
        return nil
    }
}

extension Project {
    /// Bindings of the whole project; open buffers' unsaved text wins over disk.
    public func bindingIndex() async -> BindingIndex {
        let sources = textSources { FileKind.isTypst($0) }
        return await Self.buildBindings(sources)
    }

    @concurrent private static func buildBindings(_ sources: [SearchSource]) async -> BindingIndex {
        BindingIndex.build(sources.compactMap(\.loaded))
    }
}
