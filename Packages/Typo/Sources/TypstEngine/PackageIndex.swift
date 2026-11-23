import Foundation
import Synchronization

/// The `@preview` package index: cached on disk, revalidated in the background, never on the engine queue.
/// Foundation only. Files: `<dir>/index.json` and `<dir>/index.etag`; the index file's mtime is the time of
/// the last successful check.
public final class PackageIndex: Sendable {
    enum Fetched: Sendable { case notModified; case data(Data, etag: String?) }
    typealias Fetcher = @Sendable (_ etag: String?) async throws -> Fetched

    static let maxAge: TimeInterval = 3600
    static let url = URL(string: "https://packages.typst.org/preview/index.json")!

    private let dir: URL
    private let fetch: Fetcher
    private let now: @Sendable () -> Date
    /// Hands JSON to the runtime; returns the number of usable entries.
    private let apply: @Sendable (Data) -> Int
    private let applied = Mutex(0)

    /// Usable entries of the index last handed to the runtime.
    var count: Int { applied.withLock { $0 } }

    init(dir: URL, fetch: @escaping Fetcher = PackageIndex.urlSession, now: @escaping @Sendable () -> Date = { Date() },
         apply: @escaping @Sendable (Data) -> Int) {
        self.dir = dir
        self.fetch = fetch
        self.now = now
        self.apply = apply
    }

    private var indexFile: URL { dir.appending(path: "index.json") }
    private var etagFile: URL { dir.appending(path: "index.etag") }

    /// Loads the cached copy, if any. Synchronous: a few milliseconds for the real index.
    @discardableResult func loadCache() -> Int {
        guard let data = try? Data(contentsOf: indexFile) else { return 0 }
        return load(data)
    }

    private func load(_ data: Data) -> Int {
        let n = apply(data)
        if n > 0 { applied.withLock { $0 = n } }
        return n
    }

    var isFresh: Bool {
        guard let m = (try? indexFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return false }
        return now().timeIntervalSince(m) < Self.maxAge
    }

    /// At most one request per hour. Any failure keeps whatever is cached.
    public func revalidate() async {
        guard !isFresh else { return }
        _ = try? await refresh()
    }

    /// Asks the server now, whatever the age; throws on a failed request or a reply that is no index (the cache stays).
    @discardableResult func refresh() async throws -> Int {
        let cached = (try? Data(contentsOf: indexFile)) != nil
        let etag = cached ? (try? String(contentsOf: etagFile, encoding: .utf8)) : nil
        switch try await fetch(etag) {
        case .notModified:
            try? FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: indexFile.path)
        case .data(let data, let newTag):
            guard load(data) > 0 else { throw URLError(.cannotParseResponse) }   // not an index: keep the cache
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: indexFile, options: .atomic)
            NotificationCenter.default.post(name: TypstRuntime.packageIndexDidChange, object: nil)
            if let newTag { try? newTag.write(to: etagFile, atomically: true, encoding: .utf8) }
            else { try? FileManager.default.removeItem(at: etagFile) }
        }
        return count
    }

    @Sendable static func urlSession(etag: String?) async throws -> Fetched {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 30
        if let etag { req.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        switch (resp as? HTTPURLResponse)?.statusCode {
        case 304: return .notModified
        case 200: return .data(data, etag: (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "ETag"))
        default: throw URLError(.badServerResponse)
        }
    }
}
