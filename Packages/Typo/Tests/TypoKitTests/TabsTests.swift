import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

/// Editor tabs (design/14h): the pure list, and how a project's tabs follow selection, edits, moves, the Trash and relaunch.
@Suite(.serialized) @MainActor struct TabsTests {
    private func rel(_ s: String) -> RelPath { RelPath(s)! }
    private func names(_ t: TabList) -> [String] { t.paths.map(\.raw) }
    private let files = ["main.typ": "= Hi\n", "a.typ": "a\n", "b.typ": "b\n", "c.typ": "c\n", "d/x.typ": "x\n"]

    // MARK: TabList

    @Test func titleShowsTheFolderOnlyForDuplicateNames() {
        var t = TabList()
        for p in ["main.typ", "a/x.typ", "b/x.typ"] { t.show(rel(p), permanent: true) }
        #expect(t.title(of: rel("main.typ")) == "main.typ")
        #expect(t.title(of: rel("a/x.typ")) == "x.typ — a" && t.title(of: rel("b/x.typ")) == "x.typ — b")
    }

    @Test func previewIsReplacedInPlaceAndPermanentGoesAfterTheActiveTab() {
        var t = TabList()
        t.show(rel("a"), permanent: true)
        t.show(rel("b"), permanent: false)
        t.show(rel("c"), permanent: true)
        #expect(names(t) == ["a", "b", "c"] && t.preview == rel("b"))
        t.show(rel("d"), permanent: false)
        #expect(names(t) == ["a", "d", "c"] && t.preview == rel("d"))
        t.show(rel("e"), permanent: true, active: rel("a"))
        #expect(names(t) == ["a", "e", "d", "c"])
    }

    @Test func showingAnExistingTabNeverDuplicatesAndPermanentPins() {
        var t = TabList()
        t.show(rel("a"), permanent: false)
        t.show(rel("a"), permanent: false)
        #expect(names(t) == ["a"] && t.preview == rel("a"))
        t.show(rel("a"), permanent: true)
        #expect(names(t) == ["a"] && t.preview == nil)
    }

    @Test func closeShowsTheRightNeighbourThenTheLeftThenNothing() {
        var t = TabList()
        for p in ["a", "b", "c"] { t.show(rel(p), permanent: true) }
        #expect(t.close(rel("b"), active: rel("b")) == rel("c"))
        #expect(t.close(rel("c"), active: rel("c")) == rel("a"))
        #expect(t.close(rel("zzz"), active: rel("a")) == rel("a"))
        #expect(t.close(rel("a"), active: rel("a")) == nil)
        #expect(t.paths.isEmpty)
    }

    @Test func neighbourWraps() {
        var t = TabList()
        for p in ["a", "b", "c"] { t.show(rel(p), permanent: true) }
        #expect(t.neighbour(of: rel("c"), by: 1) == rel("a") && t.neighbour(of: rel("a"), by: -1) == rel("c"))
    }

    @Test func rekeyFollowsAFolderAndCodableRoundTrips() throws {
        var t = TabList()
        t.show(rel("d/x"), permanent: true)
        t.show(rel("d/y"), permanent: false)
        t.rekey(from: rel("d"), to: rel("e"))
        #expect(names(t) == ["e/x", "e/y"] && t.preview == rel("e/y"))
        #expect(try JSONDecoder().decode(TabList.self, from: JSONEncoder().encode(t)) == t)
        #expect(t.remove(atOrUnder: rel("e"), active: rel("e/x")) == nil && t.paths.isEmpty && t.preview == nil)
    }

    // MARK: Pinned tabs

    private func list(_ ps: String...) -> TabList {
        var t = TabList()
        for p in ps { t.show(rel(p), permanent: true) }
        return t
    }

    @Test func pinnedTabsSitFirstInPinOrderAndAreNeverThePreview() {
        var t = list("a", "b", "c")
        t.show(rel("p"), permanent: false)
        t.pin(rel("p"))
        #expect(names(t) == ["p", "a", "b", "c"] && t.preview == nil && t.pinned == [rel("p")])
        t.pin(rel("c"))
        t.pin(rel("c"))
        #expect(names(t) == ["p", "c", "a", "b"] && t.pinned == [rel("p"), rel("c")])
        t.show(rel("n"), permanent: true, active: rel("p"))
        #expect(names(t) == ["p", "c", "n", "a", "b"])
        t.show(rel("q"), permanent: false)
        #expect(names(t) == ["p", "c", "n", "a", "b", "q"] && t.preview == rel("q"))
    }

