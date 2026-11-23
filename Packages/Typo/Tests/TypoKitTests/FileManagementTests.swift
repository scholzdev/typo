import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

/// All in fresh temp folders (and an injected trash function), never the demo project or the user's Trash.
@Suite(.serialized) @MainActor struct FileManagementTests {
    private func rel(_ s: String) -> RelPath { RelPath(s)! }

    private func exists(_ root: URL, _ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appending(path: path).path) }

    private func text(_ root: URL, _ path: String) throws -> String { try String(contentsOf: root.appending(path: path), encoding: .utf8) }

    private func kind(_ e: ProjectError?) -> String {
        switch e {
        case nil: "none"
        case .invalidName: "invalidName"
        case .nameExists: "nameExists"
        case .notFound: "notFound"
        case .invalidMove: "invalidMove"
        case .operationFailed: "operationFailed"
        default: "other"
        }
    }

    private func failure<T>(_ body: () async throws -> T) async -> ProjectError? {
        do { _ = try await body(); return nil } catch { return error as? ProjectError ?? .operationFailed("\(error)") }
    }

    private func clean(_ p: Project) async throws {
        let r = try #require(await p.settle())
        #expect(r.snapshot.diagnostics.isEmpty, "\(r.snapshot.diagnostics.map(\.message))")
        #expect(r.snapshot.pageCount > 0)
    }

    private func overlaysExact(_ p: Project, _ paths: [RelPath]) async {
        for path in paths { #expect(await p.engine.overlayText(path) == p.buffer(for: path)?.storage.string, "\(path.raw)") }
    }

    // MARK: Rename

    @Test func renameOpenFileWithUnsavedEdits() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let b = try await p.open(rel("a.typ"))
        b.undoManager.groupsByEvent = false
        let storage = b.storage
        type(b, "EDIT ", at: 0)
        p.selectedFile = rel("a.typ")
        let new = try await p.rename(rel("a.typ"), to: "b.typ")
        #expect(new == rel("b.typ"))
        #expect(!exists(root, "a.typ"))
        #expect(try text(root, "b.typ") == "EDIT alpha\n")
        #expect(p.buffer(for: new) === b && b.storage === storage && b.path == new)
        #expect(p.buffer(for: rel("a.typ")) == nil)
        #expect(p.selectedFile == new)
        #expect(!b.isDirty)
        _ = await p.settle()
        #expect(await p.engine.overlayText(new) == b.storage.string)
        #expect(await p.engine.overlayText(rel("a.typ")) == nil)
        b.undoManager.undo()                                    // the undo history came along
        #expect(b.storage.string == "EDITalpha\n")
        _ = await p.settle()
        #expect(await p.engine.overlayText(new) == "EDITalpha\n")
        #expect(p.resyncCount == 0)
    }

    @Test func autosaveRacingARenameNeverResurrectsTheOldPath() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "alpha\n"])
        let b = try await p.open(rel("a.typ"))
        var current = "a.typ"
        for i in 0..<12 {
            p.autosaveDelay = .milliseconds(i % 4)
            type(b, "\(i % 10)", at: 0)                          // queues an autosave for the path about to change
            let next = current == "a.typ" ? "z.typ" : "a.typ"
            try await p.rename(rel(current), to: next)
            current = next
        }
        let expected = b.storage.string
        try await Task.sleep(for: .milliseconds(300))           // the writer has drained
        let other = current == "a.typ" ? "z.typ" : "a.typ"
        #expect(!exists(root, other))
        #expect(try text(root, current) == expected)
        #expect(b.path == rel(current))
    }

    @Test func renameMainThenMoveItsFolder() async throws {
        let recents = RecentProjects(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let root = FileManager.default.temporaryDirectory.appending(path: "typstcore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "archive"), withIntermediateDirectories: true)
        try "= Title\nBody\n".write(to: root.appending(path: "src/main.typ"), atomically: true, encoding: .utf8)
        try "#include \"part.typ\"\n".write(to: root.appending(path: "src/other.typ"), atomically: true, encoding: .utf8)
        try "Part\n".write(to: root.appending(path: "src/part.typ"), atomically: true, encoding: .utf8)
        let id = try recents.register(root: root, main: rel("src/main.typ"))
        let p = try await Project(id: id, root: root, main: rel("src/main.typ"), runtime: await TestEnv.runtime.value)
        p.autosaveDelay = nil
        p.recents = recents
        let b = try await p.open(rel("src/main.typ"))
        type(b, "More ", at: 0)
        try await clean(p)

        try await p.rename(rel("src/main.typ"), to: "paper.typ")
        #expect(p.main == rel("src/paper.typ"))
        #expect(recents.record(id)?.main == rel("src/paper.typ"))
        try await clean(p)
        await overlaysExact(p, [rel("src/paper.typ")])
        #expect(await p.engine.overlayText(rel("src/main.typ")) == nil)

        try await p.rename(rel("src"), to: "source")
        #expect(p.main == rel("source/paper.typ") && recents.record(id)?.main == rel("source/paper.typ"))
        try await clean(p)
        await overlaysExact(p, [rel("source/paper.typ")])

        try await p.move(rel("source"), into: rel("archive"))
        #expect(p.main == rel("archive/source/paper.typ") && recents.record(id)?.main == rel("archive/source/paper.typ"))
        #expect(p.buffer(for: p.main) === b)
        try await clean(p)
        await overlaysExact(p, [p.main])
        #expect(!exists(root, "source") && exists(root, "archive/source/paper.typ"))
        #expect(p.files.map(\.id.raw) == ["archive"])
    }

    @Test func renameFolderWithNestedOpenBuffers() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "chap/one.typ": "one\n", "chap/sub/two.typ": "two\n", "chap/notes.txt": "n\n"])
        let one = try await p.open(rel("chap/one.typ")), two = try await p.open(rel("chap/sub/two.typ"))
        let notes = try await p.open(rel("chap/notes.txt"))
        type(two, "ED ", at: 0)
        p.selectedFile = rel("chap/sub/two.typ")
        try await p.rename(rel("chap"), to: "chapters")
        #expect(!exists(root, "chap"))
        #expect(try text(root, "chapters/sub/two.typ") == "ED two\n")
        #expect(p.buffer(for: rel("chapters/one.typ")) === one)
        #expect(p.buffer(for: rel("chapters/sub/two.typ")) === two)
        #expect(p.buffer(for: rel("chapters/notes.txt")) === notes)
        #expect(p.buffer(for: rel("chap/one.typ")) == nil)
        #expect(p.selectedFile == rel("chapters/sub/two.typ"))
        #expect(p.files.map(\.id.raw) == ["chapters", "main.typ"])
        _ = await p.settle()
        await overlaysExact(p, [rel("chapters/one.typ"), rel("chapters/sub/two.typ"), rel("chapters/notes.txt")])
        for old in ["chap/one.typ", "chap/sub/two.typ"] { #expect(await p.engine.overlayText(rel(old)) == nil) }
    }

    @Test func extensionChangeUpdatesTheHighlighter() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "n.txt": "= Heading *x*\n"])
        let b = try await p.open(rel("n.txt"))
        func plain() -> Bool { (b.storage.attributes(at: 2, effectiveRange: nil) as NSDictionary).isEqual(Highlighter.base as NSDictionary) }
        #expect(!b.isTypst && plain())
        try await p.rename(rel("n.txt"), to: "n.typ")
        #expect(b.isTypst && b.path == rel("n.typ") && !plain())
        try await p.rename(rel("n.typ"), to: "n.bib")
        #expect(!b.isTypst && b.structured != nil)
        try await p.rename(rel("n.bib"), to: "n.txt")
        #expect(!b.isTypst && b.structured == nil)
    }

    @Test func moveFileIntoFolderAndToRoot() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "a\n", "docs/readme.md": "r\n"])
        let b = try await p.open(rel("a.typ"))
        let moved = try await p.move(rel("a.typ"), into: rel("docs"))
        #expect(moved == rel("docs/a.typ") && exists(root, "docs/a.typ") && !exists(root, "a.typ"))
        #expect(p.buffer(for: moved) === b)
        let back = try await p.move(moved, into: nil)
        #expect(back == rel("a.typ") && exists(root, "a.typ"))
        #expect(try await p.move(back, into: nil) == back)       // already there: nothing happens
        #expect(kind(await failure { try await p.move(rel("a.typ"), into: rel("main.typ")) }) == "notFound")
    }

    @Test func caseOnlyRename() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "b.typ": "b\n"])
        let b = try await p.open(rel("main.typ"))
        type(b, "Z ", at: 0)
        let new = try await p.rename(rel("main.typ"), to: "Main.typ")
        #expect(new == rel("Main.typ") && p.main == new)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.contains("Main.typ") && !names.contains("main.typ"))
        #expect(p.buffer(for: new) === b)
        #expect(try text(root, "Main.typ") == "Z = Hi\n")
        try await clean(p)
        await overlaysExact(p, [new])
        #expect(await p.engine.overlayText(rel("main.typ")) == nil)
    }

    @Test func renameFailuresChangeNothing() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "a\n"])
        let b = try await p.open(rel("a.typ"))
        type(b, "E", at: 0)
        #expect(kind(await failure { try await p.rename(rel("a.typ"), to: "main.typ") }) == "nameExists")
        #expect(kind(await failure { try await p.rename(rel("a.typ"), to: "") }) == "invalidName")
        #expect(kind(await failure { try await p.rename(rel("a.typ"), to: "x/y.typ") }) == "invalidName")
        #expect(kind(await failure { try await p.rename(rel("nope.typ"), to: "x.typ") }) == "notFound")
        #expect(p.buffer(for: rel("a.typ")) === b && exists(root, "a.typ"))
    }

    @Test func folderCannotMoveIntoItselfOrADescendant() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a/x.typ": "x\n", "a/b/y.typ": "y\n"])
        #expect(kind(await failure { try await p.move(rel("a"), into: rel("a")) }) == "invalidMove")
        #expect(kind(await failure { try await p.move(rel("a"), into: rel("a/b")) }) == "invalidMove")
        #expect(exists(root, "a/x.typ") && exists(root, "a/b/y.typ"))
        // "a2" is not a descendant of "a" even though the names share a prefix.
        try p.createFolder(named: "a2")
        #expect(try await p.move(rel("a"), into: rel("a2")) == rel("a2/a"))
    }

    // MARK: Create, duplicate

    @Test func createFileAndFolder() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "docs/x.md": "x\n"])
        let f = try p.createFile(named: "Untitled.typ", in: nil)
        #expect(f == rel("Untitled.typ") && exists(root, "Untitled.typ") && p.selectedFile == f)
        let b = try await p.open(f)
        #expect(b.storage.string.isEmpty)
        let nested = try p.createFile(named: "n.md", in: rel("docs"))
        #expect(nested == rel("docs/n.md"))
        let folder = try p.createFolder(named: "untitled folder")
        #expect(folder == rel("untitled folder") && p.files.contains { $0.id == folder && $0.isDirectory })
        #expect(p.availableName(for: "Untitled.typ", in: nil, copy: false) == "Untitled 2.typ")
        #expect(p.availableName(for: "untitled folder", in: nil, copy: false, isFolder: true) == "untitled folder 2")
        #expect(kind(failureNow { try p.createFile(named: "main.typ") }) == "nameExists")
        #expect(kind(failureNow { try p.createFile(named: "Main.TYP") }) == "nameExists" || exists(root, "Main.TYP") == false)
        #expect(kind(failureNow { try p.createFolder(named: "docs") }) == "nameExists")
        for bad in ["", "   ", ".", "..", ".hidden", "a/b", "a:b"] {
            #expect(kind(failureNow { try p.createFile(named: bad) }) == "invalidName", "\(bad)")
            #expect(kind(failureNow { try p.createFolder(named: bad) }) == "invalidName", "\(bad)")
        }
        #expect(kind(failureNow { try p.createFile(named: "q.typ", in: rel("missing")) }) == "notFound")
    }

    private func failureNow<T>(_ body: () throws -> T) -> ProjectError? {
        do { _ = try body(); return nil } catch { return error as? ProjectError ?? .operationFailed("\(error)") }
    }

    @Test func duplicateNaming() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "a\n", "docs/x.md": "x\n", "v1.2/f.txt": "f\n"])
        let b = try await p.open(rel("a.typ"))
        type(b, "NEW ", at: 0)
        #expect(try await p.duplicate(rel("a.typ")) == rel("a copy.typ"))
        #expect(try text(root, "a copy.typ") == "NEW a\n")        // the unsaved text
        #expect(try await p.duplicate(rel("a.typ")) == rel("a copy 2.typ"))
        #expect(try await p.duplicate(rel("a copy.typ")) == rel("a copy copy.typ"))
        #expect(try await p.duplicate(rel("docs")) == rel("docs copy") && exists(root, "docs copy/x.md"))
        #expect(try await p.duplicate(rel("v1.2")) == rel("v1.2 copy"))
        #expect(try await p.duplicate(rel("docs/x.md")) == rel("docs/x copy.md"))
        #expect(p.buffer(for: rel("a.typ")) === b)
        #expect(p.files.contains { $0.id == rel("a copy 2.typ") })
        #expect(kind(await failure { try await p.duplicate(rel("none.typ")) }) == "notFound")
    }

    // MARK: Trash

    /// The fake Trash: moves `url` into `sink` and returns where it went.
    private func moveInto(_ sink: URL, _ url: URL) throws -> URL {
        let dst = sink.appending(path: url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: dst)
        return dst
    }

    private func sink() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appending(path: "typstcore-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func trashSavesFirstThenClosesTheBuffer() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "a\n", "d/x.typ": "x\n"])
        let sink = try sink()
        var trashed: [String] = []
        p.trash = { url in trashed.append(url.lastPathComponent); return try moveInto(sink, url) }
        let a = try await p.open(rel("a.typ")), x = try await p.open(rel("d/x.typ"))
        type(a, "LAST ", at: 0)
        type(x, "XX ", at: 0)
        p.selectedFile = rel("d/x.typ")
        try await p.moveToTrash(rel("a.typ"))
        #expect(trashed == ["a.typ"])
        #expect(try String(contentsOf: sink.appending(path: "a.typ"), encoding: .utf8) == "LAST a\n")   // saved before it went
        #expect(!exists(root, "a.typ") && p.buffer(for: rel("a.typ")) == nil)
        _ = await p.settle()
        #expect(await p.engine.overlayText(rel("a.typ")) == nil)
        try await p.moveToTrash(rel("d"))
        #expect(try String(contentsOf: sink.appending(path: "d/x.typ"), encoding: .utf8) == "XX x\n")
        #expect(p.buffer(for: rel("d/x.typ")) == nil && p.selectedFile == nil)
        #expect(p.files.map(\.id.raw) == ["main.typ"])
        #expect(!p.hasUnsavedChanges)
        try await clean(p)
    }

    @Test func trashingTheMainFallsBack() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "other.typ": "Other\n", "z/more.typ": "More\n"])
        let sink = try sink()
        p.trash = { try moveInto(sink, $0) }
        _ = try await p.open(rel("other.typ"))
        p.selectedFile = rel("other.typ")
        try await p.moveToTrash(rel("main.typ"))
        #expect(p.main == rel("other.typ"))                    // the selected .typ
        try await clean(p)
        p.selectedFile = nil
        try await p.moveToTrash(rel("other.typ"))
        #expect(p.main == rel("other.typ"))                     // z/more.typ is not in the root: no fallback
    }

    @Test func trashingTheLastTypstFileLeavesNoDocument() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "notes.txt": "n\n"])
        let sink = try sink()
        p.trash = { try moveInto(sink, $0) }
        try await p.moveToTrash(rel("main.typ"))
        #expect(p.main == rel("main.typ") && !exists(root, "main.typ"))      // kept: there is no other document
        let r = try #require(await p.settle())
        #expect(r.snapshot.pageCount == 0 && !r.snapshot.diagnostics.isEmpty)
    }

    @Test func trashFolderContainingMainFallsBackToRootTypst() async throws {
        let (p, _) = try await TestEnv.project(files: ["src/main.typ": "= In\n", "root.typ": "Root\n"], main: "src/main.typ")
        let sink = try sink()
        p.trash = { try moveInto(sink, $0) }
        try await p.moveToTrash(rel("src"))
        #expect(p.main == rel("root.typ") && p.selectedFile == rel("root.typ"))
        try await clean(p)
    }

    @Test func failedTrashKeepsEverythingOpen() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "a\n"])
        p.trash = { _ in throw CocoaError(.fileWriteVolumeReadOnly) }
        let a = try await p.open(rel("a.typ"))
        type(a, "E", at: 0)
        #expect(kind(await failure { try await p.moveToTrash(rel("a.typ")) }) == "operationFailed")
        #expect(p.buffer(for: rel("a.typ")) === a && exists(root, "a.typ"))
        _ = await p.settle()
        #expect(await p.engine.overlayText(rel("a.typ")) == a.storage.string)
    }

    // MARK: Import, refresh

    @Test func importCopiesAndKeepsOriginals() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "x.txt": "mine\n", "docs/readme.md": "r\n"])
        let outside = try sink()
        try "theirs\n".write(to: outside.appending(path: "x.txt"), atomically: true, encoding: .utf8)
        try "new\n".write(to: outside.appending(path: "y.csv"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: outside.appending(path: "folder"), withIntermediateDirectories: true)
        try "in\n".write(to: outside.appending(path: "folder/in.txt"), atomically: true, encoding: .utf8)
        try "h\n".write(to: outside.appending(path: ".hidden"), atomically: true, encoding: .utf8)
        let got = try p.importItems(["x.txt", "y.csv", "folder", ".hidden"].map { outside.appending(path: $0) }, into: nil)
        #expect(got.map(\.raw) == ["x copy.txt", "y.csv", "folder"])
        #expect(try text(root, "x.txt") == "mine\n" && text(root, "x copy.txt") == "theirs\n")
        #expect(try text(root, "folder/in.txt") == "in\n" && !exists(root, ".hidden"))
        for n in ["x.txt", "y.csv", "folder/in.txt", ".hidden"] { #expect(FileManager.default.fileExists(atPath: outside.appending(path: n).path)) }
        let into = try p.importItems([outside.appending(path: "y.csv")], into: rel("docs"))
        #expect(into == [rel("docs/y.csv")])
        #expect(kind(failureNow { try p.importItems([root], into: nil) }) == "invalidMove")
        #expect(p.files.contains { $0.id == rel("x copy.txt") })
    }

    @Test func refreshFilesPicksUpExternalChangesOnce() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n"])
        let before = p.fileRevision
        await p.refreshFiles()
        #expect(p.fileRevision == before)                        // nothing changed: the echo of our own operations is a no-op
        try "x\n".write(to: root.appending(path: "late.txt"), atomically: true, encoding: .utf8)
        await p.refreshFiles()
        #expect(p.files.map(\.id.raw) == ["late.txt", "main.typ"] && p.fileRevision == before + 1)
        try p.createFile(named: "mine.txt")
        let after = p.fileRevision
        await p.refreshFiles()
        #expect(p.fileRevision == after)
    }

    // MARK: Search and diagnostics after a relocate

    @Test func searchAndDiagnosticsNeverPointAtMissingFiles() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#include \"bad.typ\"\nneedle\n", "bad.typ": "= Bad needle\n#undefinedfunc()\n"])
        let bad = try await p.open(rel("bad.typ"))
        type(bad, "needle ", at: 0)
        _ = await p.settle()
        #expect(p.diagnostics.contains { if case .project(let l) = $0.origin { l.file == rel("bad.typ") } else { false } })
        let first = try #require(await p.search("needle", options: SearchOptions()))
        #expect(first.files.map(\.id.raw) == ["bad.typ", "main.typ"])

        try await p.rename(rel("bad.typ"), to: "good.typ")
        // No compile has landed yet: the stale result is hidden, not shown against a missing file.
        func files(_ ds: [Diagnostic]) -> [RelPath] { ds.compactMap { if case .project(let l) = $0.origin { l.file } else { nil } } }
        #expect(!files(p.diagnostics).contains(rel("bad.typ")))
        let after = try #require(await p.search("needle", options: SearchOptions()))
        #expect(after.files.map(\.id.raw) == ["good.typ", "main.typ"])
        #expect(after.files[0].hits.count == 2)                  // the open buffer's text, under its new name
        for f in after.files { #expect(p.allFiles.contains(f.id)) }
        _ = await p.settle()
        #expect(files(p.diagnostics).allSatisfy { p.allFiles.contains($0) })    // the include now fails in main.typ
        #expect(files(p.diagnostics).contains(rel("main.typ")))
    }

    @Test func outlineDropsMovedFilesUntilTheNextCompile() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Top\n#include \"inc.typ\"\n", "inc.typ": "== Inner\n"])
        _ = await p.settle()
        #expect(p.outline.map(\.file.raw) == ["main.typ", "inc.typ"])
        try await p.rename(rel("inc.typ"), to: "inc2.typ")
        #expect(p.outline.map(\.file.raw) == ["main.typ"])
        _ = await p.settle()
        #expect(p.outline.map(\.file.raw) == ["main.typ"])        // the include is broken now; the last good outline stays hidden
    }

    @Test func projectWithATrashedMainStillOpens() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "notes.txt": "n\n"])
        let sink = try sink()
        p.trash = { try moveInto(sink, $0) }
        _ = await p.settle()
        #expect(!p.preview.pages.isEmpty)
        try await p.moveToTrash(rel("main.typ"))
        #expect(p.preview.pages.isEmpty)                          // no document, not the last good one
        // The recents record still names the trashed main; reopening must not fail on it.
        let again = try await Project(id: ProjectID(), root: root, main: rel("main.typ"), runtime: await TestEnv.runtime.value)
        #expect(again.selectedFile == nil && again.files.map(\.id.raw) == ["notes.txt"])
    }

    @Test func dropsMoveProjectRowsAndCopyFinderItems() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "a\n", "dir/x.txt": "x\n", "dir/sub/y.txt": "y\n"])
        let b = try await p.open(rel("a.typ"))
        let outside = try sink()
        try "o\n".write(to: outside.appending(path: "o.txt"), atomically: true, encoding: .utf8)
        let got = try await p.dropItems([p.url(for: rel("a.typ")), outside.appending(path: "o.txt")], into: rel("dir"))
        #expect(got == [rel("dir/a.typ"), rel("dir/o.txt")])
        #expect(p.buffer(for: rel("dir/a.typ")) === b && !exists(root, "a.typ"))
        #expect(exists(root, "dir/o.txt") && FileManager.default.fileExists(atPath: outside.appending(path: "o.txt").path))
        #expect(kind(await failure { try await p.dropItems([p.url(for: rel("dir"))], into: rel("dir/sub")) }) == "invalidMove")
        #expect(exists(root, "dir/sub/y.txt"))
    }
}
