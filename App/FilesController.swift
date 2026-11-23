import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What the Files tab, its context menu, the "+" button and the File menu share: the operations on the
/// sidebar selection, and the watcher that keeps the tree in step with Finder. The protocol lives in core
/// (`Project.rename`, `move`, `moveToTrash`, ...); this only decides targets and shows errors.
@MainActor @Observable final class FilesController {
    let project: Project
    let model: SidebarModel
    @ObservationIgnored private var watcher: FileWatcher?
    /// The window's: Cmd-Z with the file list focused undoes file operations (the text view has the buffer's).
    @ObservationIgnored var undoManager: UndoManager?

    init(project: Project, model: SidebarModel) {
        self.project = project
        self.model = model
    }

    var selection: RelPath? { model.listSelection }

    /// The folder a new item goes into: the selected folder, the selected file's folder, else the root.
    private func folder(near path: RelPath?) -> RelPath? {
        guard let path else { return nil }
        return project.isDirectory(path) ? path : path.parent
    }

    // MARK: Create

    func newFile(near path: RelPath? = nil) { create(folder: false, near: path ?? selection) }
    func newFolder(near path: RelPath? = nil) { create(folder: true, near: path ?? selection) }
    /// From the list's empty space: always the project root, whatever is selected.
    func newFileInRoot() { create(folder: false, near: nil) }
    func newFolderInRoot() { create(folder: true, near: nil) }

    /// The item is created at once under its placeholder name and its row goes into inline editing, so the
    /// name is chosen through the same rename as any other.
    private func create(folder isFolder: Bool, near path: RelPath?) {
        let parent = folder(near: path)
        let name = project.availableName(for: isFolder ? "untitled folder" : "Untitled.typ", in: parent, copy: false, isFolder: isFolder)
        do {
            let new = isFolder ? try project.createFolder(named: name, in: parent) : try project.createFile(named: name, in: parent)
            model.tab = .files
            expandAncestors(of: new)
            model.listSelection = new
            model.renaming = new
            track([new])
            registerUndo(isFolder ? "New Folder" : "New File", .trashing(new))
        } catch {
            fail("Couldn’t Create the Item", error)
        }
    }

    private func expandAncestors(of path: RelPath) {
        var p = path.parent
        while let f = p { model.expanded.insert(f); p = f.parent }
    }

    // MARK: Rename, duplicate, trash, move

    func beginRename(_ path: RelPath? = nil) {
        guard let path = path ?? selection else { return }
        model.tab = .files
        model.listSelection = path
        model.renaming = path
    }

    func cancelRename() {
        model.renaming = nil
        flushRefresh()
    }

    func commitRename(_ path: RelPath, to name: String) {
        model.renaming = nil
        guard name != path.name else { flushRefresh(); return }
        Task {
            do {
                let new = try project.renameTarget(path, to: name)
                if new != path {
                    try await relocate(path, to: new)
                    registerUndo("Rename", .moving(new, to: path))
                }
            } catch { fail("Couldn’t Rename “\(path.name)”", error) }
            flushRefresh()
        }
    }

    func duplicate(_ path: RelPath? = nil) {
        guard let path = path ?? selection else { return }
        Task {
            do {
                let copy = try await project.duplicate(path)
                model.listSelection = copy
                track([copy])
                registerUndo("Duplicate", .trashing(copy))
            } catch { fail("Couldn’t Duplicate “\(path.name)”", error) }
        }
    }

    func moveToTrash(_ path: RelPath? = nil) {
        guard let path = path ?? selection else { return }
        let count = files(under: path)
        if project.isDirectory(path), count > 1 {
            guard confirm("Move “\(path.name)” and its \(count) files to the Trash?", "You can restore them from the Trash with Put Back.", ok: "Move to Trash") else { return }
        }
        Task {
            do {
                let trashed = try await project.moveToTrash(path)
                self.trashed(path)
                registerUndo("Move to Trash", .restoring(trashed, to: path))
            } catch { fail("Couldn’t Move “\(path.name)” to the Trash", error) }
        }
    }

    private func files(under path: RelPath) -> Int {
        func count(_ nodes: [FileNode]) -> Int { nodes.reduce(0) { $0 + ($1.isDirectory ? count($1.children ?? []) : 1) } }
        func find(_ nodes: [FileNode]) -> FileNode? {
            for n in nodes { if n.id == path { return n }; if path.isAtOrUnder(n.id), let f = find(n.children ?? []) { return f } }
            return nil
        }
        return find(project.files).map { $0.isDirectory ? count($0.children ?? []) : 1 } ?? 1
    }