    @Test func unpinMovesTheTabBehindTheRemainingPinnedOnes() {
        var t = list("a", "b", "c")
        t.pin(rel("c")); t.pin(rel("b"))
        t.unpin(rel("c"))
        #expect(names(t) == ["b", "c", "a"] && t.pinned == [rel("b")])
    }

    @Test func aPinnedTabDoesNotClose() {
        var t = list("a", "b")
        t.pin(rel("b"))
        #expect(t.close(rel("b"), active: rel("b")) == rel("b") && names(t) == ["b", "a"])
        #expect(t.close(rel("a"), active: rel("b")) == rel("b") && names(t) == ["b"])
    }

    @Test func removingOrMovingKeepsPinnedConsistent() {
        var t = list("d/x", "d/y", "z")
        t.pin(rel("d/x")); t.pin(rel("z"))
        t.rekey(from: rel("d"), to: rel("e"))
        #expect(names(t) == ["e/x", "z", "e/y"] && t.pinned == [rel("e/x"), rel("z")])
        _ = t.remove(atOrUnder: rel("e"), active: nil)
        #expect(names(t) == ["z"] && t.pinned == [rel("z")])
        _ = t.remove(atOrUnder: rel("z"), active: nil)
        #expect(t.paths.isEmpty && t.pinned.isEmpty)
    }

