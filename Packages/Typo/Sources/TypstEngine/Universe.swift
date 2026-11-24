import Foundation
import Synchronization

/// One package of the Typst Universe index (`@preview`), newest version first in `allVersions`.
public struct UniversePackage: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let version: String          // latest
    public let allVersions: [String]
    public let description: String
    public let authors: [String]
    public let categories: [String]
    public let keywords: [String]
    public let license: String
    public let isTemplate: Bool
    public let repository: URL?
    public let homepage: URL?
    /// The newest version's minimum Typst version, and when that version was published.
    public var compiler: String? = nil
    public var updated: Date? = nil
    /// Minimum Typst version per package version, where the index names one.
    public var compilerByVersion: [String: String] = [:]

    public var title: String { "@preview/\(name)" }
    public var universeURL: URL { URL(string: "https://typst.app/universe/package/\(name)")! }
    public func importLine(_ version: String) -> String { "#import \"@preview/\(name):\(version)\": *" }
}

public enum PackageInstallState: Sendable, Equatable { case get, installed, update }

public enum Universe {
    /// Numeric per component: 0.10.0 is newer than 0.2.0.
    /// True when the package needs a newer Typst than `ours` (versions like "0.14.0"; unknown requirements pass).
    public static func needsNewerTypst(_ p: UniversePackage, than ours: String) -> Bool {
        guard let c = p.compiler, !c.isEmpty else { return false }
        return isNewer(c, than: ours)
    }

    public static func isNewer(_ a: String, than b: String) -> Bool { a.compare(b, options: .numeric) == .orderedDescending }

    private struct Entry: Decodable {
        struct Marker: Decodable {}
        let name, version: String
        let description: String?, license: String?
        let authors, categories, keywords: [String]?
        let template: Marker?
        let repository, homepage: String?
        let compiler: String?
        let updatedAt: Double?
    }

    /// All packages of an index.json, each name once with its newest version's data, sorted by name. Bad input gives [].
    public static func parse(_ data: Data) -> [UniversePackage] {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        let byName = Dictionary(grouping: entries, by: \.name)
        return byName.values.map { group in
            let sorted = group.sorted { isNewer($0.version, than: $1.version) }
            let e = sorted[0]
            var p = UniversePackage(name: e.name, version: e.version, allVersions: sorted.map(\.version),
                                   description: e.description ?? "", authors: e.authors ?? [], categories: e.categories ?? [],
                                   keywords: e.keywords ?? [], license: e.license ?? "", isTemplate: e.template != nil,
                                   repository: e.repository.flatMap(URL.init(string:)), homepage: e.homepage.flatMap(URL.init(string:)),
                                   compiler: e.compiler, updated: e.updatedAt.map { Date(timeIntervalSince1970: $0) })
            p.compilerByVersion = Dictionary(group.compactMap { g in g.compiler.map { (g.version, $0) } }, uniquingKeysWith: { a, _ in a })
            return p
        }.sorted { $0.name < $1.name }
    }

    /// Case-insensitive; every word must occur in the name, description, a keyword or a category.
    public static func matches(_ p: UniversePackage, query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        if words.isEmpty { return true }
        let hay = ([p.name, p.description] + p.keywords + p.categories).joined(separator: "\n").lowercased()
        return words.allSatisfy { hay.contains($0) }
    }

    public static func state(of p: UniversePackage, installed: Set<String>) -> PackageInstallState {
        if installed.contains(p.version) { return .installed }
        return installed.contains { isNewer(p.version, than: $0) } ? .update : .get
    }
}

public enum PackageInstallError: LocalizedError, Equatable {
    case fetchFailed(String)
    public var errorDescription: String? {
        switch self { case .fetchFailed(let m): String(localized: "Could not download the package: \(m)", bundle: .module) }
    }
}

extension TypstRuntime {
    private static let universeCache = Mutex<(stamp: Date, packages: [UniversePackage])?>(nil)

    /// Every package of the cached `@preview` index; empty when none is cached. Reads and parses off the caller's actor;
    /// the parse is kept until the file changes, as the lint asks on every run.
    public static func universePackages() async -> [UniversePackage] {
        await Task.detached(priority: .userInitiated) {
            let file = packageDirectory.appending(path: "preview/index.json")
            let stamp = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if let hit = universeCache.withLock({ $0 }), hit.stamp == stamp { return hit.packages }
            let parsed = (try? Data(contentsOf: file)).map(Universe.parse) ?? []
            universeCache.withLock { $0 = (stamp, parsed) }
            return parsed
        }.value
    }

    /// Downloads `@preview/name:version` into the package cache and returns its folder.
    public func install(name: String, version: String) async throws(PackageInstallError) -> URL {
        let r = await Task.detached(priority: .userInitiated) { [self] in Bridge.fetchPackage(handle, spec: "@preview/\(name):\(version)") }.value
        guard r.ok else { throw .fetchFailed(r.text) }
        return URL(fileURLWithPath: r.text)
    }
}
