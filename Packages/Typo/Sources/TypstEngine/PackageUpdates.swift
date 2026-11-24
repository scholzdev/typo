import Foundation

/// An installed `@preview` package with a newer, compatible version in the index.
public struct PackageUpdate: Sendable, Equatable, Identifiable {
    public let name: String
    public let installed: String     // highest installed version
    public let newest: String
    public var id: String { name }
}

/// Update checks against the cached `@preview` index. Pure; the app supplies the installed set and the index.
public enum PackageUpdates {
    /// Major, minor, patch of "1.2.3"; a pre-release or build suffix is ignored. Nil for anything else.
    static func parts(_ v: String) -> [Int]? {
        let core = v.prefix { $0 != "-" && $0 != "+" }.split(separator: ".", omittingEmptySubsequences: false)
        let n = core.compactMap { Int($0) }
        return core.count == 3 && n.count == 3 ? n : nil
    }

    /// True when `a` is a newer version than `b`; unparsable versions are never newer.
    static func isNewer(_ a: String, than b: String) -> Bool {
        guard let x = parts(a), let y = parts(b) else { return false }
        return x.lexicographicallyPrecedes(y) ? false : x != y
    }

    /// The newest version Typo can compile (skips those that need a newer Typst than `ours`).
    static func newestCompatible(_ p: UniversePackage, ours: String) -> String? {
        p.allVersions.filter { v in parts(v) != nil && !(p.compilerByVersion[v].map { Universe.isNewer($0, than: ours) } ?? false) }
            .max { isNewer($1, than: $0) }
    }

    /// Downloaded `@preview` packages: name and installed versions (local namespaces have no index).
    public static func installed(in packageDir: URL) -> [String: Set<String>] {
        InstalledPackage.list(in: packageDir, namespaces: ["preview"], measured: false)
            .reduce(into: [:]) { $0[$1.name, default: []].insert($1.version) }
    }

    /// One entry per installed package whose highest installed version is below the newest compatible one, by name.
    public static func available(installed: [String: Set<String>], index: [UniversePackage], ours: String = EngineVersions.typst) -> [PackageUpdate] {
        index.compactMap { p in
            guard let have = installed[p.name]?.filter({ parts($0) != nil }).max(by: { isNewer($1, than: $0) }),
                  let newest = newestCompatible(p, ours: ours), isNewer(newest, than: have) else { return nil }
            return PackageUpdate(name: p.name, installed: have, newest: newest)
        }.sorted { $0.name < $1.name }
    }

    /// `import "@preview/name:version"` string literals of a file, with the range of the version inside the literal.
    struct ImportSite: Equatable { let name, version: String; let literal, versionRange: NSRange }

    static func imports(in text: String) -> [ImportSite] {
        guard text.contains("@preview/") else { return [] }
        let ns = text as NSString
        return TypstSyntax.tokens(in: text).compactMap { t in
            guard t.tag == .string, t.range.length > 12 else { return nil }
            let inner = NSRange(location: t.range.location + 1, length: t.range.length - 2)
            let s = ns.substring(with: inner)
            guard s.hasPrefix("@preview/"), let colon = s.firstIndex(of: ":") else { return nil }
            let name = String(s[s.index(s.startIndex, offsetBy: 9)..<colon]), version = String(s[s.index(after: colon)...])
            guard !name.isEmpty, !name.contains("/"), parts(version) != nil else { return nil }
            // Only what `import` names; `read("@preview/…")` is no package.
            var i = t.range.location
            while i > 0, let c = Unicode.Scalar(ns.character(at: i - 1)), c == " " || c == "\t" { i -= 1 }
            guard i >= 6, ns.substring(with: NSRange(location: i - 6, length: 6)) == "import" else { return nil }
            let at = (s as NSString).length - (version as NSString).length
            return ImportSite(name: name, version: version, literal: t.range, versionRange: NSRange(location: inner.location + at, length: (version as NSString).length))
        }
    }

    static let hintPrefix = "Newer version "

    /// "Newer version X of @preview/name is available" for each import below the newest compatible version.
    public static func hints(sources: [(file: RelPath, text: String)], index: [UniversePackage], ours: String = EngineVersions.typst, firstID: Int = 0) -> [Diagnostic] {
        let byName = Dictionary(index.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Diagnostic] = []
        for (file, text) in sources where FileKind.isTypst(file.raw) {
            for s in imports(in: text) {
                guard let p = byName[s.name], let newest = newestCompatible(p, ours: ours), isNewer(newest, than: s.version) else { continue }
                out.append(Diagnostic(id: firstID + out.count, severity: .hint, message: "\(hintPrefix)\(newest) of @preview/\(s.name) is available", hints: [],
                                      origin: .project(Location(file: file, range: s.literal))))
            }
        }
        return out
    }

    /// Name and version out of a hint message.
    public static func parseHint(_ message: String) -> (name: String, version: String)? {
        guard message.hasPrefix(hintPrefix) else { return nil }
        let w = message.dropFirst(hintPrefix.count).split(separator: " ")
        guard w.count >= 5, w[1] == "of", w[2].hasPrefix("@preview/") else { return nil }
        return (String(w[2].dropFirst(9)), String(w[0]))
    }

    /// "Update to X" for the import at `at`, and when other imports of the package name that same old version, "Update All Imports of name to X".
    public static func fixes(name: String, to new: String, at loc: Location, sources: [(file: RelPath, text: String)]) -> [QuickFix] {
        let all: [(RelPath, ImportSite)] = sources.filter { FileKind.isTypst($0.file.raw) }.flatMap { f in imports(in: f.text).map { (f.file, $0) } }
        guard let here = all.first(where: { $0.0 == loc.file && $0.1.literal == loc.range && $0.1.name == name }) else { return [] }
        let same = all.filter { $0.1.name == name && $0.1.version == here.1.version }
        var fixes = [QuickFix(title: String(localized: "Update to \(new)", bundle: .module), edits: [loc.file: [Replacement(range: here.1.versionRange, text: new)]])]
        if same.count > 1 {
            var edits: [RelPath: [Replacement]] = [:]
            for (f, s) in same { edits[f, default: []].append(Replacement(range: s.versionRange, text: new)) }
            fixes.append(QuickFix(title: String(localized: "Update All Imports of \(name) to \(new)", bundle: .module), edits: edits))
        }
        return fixes
    }
}
