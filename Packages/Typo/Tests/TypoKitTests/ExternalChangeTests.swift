import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

/// Content changed on disk while the file is open (design/14d-files-safety.md, "Changed on disk").
@Suite(.serialized) @MainActor struct ExternalChangeTests {
    private func rel(_ s: String) -> RelPath { RelPath(s)! }
    private func text(_ root: URL, _ path: String) throws -> String { try String(contentsOf: root.appending(path: path), encoding: .utf8) }
    private func write(_ root: URL, _ path: String, _ s: String) throws { try s.write(to: root.appending(path: path), atomically: true, encoding: .utf8) }

    @Test func cleanBufferTakesTheDiskText() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        try write(root, "a.typ", "alpha\nbeta\n")
        await p.refreshFiles()
        #expect(a.storage.string == "alpha\nbeta\n" && !a.isDirty && !p.hasUnsavedChanges && !a.isChangedOnDisk)
        try await p.saveAll()
        #expect(try text(root, "a.typ") == "alpha\nbeta\n")
    }

    @Test func dirtyBufferIsAConflictUntilResolved() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        type(a, "mine ", at: 0)
        try write(root, "a.typ", "theirs\n")
        await p.refreshFiles()
        #expect(a.isChangedOnDisk && a.storage.string == "mine alpha\n")
        try await p.saveAll()
        #expect(try text(root, "a.typ") == "theirs\n" && a.isDirty)
        try await p.keepMine(rel("a.typ"))
        #expect(try text(root, "a.typ") == "mine alpha\n" && !a.isDirty && !a.isChangedOnDisk)
        await p.refreshFiles()
        #expect(!a.isChangedOnDisk)                                 // our own write is not an external change
    }

    @Test func useDiskLoadsTheDiskText() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        type(a, "mine ", at: 0)
        try write(root, "a.typ", "theirs\n")
        await p.refreshFiles()
        await p.useDisk(rel("a.typ"))
        #expect(a.storage.string == "theirs\n" && !a.isDirty && !a.isChangedOnDisk)
        try await p.saveAll()
        #expect(try text(root, "a.typ") == "theirs\n")
    }

    @Test func ownSaveIsNotAnExternalChange() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        type(a, "x", at: 0)
        try await p.saveAll()
        type(a, "y", at: 0)                                          // dirty again: a false conflict would show here
        await p.refreshFiles()
        #expect(!a.isChangedOnDisk && a.storage.string == "yxalpha\n")
    }

    @Test func changedAndRenamedInFinderStillEndsCorrectly() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let a = try await p.open(rel("a.typ"))
        try "changed\n".write(to: root.appending(path: "a.typ"), atomically: false, encoding: .utf8)   // in place: the file keeps its identity
        try FileManager.default.moveItem(at: root.appending(path: "a.typ"), to: root.appending(path: "b.typ"))
        await p.refreshFiles()
        #expect(p.buffer(for: rel("b.typ")) === a && a.storage.string == "changed\n" && !a.isDirty)
    }
}
