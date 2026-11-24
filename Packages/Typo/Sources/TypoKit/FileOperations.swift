import Foundation
import TypstEngine

/// File management (DESIGN.md section 13). A `RelPath` is the identity of a buffer, its overlay, the main
/// document and more, so every operation that changes one goes through `relocate` or the Trash protocol.
extension Project {
    // MARK: Names

    /// The name without surrounding whitespace, or `.invalidName`.
    static func checked(_ name: String) throws(ProjectError) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !n.hasPrefix("."), !n.contains("/"), !n.contains(":") else { throw .invalidName(name) }
        return n
    }

    func exists(_ p: RelPath) -> Bool { FileManager.default.fileExists(atPath: url(for: p).path) }

    public func isDirectory(_ p: RelPath) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url(for: p).path, isDirectory: &d) && d.boolValue
    }

    /// "name copy.ext", "name copy 2.ext", ... (`copy`), or "name.ext", "name 2.ext", ... The first one free in `folder`.
    public func availableName(for name: String, in folder: RelPath?, copy: Bool, isFolder: Bool = false) -> String {
        let ns = name as NSString
        let ext = isFolder ? "" : ns.pathExtension
        let stem = isFolder ? name : ns.deletingPathExtension
        var i = 1
        while true {
            let s = copy ? (i == 1 ? "\(stem) copy" : "\(stem) copy \(i)") : (i == 1 ? stem : "\(stem) \(i)")
            let candidate = ext.isEmpty ? s : "\(s).\(ext)"
            if let p = RelPath.make(candidate, in: folder), !exists(p) { return candidate }
            i += 1
        }
    }

    /// Rescans the tree on the caller's thread: no suspension between a disk change and the tree showing it.
    func rescan() {
        files = FileNode.scanNow(root)
        filesGeneration += 1
        structureChanged()
    }

    /// Hands the project's font files to the engine when their set changed; a file rewritten in place keeps its old faces until then.
    func syncProjectFonts() {
        let paths = allFiles.filter { FileKind(path: $0.raw) == .font }.map { url(for: $0).path }
        guard paths != projectFontPaths else { return }
        projectFontPaths = paths
        engine.send(.setProjectFonts(paths))
    }

    func structureChanged() {
        fileRevision += 1
        bibliographyRevision += 1
        latestSearch += 1                    // an in-flight search over the old layout answers nil
        searchTask?.cancel()
    }

    // MARK: Create

    private func newItem(_ name: String, in folder: RelPath?) throws(ProjectError) -> RelPath {
        let n = try Self.checked(name)
        if let folder, !isDirectory(folder) { throw .notFound(folder) }
        guard let p = RelPath.make(n, in: folder) else { throw .invalidName(name) }
        guard !exists(p) else { throw .nameExists(n) }
        return p
    }

    /// An empty file. A text file opens in the editor and becomes `selectedFile`.
    @discardableResult public func createFile(named name: String, in folder: RelPath? = nil) throws(ProjectError) -> RelPath {
        let p = try newItem(name, in: folder)
        do { try Data().write(to: url(for: p), options: .withoutOverwriting) } catch { throw .operationFailed(error.localizedDescription) }
        rescan()
        if FileKind.isText(p.raw) { selectedFile = p }
        return p
    }

    @discardableResult public func createFolder(named name: String, in folder: RelPath? = nil) throws(ProjectError) -> RelPath {
        let p = try newItem(name, in: folder)
        do { try FileManager.default.createDirectory(at: url(for: p), withIntermediateDirectories: false) } catch { throw .operationFailed(error.localizedDescription) }
        rescan()
        return p
    }

    // MARK: Relocate

    @discardableResult public func rename(_ path: RelPath, to newName: String) async throws(ProjectError) -> RelPath {
        let new = try renameTarget(path, to: newName)
        if new == path { return path }
        try await relocate(path, to: new)
        return new
    }

    /// Where `rename(path, to: name)` puts the item; the same error for an invalid name.
    public func renameTarget(_ path: RelPath, to name: String) throws(ProjectError) -> RelPath {
        guard let new = RelPath.make(try Self.checked(name), in: path.parent) else { throw .invalidName(name) }
        return new
    }

    /// Moves into `folder` (nil = root), under `name` when given (Keep Both, and undo of it).
    @discardableResult public func move(_ path: RelPath, into folder: RelPath?, named name: String? = nil) async throws(ProjectError) -> RelPath {
        if let folder, folder.isAtOrUnder(path) { throw .invalidMove(String(localized: "\u{201C}\(path.name)\u{201D} cannot be moved into itself.", bundle: .module)) }
        guard let new = RelPath.make(name ?? path.name, in: folder) else { throw .invalidName(name ?? path.name) }
        if new == path { return path }
        try await relocate(path, to: new)
        return new
    }

    func beginFileOp() async {
        if fileOpBusy { await withCheckedContinuation { fileOpWaiters.append($0) } } else { fileOpBusy = true }
    }

    func endFileOp() {
        if fileOpWaiters.isEmpty { fileOpBusy = false } else { fileOpWaiters.removeFirst().resume() }   // the baton passes with busy still true
    }

    /// Steps 0 and 1: no autosave starts (the caller holds a pause), no write is queued or running, and every
    /// buffer at or under `root` is saved, so nothing can land on a path after it changed. Settles in a loop
    /// because each await lets a keystroke, a Cmd-S or a sidebar click in.
    private func quiesceAndSave(under root: RelPath) async throws(ProjectError) {
        autosave?.cancel()
        autosave = nil
        func dirty() -> Bool { buffers.contains { $0.key.isAtOrUnder(root) && $0.value.isDirty && !missingFiles.contains($0.key) && !changedOnDisk.contains($0.key) } }
        while true {
            for (p, t) in opening where p.isAtOrUnder(root) { _ = try? await t.value; opening[p] = nil }
            await waitForSaves()
            if dirty() { try await save(under: root) }
            // A finished save waits for its owner to clear `saving`; let it run instead of looping on main.
            if saving != nil { await Task.yield(); continue }
            if !dirty(), !opening.keys.contains(where: { $0.isAtOrUnder(root) }) { return }
        }
    }

    private func resumeAutosave() {
        autosavePauses -= 1
        if autosavePauses == 0, hasUnsavedChanges { scheduleAutosave() }
    }

    private func isSameItem(_ a: URL, _ b: URL) -> Bool {
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let x = try? a.resourceValues(forKeys: key).fileResourceIdentifier,
              let y = try? b.resourceValues(forKeys: key).fileResourceIdentifier else { return false }
        return x.isEqual(y)
    }

    /// The identity change for a file or a folder (the descendants relocate with it).
    func relocate(_ old: RelPath, to new: RelPath) async throws(ProjectError) {
        await beginFileOp()
        defer { endFileOp() }
        guard exists(old) else { throw .notFound(old) }
        let src = url(for: old), dst = url(for: new)
        let caseOnly = old.parent == new.parent && old.name.caseInsensitiveCompare(new.name) == .orderedSame
        func checkDestination() throws(ProjectError) {
            if let parent = new.parent, !isDirectory(parent) { throw .notFound(parent) }
            if exists(new), !(caseOnly && isSameItem(src, dst)) { throw .nameExists(new.name) }
        }
        try checkDestination()
        autosavePauses += 1
        defer { resumeAutosave() }
        try await quiesceAndSave(under: old)

        // Steps 2 to 4 below never suspend: no autosave or other main-actor work sees a half-moved state.
        try checkDestination()
        let fm = FileManager.default
        do {
            if caseOnly, exists(new) {      // the same item under another case: a case-insensitive volume needs a hop
                let hop = src.deletingLastPathComponent().appending(path: ".rename-\(UUID().uuidString)")
                try fm.moveItem(at: src, to: hop)
                do { try fm.moveItem(at: hop, to: dst) } catch { try? fm.moveItem(at: hop, to: src); throw error }
            } else {
                try fm.moveItem(at: src, to: dst)
            }
        } catch {
            throw .operationFailed(String(localized: "\u{201C}\(old.name)\u{201D} could not be moved: \(error.localizedDescription)", bundle: .module))
        }

        rekeyOpenItems(from: old, to: new)
    }

    /// The synchronous tail of a move, shared by `relocate` and `followExternalMoves`: the engine, the buffers
    /// and every path the project keeps follow the item from `old` to `new`; then rescan.
    func rekeyOpenItems(from old: RelPath, to new: RelPath) {
        let seq = takeSeq()
        let moving = buffers.keys.filter { $0.isAtOrUnder(old) }
        engine.send(.relocate(from: old, to: new, overlays: moving, seq))
        let rekeyed = moving.map { (buffers.removeValue(forKey: $0)!, $0.replacing(old, with: new)!) }
        for (b, p) in rekeyed { b.rekey(to: p); buffers[p] = b }
        for p in moving {
            let n = p.replacing(old, with: new)!
            identities[n] = identities.removeValue(forKey: p)
            diskHashes[n] = diskHashes.removeValue(forKey: p)
            if changedOnDisk.remove(p) != nil { changedOnDisk.insert(n) }
        }
        tabs.rekey(from: old, to: new)
        if let s = selectedFile?.replacing(old, with: new) { selectedFile = s }
        if let m = main.replacing(old, with: new) { main = m; recents?.setMain(m, for: id) }
        if let c = lastCursor, let f = c.file.replacing(old, with: new) { lastCursor = (f, c.cursor) }
        cursorSeqs = Dictionary(cursorSeqs.map { ($0.key.replacing(old, with: new) ?? $0.key, $0.value) }, uniquingKeysWith: { $1 })
        log.relocate(from: old, to: new)
        if bookmarks.contains(where: { $0.path.isAtOrUnder(old) }) {
            bookmarks = bookmarks.map { var b = $0; b.path = b.path.replacing(old, with: new) ?? b.path; return b }
        }
        activeList = nil
        staleRoots.append(old)
        staleSince = seq
        trimLog()
        rescan()
        checkMissing()
    }

    private func fileID(_ url: URL) -> (any NSObjectProtocol)? {
        try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
    }

    func identify(_ path: RelPath) { identities[path] = fileID(url(for: path)) }

    /// Open files renamed or moved in Finder: a buffer whose path is gone follows the new path (not in the previous
    /// tree, no buffer) that carries the same file identity. Returns whether any buffer moved.
    private func followExternalMoves(scanned: [FileNode]) -> Bool {
        let known = Set(allFiles)
        let candidates = scanned.flatMap(\.leaves).filter { !known.contains($0) && buffers[$0] == nil }
        var moved = false
        for old in buffers.keys.sorted(by: { $0.raw < $1.raw }) where !exists(old) {
            guard let id = identities[old],
                  let new = candidates.first(where: { buffers[$0] == nil && fileID(url(for: $0)).map(id.isEqual) == true }) else { continue }
            rekeyOpenItems(from: old, to: new)
            moved = true
        }
        for p in buffers.keys where exists(p) { identify(p) }
        return moved
    }

    // MARK: Duplicate, trash, import

    /// A copy next to the original ("name copy.ext"); unsaved text of open files is saved first so the copy has it.
    @discardableResult public func duplicate(_ path: RelPath) async throws(ProjectError) -> RelPath {
        await beginFileOp()
        defer { endFileOp() }
        guard exists(path) else { throw .notFound(path) }
        try await save(under: path)
        let name = availableName(for: path.name, in: path.parent, copy: true, isFolder: isDirectory(path))
        guard let new = RelPath.make(name, in: path.parent) else { throw .invalidName(name) }
        do { try FileManager.default.copyItem(at: url(for: path), to: url(for: new)) } catch { throw .operationFailed(error.localizedDescription) }
        rescan()
        return new
    }

    /// Trash protocol: save, move to the Trash, then drop the overlays and close the buffers. The Trash comes
    /// before the close (the spec lists it after), so a failing Trash leaves every buffer open; on success the
    /// result is the same, since nothing suspends in between. Returns where the item went, for undo.
    @discardableResult public func moveToTrash(_ path: RelPath) async throws(ProjectError) -> URL {
        await beginFileOp()
        defer { endFileOp() }
        guard exists(path) else { throw .notFound(path) }
        autosavePauses += 1
        defer { resumeAutosave() }
        try await quiesceAndSave(under: path)

        let trashed: URL
        do { trashed = try trash(url(for: path)) } catch {
            throw .operationFailed(String(localized: "\u{201C}\(path.name)\u{201D} could not be moved to the Trash: \(error.localizedDescription)", bundle: .module))
        }
        forget(path)
        return trashed
    }

    /// A drop's Replace: the item at `dest` goes to the Trash (as Move to Trash does it), then `path` moves there.
    /// Returns the Trash location of the old item, for `undoReplacing`.
    public func replacing(_ dest: RelPath, with path: RelPath) async throws(ProjectError) -> URL {
        if dest.isAtOrUnder(path) || path.isAtOrUnder(dest) { throw .invalidMove(String(localized: "\u{201C}\(path.name)\u{201D} cannot replace an item that contains it or is inside it.", bundle: .module)) }
        let trashed = try await moveToTrash(dest)
        do { try await relocate(path, to: dest) } catch { try? await restore(fromTrash: trashed, to: dest); throw error }
        return trashed
    }

    /// Undo of `replacing`: the moved item goes back first (the name is then free), then the trashed one is restored.
    public func undoReplacing(_ dest: RelPath, from path: RelPath, trashed: URL) async throws(ProjectError) {
        try await relocate(dest, to: path)
        try await restore(fromTrash: trashed, to: dest)
    }

    /// Steps 2 and 4 of the Trash protocol for an item that is gone: overlays dropped, buffers closed, `main` moved on.
    func forget(_ path: RelPath) {
        let seq = takeSeq()
        let closed = buffers.keys.filter { $0.isAtOrUnder(path) }
        engine.send(.drop(closed, seq))
        for p in closed { buffers[p] = nil; cursorSeqs[p] = nil; diskHashes[p] = nil; changedOnDisk.remove(p) }
        removeBookmarks { $0.path.isAtOrUnder(path) }
        let hadSelection = selectedFile.map { !$0.isAtOrUnder(path) } ?? false
        let next = tabs.remove(atOrUnder: path, active: selectedFile)
        if selectedFile?.isAtOrUnder(path) == true { selectedFile = next }
        if lastCursor?.file.isAtOrUnder(path) == true { lastCursor = nil }
        activeList = nil
        staleRoots.append(path)
        staleSince = seq
        hasUnsavedChanges = buffers.values.contains(where: \.isDirty)
        trimLog()
        rescan()
        checkMissing()
        guard main.isAtOrUnder(path) else { return }
        // The selected .typ, else the first .typ in the root. With none left `main` keeps the trashed path:
        // the compile reports the missing file and the preview shows no document.
        let selectedTyp = hadSelection ? selectedFile.flatMap { FileKind.isTypst($0.raw) ? $0 : nil } : nil
        guard let next = selectedTyp ?? files.first(where: { !$0.isDirectory && $0.kind == .typst })?.id else {
            preview.clear()
            return
        }
        setMain(next)
        if selectedFile == nil { selectedFile = next }
    }

    /// Copies files dropped from outside into `folder` (nil = root); the originals stay. A name clash gets "copy".
    @discardableResult public func importItems(_ urls: [URL], into folder: RelPath? = nil) throws(ProjectError) -> [RelPath] {
        if let folder, !isDirectory(folder) { throw .notFound(folder) }
        let rootPath = root.standardizedFileURL.path
        var imported: [RelPath] = []
        defer { if !imported.isEmpty { rescan() } }
        for u in urls {
            let source = u.standardizedFileURL
            if rootPath == source.path || rootPath.hasPrefix(source.path + "/") {
                throw .invalidMove(String(localized: "\u{201C}\(source.lastPathComponent)\u{201D} contains this project and cannot be copied into it.", bundle: .module))
            }
            let base = source.lastPathComponent
            guard (try? Self.checked(base)) != nil else { continue }       // hidden files would not show up
            let isDir = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let name = RelPath.make(base, in: folder).map(exists) == true ? availableName(for: base, in: folder, copy: true, isFolder: isDir) : base
            guard let p = RelPath.make(name, in: folder) else { continue }
            do { try FileManager.default.copyItem(at: source, to: url(for: p)) } catch { throw .operationFailed(error.localizedDescription) }
            imported.append(p)
        }
        return imported
    }

    /// A drop on the file list. A URL inside the project is a row dragged within it and moves into `folder`
    /// (nil = root); any other URL is a Finder item and is copied in.
    @discardableResult public func dropItems(_ urls: [URL], into folder: RelPath?) async throws(ProjectError) -> [RelPath] {
        var outside: [URL] = []
        var result: [RelPath] = []
        for u in urls {
            if let p = relPath(of: u) {
                result.append(try await move(p, into: folder))
            } else {
                outside.append(u)
            }
        }
        return result + (try importItems(outside, into: folder))
    }

    /// The project path of a file URL inside the root (a row dragged within the list); nil for anything else.
    public func relPath(of url: URL) -> RelPath? {
        let base = root.resolvingSymlinksInPath().path + "/", path = url.resolvingSymlinksInPath().path
        return path.hasPrefix(base) ? RelPath(String(path.dropFirst(base.count))) : nil
    }

    // MARK: External changes

    /// Rescans the tree off the main thread (the FSEvents watcher and app activation call this). Nothing
    /// changes, not even the revision, when the tree is the same, which is how the echo of the app's own
    /// operations is skipped: they updated the tree already.
    public func refreshFiles() async {
        let generation = filesGeneration
        let scanned = await FileNode.scan(root)
        if generation == filesGeneration, followExternalMoves(scanned: scanned) { engine.send(.recompile) }
        checkMissing()                    // also when the tree looks unchanged: a delete and a recreate may coalesce
        await reloadChangedFiles()
        guard generation == filesGeneration, scanned != files else { return }
        files = scanned
        filesGeneration += 1
        structureChanged()
        engine.send(.recompile)           // a file that appeared may be the one a diagnostic is missing
    }
}
