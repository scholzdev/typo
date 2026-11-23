import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

/// Files deleted outside the app, and the core operations behind undo of file operations. Temp folders and a fake Trash.
@Suite(.serialized) @MainActor struct FileSafetyTests {
    private func rel(_ s: String) -> RelPath { RelPath(s)! }
    private func exists(_ root: URL, _ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appending(path: path).path) }
    private func text(_ root: URL, _ path: String) throws -> String { try String(contentsOf: root.appending(path: path), encoding: .utf8) }
    private func delete(_ root: URL, _ path: String) throws { try FileManager.default.removeItem(at: root.appending(path: path)) }

    // MARK: Deleted on disk

    @Test func deletedFileIsMarkedAndNeverRecreatedUntilSavedAgain() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        p.selectedFile = rel("a.typ")
        try delete(root, "a.typ")
        await p.refreshFiles()
        #expect(a.isMissingOnDisk)
        type(a, "more ", at: 0)
        try await p.saveAll()
        #expect(!exists(root, "a.typ"))
        #expect(p.hasUnsavedChanges && p.unsavedMissingFiles() == [rel("a.typ")])
        try await p.saveAgain(rel("a.typ"))
        #expect(try text(root, "a.typ") == "more alpha\n")
        #expect(!a.isMissingOnDisk && !a.isDirty && !p.hasUnsavedChanges)
        #expect(p.allFiles.contains(rel("a.typ")))
    }

    @Test func saveRacingTheWatcherDoesNotRecreate() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        try delete(root, "a.typ")
        type(a, "x", at: 0)
        try await p.saveAll()                                   // before any refresh
        #expect(!exists(root, "a.typ") && a.isMissingOnDisk)
    }

    @Test func saveAgainWritesACleanBufferAndItsFolder() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "d/a.typ": "alpha\n"])
        let a = try await p.open(rel("d/a.typ"))
        try delete(root, "d")
        await p.refreshFiles()
        #expect(a.isMissingOnDisk && p.unsavedMissingFiles().isEmpty)    // clean: nothing to ask at quit
        try await p.saveAgain(rel("d/a.typ"))
        #expect(try text(root, "d/a.typ") == "alpha\n")
    }

    @Test func fileThatComesBackClearsTheMark() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        try delete(root, "a.typ")
        await p.refreshFiles()
        #expect(a.isMissingOnDisk)
        try "alpha\n".write(to: root.appending(path: "a.typ"), atomically: true, encoding: .utf8)   // git checkout
        await p.refreshFiles()
        #expect(!a.isMissingOnDisk)
    }

    @Test func closeDropsTheBufferAndShowsTheMain() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        p.selectedFile = rel("a.typ")
        type(a, "x", at: 0)
        try delete(root, "a.typ")
        await p.refreshFiles()
        p.closeMissing(rel("a.typ"))
        #expect(p.buffer(for: rel("a.typ")) == nil && p.selectedFile == rel("main.typ"))
        #expect(!p.hasUnsavedChanges && !exists(root, "a.typ"))
        _ = await p.settle()
        #expect(await p.engine.overlayText(rel("a.typ")) == nil)
    }

    @Test func movingAFolderWithAMissingDirtyFileFinishes() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "d/x.typ": "x\n", "d/y.typ": "y\n"])
        let x = try await p.open(rel("d/x.typ"))
        type(x, "edit ", at: 0)
        try delete(root, "d/x.typ")
        try await p.rename(rel("d"), to: "e")                  // the quiesce loop must not wait for x forever
        #expect(x.path == rel("e/x.typ") && x.isMissingOnDisk)
        #expect(!exists(root, "e/x.typ") && exists(root, "e/y.typ"))
    }

    // MARK: What undo of a file operation does

    @Test func renameBackKeepsTheBufferAndItsText() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        type(a, "X", at: 0)
        p.selectedFile = rel("a.typ")
        let new = try await p.rename(rel("a.typ"), to: "b.typ")
        try await p.rename(new, to: "a.typ")                    // Undo Rename
        #expect(exists(root, "a.typ") && !exists(root, "b.typ"))
        #expect(p.buffer(for: rel("a.typ")) === a && a.storage.string == "Xalpha\n" && p.selectedFile == rel("a.typ"))
    }

    @Test func trashedItemComesBackFromTheTrash() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "d/x.typ": "x\n"])
        let sink = FileManager.default.temporaryDirectory.appending(path: "typstcore-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sink, withIntermediateDirectories: true)
        p.trash = { url in
            let dst = sink.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dst)
            return dst
        }
        let x = try await p.open(rel("d/x.typ"))
        type(x, "saved ", at: 0)
        let trashed = try await p.moveToTrash(rel("d"))
        #expect(!exists(root, "d") && trashed == sink.appending(path: "d"))
        try await p.restore(fromTrash: trashed, to: rel("d"))   // Undo Move to Trash
        #expect(try text(root, "d/x.typ") == "saved x\n")
        #expect(p.allFiles.contains(rel("d/x.typ")))
        let again = try await p.moveToTrash(rel("d"))           // Redo
        try FileManager.default.createDirectory(at: root.appending(path: "d"), withIntermediateDirectories: true)
        await #expect(throws: ProjectError.self) { try await p.restore(fromTrash: again, to: rel("d")) }   // the name is taken
        #expect(FileManager.default.fileExists(atPath: again.path))
    }

    // MARK: Renamed or moved in Finder

    private func mv(_ root: URL, _ a: String, _ b: String) throws {
        try FileManager.default.createDirectory(at: root.appending(path: b).deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: root.appending(path: a), to: root.appending(path: b))
    }

    @Test func fileRenamedInFinderIsFollowedWithItsUnsavedText() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        p.selectedFile = rel("a.typ")
        type(a, "more ", at: 0)
        try mv(root, "a.typ", "b.typ")
        await p.refreshFiles()
        #expect(a.path == rel("b.typ") && p.buffer(for: rel("b.typ")) === a && !a.isMissingOnDisk)
        #expect(a.storage.string == "more alpha\n" && a.isDirty && p.selectedFile == rel("b.typ"))
        try await p.saveAll()
        #expect(try text(root, "b.typ") == "more alpha\n" && !exists(root, "a.typ"))
    }

    @Test func renameAfterASaveIsStillFollowed() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        type(a, "x", at: 0)
        try await p.saveAll()                                   // the atomic write gives the file a new identity
        try mv(root, "a.typ", "b.typ")
        await p.refreshFiles()
        #expect(a.path == rel("b.typ") && !a.isMissingOnDisk)
    }

    @Test func fileMovedOutOfTheProjectIsMissing() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        let outside = FileManager.default.temporaryDirectory.appending(path: "typstcore-out-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: root.appending(path: "a.typ"), to: outside)
        await p.refreshFiles()
        #expect(a.path == rel("a.typ") && a.isMissingOnDisk)
    }

    @Test func folderRenamedInFinderIsFollowedPerFile() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "ch/a.typ": "alpha\n", "ch/b.typ": "beta\n"])
        let a = try await p.open(rel("ch/a.typ"))
        let b = try await p.open(rel("ch/b.typ"))
        try mv(root, "ch", "kap")
        await p.refreshFiles()
        #expect(a.path == rel("kap/a.typ") && b.path == rel("kap/b.typ") && !a.isMissingOnDisk && !b.isMissingOnDisk)
    }

    // MARK: Drop onto a name clash

    private func sink(_ p: Project) throws -> URL {
        let sink = FileManager.default.temporaryDirectory.appending(path: "typstcore-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sink, withIntermediateDirectories: true)
        p.trash = { url in
            let dst = sink.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dst)
            return dst
        }
        return sink
    }

    @Test func replacingTrashesTheOldItemAndUndoPutsBothBack() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "new\n", "f/a.typ": "old\n"])
        let trash = try sink(p)
        let trashed = try await p.replacing(rel("f/a.typ"), with: rel("a.typ"))
        #expect(try text(root, "f/a.typ") == "new\n" && !exists(root, "a.typ"))
        #expect(try String(contentsOf: trashed, encoding: .utf8) == "old\n" && trashed.resolvingSymlinksInPath().path.hasPrefix(trash.resolvingSymlinksInPath().path))
        try await p.undoReplacing(rel("f/a.typ"), from: rel("a.typ"), trashed: trashed)
        #expect(try text(root, "a.typ") == "new\n" && text(root, "f/a.typ") == "old\n")
    }

    @Test func keepBothNameComesFromAvailableName() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "new\n", "f/a.typ": "old\n"])
        let name = p.availableName(for: "a.typ", in: rel("f"), copy: false, isFolder: false)
        #expect(name == "a 2.typ")
        let moved = try await p.move(rel("a.typ"), into: rel("f"), named: name)
        #expect(moved == rel("f/a 2.typ"))
    }
}
