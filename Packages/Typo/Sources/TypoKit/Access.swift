import Foundation
import Observation
import TypstEngine

/// The single owner of bookmarks and of the Open Recent list. Persisted in UserDefaults.
@MainActor @Observable public final class RecentProjects {
    public struct Record: Codable, Sendable {
        public let id: ProjectID
        var bookmark: Data
        public internal(set) var rootPath: String
        public var main: RelPath
        public var name: String
        public var lastOpened: Date
        /// Preview lock; nil (records from before it existed) means locked. `main` is the pinned document.
        var locked: Bool?
    }
    public private(set) var records: [Record] = []           // most recent first, capped at 20

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "TypstCore.recentProjects"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let r = try? JSONDecoder().decode([Record].self, from: data) {
            records = r
        }
    }

    /// The macOS bookmark uses .withSecurityScope and iOS uses []. This is the only platform branch.
    /// Reuses the ID when the root path already has a record, so reopening a folder refocuses its window.
    public func register(root: URL, main: RelPath) throws -> ProjectID {
        let path = root.standardizedFileURL.path
        // Empty when creation fails: unsandboxed, `rootPath` alone reopens the project.
        let bookmark = (try? root.bookmarkData(options: ScopedAccess.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
        var record: Record
        if let i = records.firstIndex(where: { $0.rootPath == path }) {
            record = records.remove(at: i)
            record.bookmark = bookmark
            record.main = main
            record.lastOpened = .now
        } else {
            record = Record(id: ProjectID(), bookmark: bookmark, rootPath: path, main: main, name: root.lastPathComponent, lastOpened: .now)
        }
        records.insert(record, at: 0)
        if records.count > 20 { records.removeLast(records.count - 20) }
        save()
        return record.id
    }

    public func setMain(_ main: RelPath, for id: ProjectID) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].main = main
        save()
    }

    public func isLocked(_ id: ProjectID) -> Bool { record(id)?.locked ?? true }

    public func setLocked(_ locked: Bool, for id: ProjectID) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].locked = locked
        save()
    }

    func record(_ id: ProjectID) -> Record? { records.first { $0.id == id } }

    func refreshBookmark(_ id: ProjectID, root: URL) {
        guard let i = records.firstIndex(where: { $0.id == id }),
              let b = try? root.bookmarkData(options: ScopedAccess.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        records[i].bookmark = b
        save()
    }

    func setBookmarkForTesting(_ b: Data, _ id: ProjectID) {
        if let i = records.firstIndex(where: { $0.id == id }) { records[i].bookmark = b }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(records), forKey: Self.key)
    }
}

/// Holds security-scoped access to the project root for exactly as long as the Project lives.
/// Rust reads disk files with plain POSIX calls under this process-wide grant.
public final class ScopedAccess: Sendable {
#if os(macOS)
    static let creationOptions: URL.BookmarkCreationOptions = .withSecurityScope
    static let resolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
#else
    static let creationOptions: URL.BookmarkCreationOptions = []
    static let resolutionOptions: URL.BookmarkResolutionOptions = []
#endif

    let root: URL
    let isStale: Bool
    private let started: Bool

    /// `fallbackPath`: bookmarks made by the sandboxed build do not resolve in the unsandboxed one, so an existing
    /// directory opens by path (reported stale, so the caller stores a fresh bookmark).
    init(resolving bookmark: Data, fallbackPath: String? = nil) throws(ProjectError) {
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: Self.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            var isDir: ObjCBool = false
            guard let fallbackPath, FileManager.default.fileExists(atPath: fallbackPath, isDirectory: &isDir), isDir.boolValue,
                  FileManager.default.isReadableFile(atPath: fallbackPath) else { throw .accessDenied }
            url = URL(fileURLWithPath: fallbackPath, isDirectory: true)
            stale = true
        }
        root = url
        isStale = stale
        // False is normal outside the sandbox, where the URL needs no grant.
        started = url.startAccessingSecurityScopedResource()
    }

    deinit { if started { root.stopAccessingSecurityScopedResource() } }
}

/// The user's local packages folder (typst's packages data dir): an app-scope security-scoped bookmark in
/// UserDefaults. Access is held from `choose`/`restore` until `clear` or a replacement, and the folder is
/// handed to the runtime, which recompiles every open project.
@MainActor @Observable public final class LocalPackagesFolder {
    public private(set) var url: URL?
    @ObservationIgnored private var access: ScopedAccess?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let runtime: TypstRuntime?
    private static let key = "TypstCore.localPackagesBookmark"

    /// `runtime` nil means the shared one.
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults; runtime = nil }
    init(defaults: UserDefaults, runtime: TypstRuntime) { self.defaults = defaults; self.runtime = runtime }

    /// Resolves the stored bookmark (refreshing it when stale) and applies it. A bookmark that no longer
    /// resolves is dropped.
    public func restore() async {
        guard let data = defaults.data(forKey: Self.key) else { return }
        guard let a = try? ScopedAccess(resolving: data) else { defaults.removeObject(forKey: Self.key); return }
        if a.isStale, let fresh = try? a.root.bookmarkData(options: ScopedAccess.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: Self.key)
        }
        await apply(a)
    }

    /// The folder the setting names, read without touching the setting (typo-mcp reads the app's defaults).
    public static func stored(in defaults: UserDefaults = .standard) -> URL? {
        var stale = false
        return defaults.data(forKey: key).flatMap { try? URL(resolvingBookmarkData: $0, options: ScopedAccess.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &stale) }
    }

    /// `folder` comes from an open panel, so it carries its own grant.
    public func choose(_ folder: URL) async throws {
        let data = try folder.bookmarkData(options: ScopedAccess.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        let a = try ScopedAccess(resolving: data)
        defaults.set(data, forKey: Self.key)
        await apply(a)
    }

    public func clear() async {
        defaults.removeObject(forKey: Self.key)
        await apply(nil)
    }

    /// The runtime switches first, so no new compile reads the folder whose access is about to end.
    private func apply(_ new: ScopedAccess?) async {
        let rt = if let runtime { runtime } else { await TypstRuntime.shared.value }
        url = new?.root
        rt.setPackagesDir(new?.root)
        access = new
    }
}
