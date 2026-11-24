import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct BufferStateTests {
    @Test func restoredSelectionIsClampedToTheText() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "abcdef"])
        let b = try await p.open(RelPath("main.typ")!)
        #expect(b.restoredSelection == NSRange(location: 0, length: 0))            // default: caret at 0
        b.selection = NSRange(location: 4, length: 2)
        #expect(b.restoredSelection == NSRange(location: 4, length: 2))
        replace(b, NSRange(location: 2, length: 4), with: "")                      // text shrinks to "ab"
        #expect(b.restoredSelection == NSRange(location: 2, length: 0))
        b.selection = NSRange(location: 1, length: 9)
        #expect(b.restoredSelection == NSRange(location: 1, length: 1))
    }

    /// Overlapping saves (autosave, ⌘S, a Git action) must all finish: a waiter used to spin on the finished save
    /// task before its owner could clear it, freezing the main actor.
    @Test(.timeLimit(.minutes(1))) func overlappingSavesAllFinish() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "hello"])
        let b = try await p.open(RelPath("main.typ")!)
        for round in 0..<20 {
            type(b, "\(round)")
            async let a: Void = p.saveAll()
            async let c: Void = p.saveAll()
            async let d: Void = p.saveAll()
            _ = try await (a, c, d)
        }
        #expect(!b.isDirty && p.saving == nil)
    }

    @Test func saveWritesThePDFBesideTheDocumentWhenAsked() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "hello"])
        let pdf = root.appending(path: "main.pdf")
        let b = try await p.open(RelPath("main.typ")!)
        type(b, "!")
        try await p.saveAll()
        try await Task.sleep(for: .seconds(1))
        #expect(!FileManager.default.fileExists(atPath: pdf.path))               // off by default
        p.exportsPDFOnSave = true
        type(b, "?")
        try await p.saveAll()
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: pdf.path) { try await Task.sleep(for: .milliseconds(100)) }
        let data = try Data(contentsOf: pdf)
        #expect(data.starts(with: Data("%PDF".utf8)))
    }

    @Test func savingTheFirstPresenterNoteTurnsTheNotesStripOn() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Slide\n"])
        let b = try await p.open(RelPath("main.typ")!)
        p.detectPresenterContent()
        #expect(!p.preview.automaticNotes)
        type(b, "#metadata(\"Say hi\") <note>\n")
        try await p.saveAll()
        #expect(p.preview.automaticNotes)
    }

    @Test func readOnlyFolderSurfacesSaveErrorUntilNextSuccess() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "hello"])
        let fm = FileManager.default
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let b = try await p.open(RelPath("main.typ")!)
        type(b, "!")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)   // atomic writes need the folder, not the file
        await #expect(throws: ProjectError.self) { try await p.saveAll() }
        let message = try #require(p.saveError)
        #expect(message.contains("main.typ"))
        #expect(p.hasUnsavedChanges && b.isDirty)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try await p.saveAll()
        #expect(p.saveError == nil && !b.isDirty)
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "hello!")
    }
}
