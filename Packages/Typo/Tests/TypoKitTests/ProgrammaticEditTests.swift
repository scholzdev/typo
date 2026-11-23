import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct ProgrammaticEditTests {
    @Test @MainActor func editsAClosedFileAsOneUndoStep() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "#include \"b.typ\"\nAlpha", "b.typ": "Beta gamma Beta"])
        let b = RelPath("b.typ")!
        #expect(p.buffer(for: b) == nil)
        try await p.edit(b, [Replacement(range: NSRange(location: 11, length: 4), text: "Omega"),
                             Replacement(range: NSRange(location: 0, length: 4), text: "Delta")])
        let buffer = try #require(p.buffer(for: b))
        #expect(buffer.storage.string == "Delta gamma Omega")
        #expect(buffer.isDirty && p.selectedFile != b)
        #expect(TestEnv.pdfText(try await p.exportPDF()).contains("Delta gamma Omega"))
        buffer.undoManager.undo()
        #expect(buffer.storage.string == "Beta gamma Beta")
        buffer.undoManager.redo()
        #expect(buffer.storage.string == "Delta gamma Omega")
        try await p.saveAll()
        #expect(try String(contentsOf: root.appending(path: "b.typ"), encoding: .utf8) == "Delta gamma Omega")
    }
}