    @Test func pinnedStateRoundTripsAndOldDataStillDecodes() throws {
        var t = list("a", "b", "c")
        t.pin(rel("c"))
        #expect(try JSONDecoder().decode(TabList.self, from: JSONEncoder().encode(t)) == t)
        let old = try JSONDecoder().decode(TabList.self, from: Data(#"{"paths":["a","b"],"preview":"b"}"#.utf8))
        #expect(names(old) == ["a", "b"] && old.preview == rel("b") && old.pinned.isEmpty)
        let odd = try JSONDecoder().decode(TabList.self, from: Data(#"{"paths":["a","b"],"pinned":["b","gone"]}"#.utf8))
        #expect(names(odd) == ["b", "a"] && odd.pinned == [rel("b")])
    }

    // MARK: Project

    @Test func selectingFilesUsesOnePreviewTabAndAnEditPinsIt() async throws {
        let (p, _) = try await TestEnv.project(files: files)
        #expect(names(p.tabs) == ["main.typ"] && p.tabs.preview == rel("main.typ"))
        p.select(rel("a.typ"))
        #expect(names(p.tabs) == ["a.typ"])                            // replaced the preview
        let a = try await p.open(rel("a.typ"))
        type(a, "x")
        #expect(p.tabs.preview == nil)
        p.select(rel("b.typ"))
        #expect(names(p.tabs) == ["a.typ", "b.typ"] && p.tabs.preview == rel("b.typ"))
        p.openPermanently(rel("b.typ"))
        #expect(p.tabs.preview == nil && p.selectedFile == rel("b.typ"))
    }

    @Test func aJumpAddsAPreviewTab() async throws {
        let (p, _) = try await TestEnv.project(files: files)
        p.openPermanently(rel("main.typ"))
        p.show(rel("c.typ"), range: NSRange(location: 0, length: 0))
        #expect(names(p.tabs) == ["main.typ", "c.typ"] && p.tabs.preview == rel("c.typ"))
    }

    @Test func movesAndFinderRenamesRekeyTabs() async throws {
        let (p, root) = try await TestEnv.project(files: files)
        p.openPermanently(rel("main.typ"))
        p.select(rel("d/x.typ")); p.openPermanently(rel("d/x.typ"))
        p.select(rel("a.typ")); p.openPermanently(rel("a.typ"))
        _ = try await p.open(rel("d/x.typ")); _ = try await p.open(rel("a.typ"))
        try await p.relocate(rel("d"), to: rel("e"))
        #expect(names(p.tabs) == ["main.typ", "e/x.typ", "a.typ"])
        try FileManager.default.moveItem(at: root.appending(path: "a.typ"), to: root.appending(path: "a2.typ"))
        await p.refreshFiles()
        #expect(names(p.tabs) == ["main.typ", "e/x.typ", "a2.typ"] && p.selectedFile == rel("a2.typ"))
    }

    @Test func trashRemovesTheTabAndShowsTheNeighbour() async throws {
        let (p, _) = try await TestEnv.project(files: files)
        let sink = FileManager.default.temporaryDirectory.appending(path: "typstcore-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sink, withIntermediateDirectories: true)
        p.trash = { url in
            let dst = sink.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dst)
            return dst
        }
        for f in ["main.typ", "a.typ", "b.typ"] { p.select(rel(f)); p.openPermanently(rel(f)) }
        p.select(rel("a.typ"))
        try await p.moveToTrash(rel("a.typ"))
        #expect(names(p.tabs) == ["main.typ", "b.typ"] && p.selectedFile == rel("b.typ"))
    }

    @Test func closingATabKeepsTheBufferAndItsUnsavedText() async throws {
        let (p, _) = try await TestEnv.project(files: files)
        p.select(rel("a.typ")); p.openPermanently(rel("a.typ"))
        p.openPermanently(rel("main.typ"))
        p.select(rel("a.typ"))
        let a = try await p.open(rel("a.typ"))
        type(a, "kept ", at: 0)
        p.closeTab(rel("a.typ"))
        #expect(names(p.tabs) == ["main.typ"] && p.selectedFile == rel("main.typ"))
        #expect(p.buffer(for: rel("a.typ")) === a && a.storage.string == "kept a\n" && a.isDirty)
        p.closeTab(rel("main.typ"))
        #expect(p.tabs.paths.isEmpty && p.selectedFile == nil)
    }

    @Test func tabsComeBackAfterReopeningWithoutMissingFiles() async throws {
        let (p, root) = try await TestEnv.project(files: files)
        defer { UserDefaults.standard.removeObject(forKey: "Tympan.tabs.\(p.id.raw)") }
        for f in ["a.typ", "b.typ"] { p.select(rel(f)); p.openPermanently(rel(f)) }
        p.select(rel("c.typ"))
        try FileManager.default.removeItem(at: root.appending(path: "a.typ"))
        let q = try await Project(id: p.id, root: root, main: rel("main.typ"), runtime: await TestEnv.runtime.value)
        #expect(names(q.tabs) == ["b.typ", "c.typ", "main.typ"] && q.tabs.preview == rel("c.typ"))
    }

    @Test func pinnedTabsSurviveCloseOthersAndCloseButNotTheTrashAndComeBackAfterReopening() async throws {
        let (p, root) = try await TestEnv.project(files: files)
        defer { UserDefaults.standard.removeObject(forKey: "Tympan.tabs.\(p.id.raw)") }
        let sink = FileManager.default.temporaryDirectory.appending(path: "typstcore-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sink, withIntermediateDirectories: true)
        p.trash = { url in
            let dst = sink.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dst)
            return dst
        }
        for f in ["main.typ", "a.typ", "b.typ", "c.typ"] { p.select(rel(f)); p.openPermanently(rel(f)) }
        p.togglePinTab(rel("b.typ")); p.togglePinTab(rel("a.typ"))
        #expect(names(p.tabs) == ["b.typ", "a.typ", "main.typ", "c.typ"])
        p.select(rel("b.typ"))
        p.closeTab(rel("b.typ"))
        #expect(names(p.tabs).first == "b.typ" && p.selectedFile == rel("b.typ"))
        p.closeOtherTabs(rel("c.typ"))
        #expect(names(p.tabs) == ["b.typ", "a.typ", "c.typ"] && p.selectedFile == rel("c.typ"))
        let q = try await Project(id: p.id, root: root, main: rel("main.typ"), runtime: await TestEnv.runtime.value)
        #expect(names(q.tabs).prefix(2) == ["b.typ", "a.typ"] && q.tabs.pinned == [rel("b.typ"), rel("a.typ")])
        try await p.moveToTrash(rel("a.typ"))
        #expect(names(p.tabs) == ["b.typ", "c.typ"] && p.tabs.pinned == [rel("b.typ")])
        p.togglePinTab(rel("b.typ"))
        #expect(p.tabs.pinned.isEmpty)
    }
}
