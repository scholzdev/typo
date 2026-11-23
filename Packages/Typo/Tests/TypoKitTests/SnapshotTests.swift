import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

/// Snapshots go to a temp folder, never the real Application Support; the clock is injected.
@Suite @MainActor struct SnapshotTests {
    private func rel(_ s: String) -> RelPath { RelPath(s)! }

    private func store() -> URL { FileManager.default.temporaryDirectory.appending(path: "typstcore-snapshots-\(UUID().uuidString)") }

    @Test func savesTakeASnapshotAtMostEveryTenMinutes() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "ch/a.typ": "a\n", "refs.bib": "@book{x}\n", "fig.png": "png"])
        p.history.folder = store()
        var t = Date(timeIntervalSince1970: 1_000_000)
        p.history.now = { t }
        let m = try await p.open(rel("main.typ"))
        func edit() async throws {
            type(m, "x", at: 0)
            try await p.saveAll()
            await p.history.writing?.value
        }
        try await edit()                                         // the first save since opening
        let first = try #require(p.snapshots().first)
        #expect(first.date == t)
        let files = await p.files(in: first)
        #expect(files.map(\.path.raw) == ["ch/a.typ", "main.typ", "refs.bib"] && files.allSatisfy { $0.state == .unchanged })
        #expect(files.first { $0.path == rel("main.typ") }?.text == "x= Hi\n")
        t += 300
        try await edit()
        #expect(p.snapshots().count == 1)
        t += 301
        try await edit()
        #expect(p.snapshots().map(\.date) == [t, t - 601])
        try await p.saveAll()                                    // nothing to write: no snapshot either
        #expect(await p.files(in: p.snapshots()[1]).first { $0.path == rel("main.typ") }?.state == .changed)
        #expect(LocalHistory.folder(for: p.rootURL).lastPathComponent.count == 64)
    }

    @Test func retentionKeepsADayThenOnePerDayForAMonthAtMost200() {
        let now = Date(timeIntervalSince1970: 10_000_000), day = 86_400.0
        let recent = (0..<30).map { now - Double($0) * 600 }
        let twoDaysAgo = [now - 2 * day - 3600, now - 2 * day - 7200]
        let old = now - 40 * day
        #expect(LocalHistory.expired(recent + twoDaysAgo + [old], now: now) == [twoDaysAgo[1], old])
        let many = (0..<250).map { now - Double($0) * 60 }
        #expect(LocalHistory.expired(many, now: now) == Set(many.suffix(50)))
    }

    @Test func restoreGoesThroughTheBufferAsOneUndoStep() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n", "d/notes.md": "n\n"])
        p.history.folder = store()
        let a = try await p.open(rel("a.typ"))
        a.undoManager.groupsByEvent = false
        await p.takeSnapshot().value
        type(a, "changed ", at: 0)
        try FileManager.default.removeItem(at: root.appending(path: "d"))
        let files = await p.files(in: try #require(p.snapshots().first))
        #expect(files.map(\.state) == [.changed, .missing, .unchanged])     // a.typ, d/notes.md, main.typ
        try await p.restore(files[0])
        #expect(a.storage.string == "alpha\n" && a.isDirty)
        a.undoManager.undo()
        #expect(a.storage.string == "changed alpha\n")
        try await p.restore(files[1])                            // gone with its folder: created again
        #expect(p.buffer(for: rel("d/notes.md"))?.storage.string == "n\n")
        try await p.saveAll()
        #expect(try String(contentsOf: root.appending(path: "d/notes.md"), encoding: .utf8) == "n\n")
    }
}
