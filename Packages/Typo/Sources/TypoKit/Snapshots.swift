import CryptoKit
import Foundation
import TypstEngine

/// Automatic local history (design/14d-files-safety.md): after a save, at most every 10 minutes, a copy of every
/// text file in `<folder>/<ISO-8601 time>/<path>`.
public struct LocalHistory {
    /// This project's snapshots; nil takes none (the app sets `folder(for:)`, tests a temp folder).
    public var folder: URL?
    var now: @MainActor () -> Date = { Date() }
    var last: Date?
    /// The latest snapshot write; the next one waits for it.
    var writing: Task<Void, Never>?

    /// Application Support/Tympan/Snapshots/<SHA-256 of the root path>.
    public static func folder(for root: URL) -> URL {
        let key = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootFolder.appending(path: key)
    }

    /// Holds one folder per project.
    public static var rootFolder: URL { URL.applicationSupportDirectory.appending(path: "Tympan/Snapshots") }

    static let interval: TimeInterval = 600
    static let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static let keepAllFor: TimeInterval = 86_400
    static let keepDailyDays = 30
    static let maxCount = 200

    public static var retentionDescription: String {
        String(localized: "Every snapshot of the last \(Int(keepAllFor / 3600)) hours is kept, then the newest of each day for \(keepDailyDays) days, never more than \(maxCount) per project.", bundle: .module)
    }

    /// Which snapshots go: see `retentionDescription`.
    static func expired(_ dates: [Date], now: Date) -> Set<Date> {
        var keep: [Date] = [], days: Set<Int> = []
        for d in dates.sorted(by: >) {
            let age = now.timeIntervalSince(d)
            if age < keepAllFor || (age < Double(keepDailyDays) * 86_400 && days.insert(Int(age / 86_400)).inserted) { keep.append(d) }
        }
        return Set(dates).subtracting(keep.prefix(maxCount))
    }
}

public struct ProjectSnapshot: Identifiable, Hashable, Sendable {
    public let date: Date
    let folder: URL
    public var id: Date { date }
}

public struct SnapshotFile: Identifiable, Hashable, Sendable {
    public enum State: Sendable { case unchanged, changed, missing }
    public let path: RelPath
    public let text: String
    /// Compared with the current text: an open buffer's, else the file's.
    public let state: State
    public var id: RelPath { path }
}

extension Project {
    /// After a save that wrote something: a snapshot when the last one is 10 minutes old, or none was taken yet.
    func snapshotIfDue() {
        guard history.folder != nil else { return }
        if let last = history.last, history.now().timeIntervalSince(last) < LocalHistory.interval { return }
        takeSnapshot()
    }

    /// Copies every text file (an open buffer's text, else the file) off the main actor, then prunes old snapshots.
    @discardableResult public func takeSnapshot() -> Task<Void, Never> {
        guard let folder = history.folder else { return Task {} }
        let date = history.now()
        history.last = date
        let sources = allFiles.filter { FileKind.isText($0.raw) }.map { ($0, buffers[$0]?.storage.string) }
        let root = root, previous = history.writing
        let task = Task {
            await previous?.value
            await Self.write(sources, root: root, into: folder, date: date)
        }
        history.writing = task
        return task
    }

    /// shortcut: a snapshot that cannot be written is skipped silently; it is a safety net, not a save.
    @concurrent private static func write(_ sources: [(RelPath, String?)], root: URL, into folder: URL, date: Date) async {
        let fm = FileManager.default
        let name = date.formatted(LocalHistory.stamp)
        let temp = folder.appending(path: ".\(name)")          // renamed into place when complete: never half a snapshot
        try? fm.createDirectory(at: temp, withIntermediateDirectories: true)
        for (path, text) in sources {
            let dst = temp.appending(path: path.raw)
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let text { try? text.write(to: dst, atomically: false, encoding: .utf8) } else { try? fm.copyItem(at: root.appending(path: path.raw), to: dst) }
        }
        try? fm.moveItem(at: temp, to: folder.appending(path: name))
        let all = snapshots(in: folder)
        let expired = LocalHistory.expired(all.map(\.date), now: date)
        for s in all where expired.contains(s.date) { try? fm.removeItem(at: s.folder) }
    }

    /// Newest first.
    public func snapshots() -> [ProjectSnapshot] { history.folder.map(Self.snapshots(in:)) ?? [] }

    nonisolated private static func snapshots(in folder: URL) -> [ProjectSnapshot] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { n in (try? Date(n, strategy: LocalHistory.stamp)).map { ProjectSnapshot(date: $0, folder: folder.appending(path: n)) } }
            .sorted { $0.date > $1.date }
    }

    /// The snapshot's files, by path, each compared with the current text.
    public func files(in snapshot: ProjectSnapshot) async -> [SnapshotFile] {
        await Self.compare(snapshot.folder, root: root, open: buffers.mapValues { $0.storage.string })
    }

    @concurrent private static func compare(_ folder: URL, root: URL, open: [RelPath: String]) async -> [SnapshotFile] {
        (FileManager.default.subpaths(atPath: folder.path) ?? []).sorted().compactMap { sub in
            guard FileKind.isText(sub), let path = RelPath(sub), let text = try? String(contentsOf: folder.appending(path: sub), encoding: .utf8) else { return nil }
            let current = open[path] ?? (try? String(contentsOf: root.appending(path: sub), encoding: .utf8))
            return SnapshotFile(path: path, text: text, state: current == nil ? .missing : current == text ? .unchanged : .changed)
        }
    }

    /// Puts a snapshot's text back as one undoable edit of the buffer; a file that is gone is created again first.
    public func restore(_ file: SnapshotFile) async throws(ProjectError) {
        if buffers[file.path] == nil, !exists(file.path) {
            var dir: RelPath?
            for c in file.path.raw.split(separator: "/").dropLast().map(String.init) {
                let d = RelPath.make(c, in: dir)
                if let d, !isDirectory(d) { try createFolder(named: c, in: dir) }
                dir = d
            }
            try createFile(named: file.path.name, in: dir)
        }
        let b = try await open(file.path)
        guard b.storage.string != file.text else { return }
        b.apply([Replacement(range: NSRange(location: 0, length: b.storage.length), text: file.text)], actionName: String(localized: "Restore File", bundle: .module))
    }
}
