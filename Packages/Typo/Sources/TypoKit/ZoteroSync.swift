import Foundation
import TypstEngine

/// A project's link to a Zotero library: which library, which `.bib` file it fills, and how far the last sync got.
/// Kept in UserDefaults per project, never in the project folder; the API key lives in the Keychain (ZoteroKeychain).
public struct ZoteroLink: Codable, Equatable, Sendable {
    public var source: ZoteroSource
    /// The web API's numeric user ID; "0" for the local API.
    public var userID: String
    /// Nil: the whole library.
    public var collection: ZoteroCollection?
    public var target: RelPath
    /// The web library version of the last sync, sent as `If-Modified-Since-Version`.
    public var version: Int?
    public var lastSynced: Date?
    public var entryCount: Int?

    public init(source: ZoteroSource, userID: String, collection: ZoteroCollection?, target: RelPath) {
        self.source = source; self.userID = source == .local ? "0" : userID; self.collection = collection; self.target = target
    }

    public var libraryName: String { collection?.name ?? "My Library" }

    public static let header = "% Synced from Zotero by Typo \u{2014} edit in Zotero; changes here are overwritten."

    /// What the target file holds for Zotero's `bibtex`: the header line, then the entries with Zotero's keys.
    public static func fileText(_ bibtex: String) -> String {
        let body = bibtex.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return header + "\n\n" + body + "\n"
    }
}

struct ZoteroLinkStore {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String

    init(_ id: ProjectID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "Typo.zotero.\(id.raw)"
    }

    func load() -> ZoteroLink? { defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ZoteroLink.self, from: $0) } }

    func save(_ link: ZoteroLink?) {
        if let link { defaults.set(try? JSONEncoder().encode(link), forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

extension Buffer {
    /// The file Zotero fills: the editors show it read-only, since every sync overwrites it.
    public var isZoteroManaged: Bool { project.zoteroLink?.target == path }
}

extension Project {
    /// Links the project to `link` (replacing any link); the caller syncs next. Unsaved text of the target is saved
    /// first, so the sync can take over the file.
    public func connectZotero(_ link: ZoteroLink) async {
        try? await saveAll()
        zoteroNotBefore = nil
        zoteroError = nil
        zoteroLink = link
    }

    /// Drops the link; the file stays as ordinary, editable BibTeX.
    public func disconnectZotero() {
        zoteroLink = nil
        zoteroError = nil
        zoteroNotBefore = nil
    }

    /// Fetches the linked library and rewrites the target file if its text changed. Only the target file is touched.
    /// Does nothing while another sync runs or Zotero asked to back off; failures land in `zoteroError`.
    public func syncZotero(key: String?, transport: @escaping ZoteroTransport = ZoteroHTTP.urlSession, now: Date = .now) async {
        guard let link = zoteroLink, !zoteroSyncing else { return }
        if let wait = zoteroNotBefore, now < wait { return }
        zoteroSyncing = true
        defer { zoteroSyncing = false }
        let client = ZoteroClient(source: link.source, userID: link.userID, key: key, transport: transport)
        do {
            // A missing file must be rewritten even when the library did not change.
            let export = try await client.bibtex(collection: link.collection?.key, since: exists(link.target) ? link.version : nil)
            if let s = export?.backoff { zoteroNotBefore = now.addingTimeInterval(TimeInterval(s)) }
            guard var next = zoteroLink, next.target == link.target else { return }     // disconnected or relinked meanwhile
            if let export {
                try await writeZotero(ZoteroLink.fileText(export.text), to: link.target)
                next.version = export.version
                next.entryCount = BibTeX.entries(in: export.text).count
            }
            next.lastSynced = now
            zoteroLink = next
            zoteroError = nil
        } catch {
            if case ZoteroError.rateLimited(let s) = error { zoteroNotBefore = now.addingTimeInterval(TimeInterval(s)) }
            zoteroError = error.localizedDescription
        }
    }

    /// An existing file changes through its buffer (one undo step, then saved), so an open editor follows; a new one is
    /// written and the tree rescanned. Unchanged text writes nothing.
    private func writeZotero(_ text: String, to path: RelPath) async throws {
        guard exists(path) else {
            let url = url(for: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            bibliographyRevision += 1
            await refreshFiles()
            return
        }
        let b = try await open(path)
        guard !b.isDirty, !changedOnDisk.contains(path) else { throw ZoteroError.unsavedChanges(path.name) }
        guard b.storage.string != text else { return }
        b.apply([Self.middleEdit(b.storage.string, text)], actionName: "Sync from Zotero")
        try await save(under: path)
    }
}
