import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// The way back from a file operation. Performing it returns the way forward again, so undo and redo alternate;
/// the Trash location is only known once an item went there, which is why each step yields the next.
struct FileUndo: Sendable {
    let perform: @MainActor @Sendable (FilesController) async throws -> FileUndo

    static func moving(_ from: RelPath, to: RelPath) -> FileUndo {
        FileUndo { c in
            try await c.relocate(from, to: to)
            return moving(to, to: from)
        }
    }

    /// Undo of a drop's Replace: the moved item goes back, then the trashed one is restored, in that order.
    static func replaced(_ dest: RelPath, from path: RelPath, trashed: URL) -> FileUndo {
        FileUndo { c in
            try await c.project.undoReplacing(dest, from: path, trashed: trashed)
            c.relocated(dest, to: path)
            c.model.listSelection = dest
            return replacing(dest, from: path)
        }
    }

    private static func replacing(_ dest: RelPath, from path: RelPath) -> FileUndo {
        FileUndo { c in
            let trashed = try await c.project.replacing(dest, with: path)
            c.trashed(dest)
            c.relocated(path, to: dest)
            return replaced(dest, from: path, trashed: trashed)
        }
    }

    /// Undo of New File, New Folder and Duplicate; redo of Move to Trash.
    static func trashing(_ path: RelPath) -> FileUndo {
        FileUndo { c in
            let trashed = try await c.project.moveToTrash(path)
            c.trashed(path)
            return restoring(trashed, to: path)
        }
    }

    static func restoring(_ trashed: URL, to path: RelPath) -> FileUndo {
        FileUndo { c in
            do { try await c.project.restore(fromTrash: trashed, to: path) } catch {
                throw ProjectError.operationFailed("\(error.localizedDescription) To get it back, open the Trash in Finder and choose Put Back.")
            }
            c.model.listSelection = path
            c.track([path])
            return trashing(path)
        }
    }
}

extension FilesController {
    /// Puts `back` on the window's undo stack as "Undo `name`". Undoing registers the way forward right away,
    /// while the undo manager is still undoing, so it lands on the redo stack; the operation itself runs after.
    func registerUndo(_ name: String, _ back: FileUndo) {
        guard let um = undoManager else { return }
        let own = um.groupingLevel == 0 && !um.isUndoing && !um.isRedoing
        if own { um.beginUndoGrouping() }
        um.registerUndo(withTarget: self) { c in
            MainActor.assumeIsolated {
                let verb = c.undoManager?.isUndoing == true ? "Undo" : "Redo"
                let done = Task {
                    do { return try await back.perform(c) } catch {
                        c.fail("Couldn\u{2019}t \(verb) \(name)", error)
                        throw error
                    }
                }
                c.registerUndo(name, FileUndo { c in try await done.value.perform(c) })
            }
        }
        um.setActionName(name)
        if own { um.endUndoGrouping() }
    }

    /// Rename and move, also when undone or redone: the move, the sidebar following it, then Xcode's offer to update
    /// the path strings that pointed at the item. They are read before the move; nothing is edited if it fails.
    func relocate(_ path: RelPath, to new: RelPath) async throws {
        let updates = project.referenceUpdates(moving: path, to: new)
        _ = try await (new.parent == path.parent ? project.rename(path, to: new.name) : project.move(path, into: new.parent, named: new.name))
        relocated(path, to: new)
        guard updates.count > 0 else { return }
        let files = updates.edits.keys.map(\.raw).sorted()
        guard confirm("Update \(updates.count) reference\(updates.count == 1 ? "" : "s") in \(files.count) file\(files.count == 1 ? "" : "s")?", files.joined(separator: "\n"), ok: "Update", cancel: "Don\u{2019}t Update") else { return }
        do { try await project.updateReferences(updates) } catch { fail("Couldn\u{2019}t Update the References", error) }
    }
}

extension View {
    /// File operations register on this window's undo manager, and saves keep snapshots of the project.
    func fileHistory(_ files: FilesController) -> some View { modifier(FileHistoryHook(files: files)) }
}

private struct FileHistoryHook: ViewModifier {
    let files: FilesController
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .onChange(of: undoManager, initial: true) { files.undoManager = undoManager }
            .onAppear { files.project.history.folder = LocalHistory.folder(for: files.project.rootURL) }
    }
}
