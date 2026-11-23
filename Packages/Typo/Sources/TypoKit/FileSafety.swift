import Foundation
import TypstEngine

/// Files deleted outside the app while open, and putting trashed items back (design/14d-files-safety.md).
extension Buffer {
    /// The file is gone from disk (Finder, a git checkout, ...): saves skip it, so it is never silently recreated.
    public var isMissingOnDisk: Bool { project.missingFiles.contains(path) }
}

extension Project {
    /// Re-derives `missingFiles` from the disk: also clears the mark of a file that came back.
    func checkMissing() {
        let gone = Set(buffers.keys.filter { !exists($0) })
        if gone != missingFiles { missingFiles = gone }
    }

    /// The save gate: a buffer whose file is gone is marked instead of written, even before the watcher noticed.
    func isOnDisk(_ path: RelPath) -> Bool {
        if !missingFiles.contains(path), exists(path) { return true }
        missingFiles.insert(path)
        return false
    }

    /// Open files that are gone from disk and have unsaved text; quit and window close ask about each.
    public func unsavedMissingFiles() -> [RelPath] {
        checkMissing()
        return missingFiles.filter { buffers[$0]?.isDirty == true }.sorted { $0.raw < $1.raw }
    }

    /// "Save Again": writes the buffer's text to its path once more, clean or not, recreating missing folders.
    public func saveAgain(_ path: RelPath) async throws(ProjectError) {
        guard let b = buffers[path] else { return }
        let u = url(for: path)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !exists(path) { FileManager.default.createFile(atPath: u.path, contents: nil) }   // the gate in save only overwrites
        missingFiles.remove(path)
        b.savedSeq = Seq(raw: 0)                                                              // dirty, so the save writes it
        try await save(under: path)
        rescan()
    }

    /// "Close" on a missing file: the buffer goes as in the Trash protocol; the main document is shown instead.
    public func closeMissing(_ path: RelPath) {
        forget(path)
        if selectedFile == nil, exists(main) { selectedFile = main }
    }

    /// Undo of Move to Trash: moves the item at `trashed` back to `path`.
    public func restore(fromTrash trashed: URL, to path: RelPath) async throws(ProjectError) {
        await beginFileOp()
        defer { endFileOp() }
        if let parent = path.parent, !isDirectory(parent) { throw .notFound(parent) }
        guard !exists(path) else { throw .nameExists(path.name) }
        do { try FileManager.default.moveItem(at: trashed, to: url(for: path)) } catch {
            throw .operationFailed("\u{201C}\(path.name)\u{201D} could not be put back: \(error.localizedDescription)")
        }
        rescan()
    }
}