    /// A drop on the list: rows dragged within it move into `folder` (nil = root), Finder items are copied in.
    func drop(_ urls: [URL], into folder: RelPath?) {
        Task {
            do {
                var new: [RelPath] = []
                for p in urls.compactMap(project.relPath(of:)) {
                    guard var dest = RelPath.make(p.name, in: folder), dest != p else { continue }
                    if FileManager.default.fileExists(atPath: project.url(for: dest).path) {
                        switch askNameClash(dest.name) {
                        case .stop: return finishDrop(new, folder)
                        case .keepBoth:
                            let name = project.availableName(for: p.name, in: folder, copy: false, isFolder: project.isDirectory(p))
                            dest = RelPath.make(name, in: folder) ?? dest
                        case .replace:
                            let trashed = try await project.replacing(dest, with: p)
                            self.trashed(dest)
                            relocated(p, to: dest)
                            registerUndo("Move", .replaced(dest, from: p, trashed: trashed))
                            new.append(dest)
                            continue
                        }
                    }
                    try await relocate(p, to: dest)
                    registerUndo("Move", .moving(dest, to: p))
                    new.append(dest)
                }
                let imported = try project.importItems(urls.filter { project.relPath(of: $0) == nil }, into: folder)
                track(imported)
                new += imported
                finishDrop(new, folder)
            } catch {
                fail("Couldn’t Move the Items", error)
                finishDrop([], nil)
            }
        }
    }

    private func finishDrop(_ new: [RelPath], _ folder: RelPath?) {
        if let folder, !new.isEmpty { model.expanded.insert(folder) }
        if let first = new.first { model.listSelection = first }
        if let q = model.quickLook, !FileManager.default.fileExists(atPath: project.url(for: q).path) { model.quickLook = nil }
    }

    private enum NameClash { case keepBoth, stop, replace }

    /// Finder's prompt for moving onto an existing name.
    private func askNameClash(_ name: String) -> NameClash {
        let alert = NSAlert()
        alert.messageText = "An item named \u{201C}\(name)\u{201D} already exists in this location."
        alert.informativeText = "Do you want to replace it with the one you\u{2019}re moving?"
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Replace")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertThirdButtonReturn: return .replace
        default: return .stop
        }
    }

    /// The sidebar keeps paths too: selection, expanded folders and the Quick Look file follow the rename.
    func relocated(_ old: RelPath, to new: RelPath) {
        model.expanded = Set(model.expanded.map { $0.replacing(old, with: new) ?? $0 })
        if let s = model.listSelection?.replacing(old, with: new) { model.listSelection = s }
        if let q = model.quickLook?.replacing(old, with: new) { model.quickLook = q }
        track([old, new])
    }

    // MARK: Watching

    func startWatching() {
        watcher = watcher ?? FileWatcher(root: project.rootURL, isStructural: { [weak self] in self?.isStructural($0, $1) ?? false },
                                         isOpen: { [weak self] in self?.isOpenFile($0) ?? false },
                                         onChange: { [weak self] in self?.filesChanged() },
                                         onContent: { [weak self] in Task { await self?.project.reloadChangedFiles() } })
    }

    func stopWatching() { watcher = nil }

    /// Whether an FSEvents event changes the tree. Autosave replaces files in place through a temporary file next
    /// to them, which reports creations and renames: hidden names, sandbox temporaries (".sb-") and a created or
    /// renamed path that is already in the tree (and still exists) are not structural.
    private func isStructural(_ path: String, _ flags: FileWatcher.Flags) -> Bool {
        let root = realRoot
        guard path.hasPrefix(root) else { return true }
        let rel = String(path.dropFirst(root.count))
        if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") || $0.contains(".sb-") }) { return false }
        if flags.contains(.removed) { return true }
        func known(_ nodes: [FileNode]) -> Bool { nodes.contains { $0.id.raw == rel || (rel.hasPrefix($0.id.raw + "/") && known($0.children ?? [])) } }
        return !(known(project.files) && FileManager.default.fileExists(atPath: path))
    }

    /// FSEvents reports real paths ("/private/tmp/x"), which `resolvingSymlinksInPath` would strip to "/tmp/x".
    private var realRoot: String {
        let path = project.rootURL.path
        guard let r = realpath(path, nil) else { return path + "/" }
        defer { free(r) }
        return String(cString: r) + "/"
    }

    private func isOpenFile(_ path: String) -> Bool {
        let root = realRoot
        return path.hasPrefix(root) && RelPath(String(path.dropFirst(root.count))).flatMap(project.buffer(for:)) != nil
    }

    /// Also called when the app becomes active. Held back while a name is being edited, so the row stays.
    func filesChanged() {
        if model.renaming != nil { model.pendingRefresh = true } else { Task { await project.refreshFiles() } }
    }

    private func flushRefresh() {
        guard model.pendingRefresh else { return }
        model.pendingRefresh = false
        Task { await project.refreshFiles() }
    }

    func trashed(_ path: RelPath) {
        if model.listSelection?.isAtOrUnder(path) == true { model.listSelection = nil }
        if model.quickLook?.isAtOrUnder(path) == true { model.quickLook = nil }
        track([path])
    }

    /// Settings' "Add and remove files automatically": the git index follows items created, renamed, moved or
    /// trashed here (undo and redo too), then the Changes list refreshes.
    func track(_ paths: [RelPath]) {
        guard SourceControl.addsAndRemovesFiles, project.isRepository, !paths.isEmpty else { return }
        let project = project
        Task {
            await project.track(paths)
            NotificationCenter.default.post(name: .gitNeedsRefresh, object: project)
        }
    }

    func fail(_ title: String, _ error: any Error) {
        showAlert(title, error.localizedDescription)
    }
}
