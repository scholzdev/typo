import CoreText
import Foundation
import Synchronization

/// Process-wide, loaded once. Fonts are ready before any world exists, so the FontBook never changes
/// under a live world.
public final class TypstRuntime: @unchecked Sendable {   // handle immutable; TbRuntime is Sync
    public static func warmUp() { _ = shared }
    public static let shared: Task<TypstRuntime, Never> = Task {
        await TypstRuntime.load(indexURL: defaultIndexURL, packageDir: defaultPackageDir)
    }

    /// The font index cache; deleting it makes the next launch rebuild it.
    public static var defaultIndexURL: URL { URL.cachesDirectory.appending(path: "typst/font-index.json") }
    // Not Caches: the system may purge Caches, and offline compiles need the packages.
    public static var packageDirectory: URL { defaultPackageDir }
    static var defaultPackageDir: URL {
        var dir = URL.applicationSupportDirectory.appending(path: "typst/packages")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }

    public let handle: OpaquePointer
    public let packageIndex: PackageIndex
    /// Font files handed to the engine (the system fonts CoreText lists).
    public let fontFileCount: Int

    /// Posted after a revalidation stored a new `@preview` index.
    public static let packageIndexDidChange = Notification.Name("TypstRuntime.packageIndexDidChange")

    public var packageIndexCount: Int { packageIndex.count }
    /// Time of the last successful check of the `@preview` index; nil when there is no cached copy.
    public var packageIndexUpdated: Date? {
        (try? Self.packageDirectory.appending(path: "preview/index.json").resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
    /// Checks the `@preview` index now. Returns its number of packages.
    public func refreshPackageIndex() async throws -> Int { try await packageIndex.refresh() }
    private let listeners = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    /// Sets (or with nil clears) the user's packages data dir: `<dir>/<namespace>/<name>/<version>`. Worlds use it
    /// from their next compile on, and every `packagesChanges()` stream fires so open projects recompile.
    /// The caller keeps security-scoped access to `dir` for as long as it is set. Returns the local packages found.
    @discardableResult public func setPackagesDir(_ dir: URL?) -> Int {
        let n = Bridge.setPackagesDir(handle, path: dir?.path ?? "")
        for c in listeners.withLock({ Array($0.values) }) { c.yield() }
        return n
    }

    public func packagesChanges() -> AsyncStream<Void> {
        let (stream, c) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        listeners.withLock { $0[id] = c }
        c.onTermination = { [weak self] _ in self?.listeners.withLock { _ = $0.removeValue(forKey: id) } }
        return stream
    }

    private struct Handle: @unchecked Sendable { let raw: OpaquePointer }

    private init(indexURL: URL, packageDir: URL, packageFetch: @escaping PackageIndex.Fetcher) {
        // Unreadable font paths (sandbox, font managers) are skipped in Rust; the rest of the index stays valid.
        var paths = Set<String>()
        let collection = CTFontCollectionCreateFromAvailableFonts(nil)
        for d in (CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor]) ?? [] {
            if let u = CTFontDescriptorCopyAttribute(d, kCTFontURLAttribute) as? URL { paths.insert(u.path) }
        }
        fontFileCount = paths.count
        let h = Handle(raw: Bridge.makeRuntime(fontPaths: paths.sorted(), indexPath: indexURL.path, packageDir: packageDir.path))
        handle = h.raw
        let index = PackageIndex(dir: packageDir.appending(path: "preview"), fetch: packageFetch) {
            Bridge.setPackageIndex(h.raw, json: $0)
        }
        packageIndex = index
        index.loadCache()
        Task.detached(priority: .utility) { await index.revalidate() }
    }

    /// A DispatchQueue, not Task.detached: the first call blocks about 2 s on a cold font index.
    static func load(indexURL: URL, packageDir: URL,
                     packageFetch: @escaping PackageIndex.Fetcher = PackageIndex.urlSession) async -> TypstRuntime {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                c.resume(returning: TypstRuntime(indexURL: indexURL, packageDir: packageDir, packageFetch: packageFetch))
            }
        }
    }
}
