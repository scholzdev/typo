import Foundation
import TypstEngine

/// Open files whose content changed on disk (another editor, a sync tool, git); design/14d-files-safety.md.
extension Buffer {
    /// The file changed on disk while this buffer has unsaved text: saves skip it until the user chooses.
    public var isChangedOnDisk: Bool { project.changedOnDisk.contains(path) }
}

/// A file's text when an agent's tool started to rewrite it; `text` is nil for a file that did not exist.
public struct AgentSnapshot: Sendable, Equatable {
    public let path: RelPath
    public let text: String?
}

extension Project {
    /// Compares each open file with the text last read or written: a clean buffer takes the disk text, a dirty one
    /// becomes a conflict. Our own writes update the remembered hash first, so they never count.
    public func reloadChangedFiles() async {
        await waitForSaves()
        for (path, known) in diskHashes.sorted(by: { $0.key.raw < $1.key.raw }) {
            guard let b = buffers[path], !missingFiles.contains(path), !changedOnDisk.contains(path), reloadHolds[path] == nil,
                  let (disk, format) = try? await Self.readFile(url(for: path), settings: textFileSettings()) else { continue }
            // A save or a reload that finished during the read moved the baseline: this text may be stale.
            guard diskHashes[path] == known, buffers[path] === b, disk.hashValue != known, reloadHolds[path] == nil else { continue }
            if b.isDirty { changedOnDisk.insert(path) } else { load(disk, format, into: b) }
        }
    }

    /// "Keep Mine": the buffer overwrites the disk version.
    public func keepMine(_ path: RelPath) async throws(ProjectError) {
        guard let b = buffers[path] else { return }
        changedOnDisk.remove(path)
        b.savedSeq = Seq(raw: 0)                  // dirty, so the save writes it
        try await save(under: path)
    }

    /// "Use Disk Version": the buffer takes the disk text (one undo step) and is clean.
    public func useDisk(_ path: RelPath) async {
        guard let b = buffers[path] else { return }
        changedOnDisk.remove(path)
        if let (disk, format) = try? await Self.readFile(url(for: path), settings: textFileSettings()) { load(disk, format, into: b) }
    }

    // MARK: Agent writes

    /// Holds `path` while an agent's own tool rewrites it on disk, so the write lands as an undoable edit (`adoptHeldWrite`)
    /// instead of a reload. The snapshot is the text of a buffer opened without showing it, nil for a file that does not
    /// exist yet. Nil, and not held, when the buffer has unsaved text: the agent edits the disk version, so the normal
    /// conflict path decides. Every snapshot ends with exactly one `adoptHeldWrite` or `releaseAgentHold`.
    public func holdForAgent(_ path: RelPath) async -> AgentSnapshot? {
        reloadHolds[path, default: 0] += 1    // before the read below, which a reload could overtake
        if buffers[path] == nil, !FileManager.default.fileExists(atPath: url(for: path).path) { return AgentSnapshot(path: path, text: nil) }
        if let b = try? await open(path), !b.isDirty { return AgentSnapshot(path: path, text: b.storage.string) }
        await releaseAgentHold(AgentSnapshot(path: path, text: nil))
        return nil
    }

    /// Ends the hold; a change on disk meanwhile is reloaded (or becomes a conflict) as usual.
    public func releaseAgentHold(_ s: AgentSnapshot) async {
        if let n = reloadHolds[s.path] { reloadHolds[s.path] = n > 1 ? n - 1 : nil }
        await reloadChangedFiles()
    }

    /// Ends the hold and takes what the agent wrote into the buffer as one undo step with AI marks, which leaves it
    /// clean: snapshot→disk (`diff` of the two texts) for an existing file, the whole text marked for a new one. Returns
    /// the snapshot's text (nil for a new file), the change and the id Revert uses; nil when nothing changed or the buffer
    /// no longer has the snapshot's text.
    public func adoptHeldWrite(_ s: AgentSnapshot, actionName: String, diff: (_ old: String, _ new: String) -> Replacement?) async
        -> (old: String?, change: Replacement, changeID: UUID?)? {
        var result: (String?, Replacement, UUID?)?
        if let old = s.text {
            if let b = buffers[s.path], b.storage.string == old,
               let (disk, format) = try? await Self.readFile(url(for: s.path), settings: textFileSettings()),
               buffers[s.path] === b, b.storage.string == old, let r = diff(old, disk) {
                b.fileFormat = format
                let ids = b.applyAssistant([r], actionName: actionName)
                b.savedSeq = b.lastSeq
                diskHashes[s.path] = disk.hashValue
                dirtyRevision += 1
                hasUnsavedChanges = buffers.values.contains(where: \.isDirty)
                result = (old, r, ids.first)
            }
        } else if buffers[s.path] == nil, let b = try? await open(s.path), b.storage.length > 0 {
            // Written whole by the agent: marked without an edit, so Revert (which trashes the file) knows it is unchanged.
            let whole = NSRange(location: 0, length: b.storage.length)
            let change = AIChange(range: whole, original: "", written: b.storage.string)
            var marks = b.aiMarks
            marks.add(whole)
            b.aiMarks = marks
            b.aiChanges.append(change)
            result = (nil, Replacement(range: whole, text: change.written), change.id)
            await refreshFiles()
        }
        await releaseAgentHold(s)
        return result
    }

    /// One edit over the differing middle only, so the caret and the folds stay where they were.
    private func load(_ disk: String, _ format: FileFormat, into b: Buffer) {
        b.fileFormat = format
        let old = b.storage.string as NSString, new = disk as NSString
        var head = 0
        while head < min(old.length, new.length), old.character(at: head) == new.character(at: head) { head += 1 }
        var tail = 0
        while tail < min(old.length, new.length) - head, old.character(at: old.length - 1 - tail) == new.character(at: new.length - 1 - tail) { tail += 1 }
        let range = NSRange(location: head, length: old.length - head - tail)
        b.apply([Replacement(range: range, text: new.substring(with: NSRange(location: head, length: new.length - head - tail)))], actionName: "Reload from Disk")
        b.savedSeq = b.lastSeq
        diskHashes[b.path] = disk.hashValue
        dirtyRevision += 1
        hasUnsavedChanges = buffers.values.contains(where: \.isDirty)
    }
}
