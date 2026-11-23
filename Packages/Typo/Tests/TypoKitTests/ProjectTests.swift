import Foundation
import PDFKit
import Synchronization
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct ProjectTests {
    // 1
    @Test func mirrorReadBackAfterLongEditSequence() async throws {
        let (p, _) = try await TestEnv.project("proj-a")
        let b = try await p.open(RelPath("main.typ")!)
        let um = b.undoManager
        um.groupsByEvent = false

        type(b, "Hello ä € 😀 world")
        let ns = b.storage.string as NSString
        replace(b, ns.range(of: "😀 w"), with: "")              // deletion across an emoji
        um.beginUndoGrouping()
        b.storage.beginEditing()                                 // grouped change, two replacements
        replace(b, NSRange(location: 0, length: 0), with: "AA")
        replace(b, NSRange(location: b.storage.length, length: 0), with: "é€😀")
        b.storage.endEditing()
        um.endUndoGrouping()
        type(b, "!!", at: 3)
        replace(b, NSRange(location: 1, length: 3), with: "😀😀")
        um.undo(); um.undo(); um.redo()
        replace(b, NSRange(location: 0, length: b.storage.length), with: b.storage.string + "\n= Tail ä\n")

        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
        #expect(p.resyncCount == 0)
    }

    // 2
    @Test func unsavedNonMainFileReachesCompile() async throws {
        let (p, root) = try await TestEnv.project("twofile")
        let original = try String(contentsOf: root.appending(path: "chapter.typ"), encoding: .utf8)
        let ch = try await p.open(RelPath("chapter.typ")!)
        type(ch, "ZEBRAMARKERWORD ", at: 0)
        let pdf = try await p.exportPDF()
        #expect(TestEnv.pdfText(pdf).contains("ZEBRAMARKERWORD"))
        #expect(ch.isDirty)
        #expect(try String(contentsOf: root.appending(path: "chapter.typ"), encoding: .utf8) == original)
    }

    // 3
    @Test func divergenceResyncs() async throws {
        let (p, _) = try await TestEnv.project("proj-a")
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        var diverged = false
        p.eventTap = { if case .diverged = $0 { diverged = true } }
        p.engine.send(.edit(Edit(seq: p.takeSeq(), file: b.path, range: NSRange(location: 0, length: 0),
                                 replacement: "X", newLength: b.storage.length + 7)))
        for _ in 0..<200 where !diverged || p.resyncCount == 0 { try await Task.sleep(for: .milliseconds(25)) }
        #expect(diverged)
        #expect(p.resyncCount >= 1)
        let r = try #require(await p.settle())
        #expect(r.snapshot.diagnostics.isEmpty)
        #expect(r.snapshot.pageCount == 1)
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
    }

    // 4
    @Test func diagnosticsFollowEditsAndVanishWhenTouched() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#undefinedfunc()\n= Hello\n"])
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        func errorRange() -> NSRange? {
            for d in p.diagnostics where d.severity == .error {
                if case .project(let l) = d.origin { return l.range }
            }
            return nil
        }
        func text(_ r: NSRange) -> String { (b.storage.string as NSString).substring(with: r) }
        #expect(try text(#require(errorRange())) == "undefinedfunc")

        // No await below: no engine result can land, so this reads the stale result through the log.
        type(b, "ä😀 ", at: 0)
        #expect(try text(#require(errorRange())) == "undefinedfunc")

        let r = try #require(errorRange())
        replace(b, NSRange(location: r.location + 2, length: 1), with: "Z")
        #expect(errorRange() == nil)
    }

    // 5
    @Test func rapidEditsCoalesce() async throws {
        let (p, _) = try await TestEnv.project("proj-a")
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        let before = await p.engine.compileCount
        type(b, String(repeating: "x", count: 50))
        _ = await p.settle()
        let compiles = await p.engine.compileCount - before
        print("coalescing: \(compiles) compiles for 50 edits")
        #expect(compiles >= 1 && compiles < 50)
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
    }

    // 6
    @Test func twoProjectsCompileConcurrently() async throws {
        let rt = await TestEnv.runtime.value
        let main = RelPath("main.typ")!
        func engine(_ fixture: String) throws -> Engine {
            let root = try TestEnv.copyFixture(fixture)
            let e = try Engine(runtime: rt, root: root, main: main)
            e.send(.setText(main, try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8), Seq(raw: 1)))
            return e
        }
        let a = try engine("proj-a"), b = try engine("proj-b")
        async let ra = a.flush()
        async let rb = b.flush()
        let (x, y) = await (ra, rb)
        #expect(x?.snapshot.pageCount == 1 && x?.snapshot.diagnostics.isEmpty == true)
        #expect(y?.snapshot.pageCount == 3 && y?.snapshot.diagnostics.isEmpty == true)
    }

    // 7
    @Test func renderAndExportLongSample() async throws {
        let (p, _) = try await TestEnv.project("sample")   // imports @preview/showybox: downloads into the temp package dir
        let pdf = try await p.exportPDF()
        #expect(PDFDocument(data: pdf)?.pageCount == 38)
        #expect(p.preview.pages.count == 38)

        let page = p.preview.pages[0]
        #expect(abs(page.size.width - 595.28) < 0.5 && abs(page.size.height - 841.89) < 0.5)
        let key = ImageKey(page.hash, pixelsPerPoint: 2)
        await p.preview.render(page, key)
        let img = try #require(p.preview.image(for: key))
        #expect(abs(Double(img.width) - 2 * 595.28) <= 2 && abs(Double(img.height) - 2 * 841.89) <= 2)
        let direct = try #require(await page.snapshot.render(page: 0, pixelsPerPoint: 2))
        #expect(direct.width == img.width)
    }

    @Test func renderSlotsCapAtLimit() async {
        let slots = RenderSlots(limit: 2)
        await slots.acquire(); await slots.acquire()
        let got = Mutex(false)
        let third = Task { await slots.acquire(); got.withLock { $0 = true } }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(got.withLock { $0 } == false)     // two slots held: the third waits
        await slots.release()
        await third.value
        #expect(got.withLock { $0 })
    }

    @Test func fontIndexSkipsUnreadablePaths() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "typstcore-idx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let notAFont = dir.appending(path: "x.ttf")
        try "nope".write(to: notAFont, atomically: true, encoding: .utf8)
        let index = dir.appending(path: "idx.json")
        _ = Bridge.makeRuntime(fontPaths: ["/nonexistent/none.ttf", notAFont.path], indexPath: index.path, packageDir: dir.appending(path: "p").path)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: index)) as? [[String: Any]]
        #expect(json != nil)
        #expect(json?.count == 1)          // the unreadable path is skipped, the readable file is indexed with zero faces
    }
}

@MainActor @Suite struct PreviewFlickerTests {
    /// An edit changes page 0's hash; until its new image lands the old one must stay visible.
    @Test func changedPageKeepsPreviousImageUntilReplaced() async throws {
        let (p, _) = try await TestEnv.project("proj-a")
        _ = await p.settle()
        let a = try #require(p.preview.pages.first)
        let keyA = ImageKey(a.hash, pixelsPerPoint: 2)
        await p.preview.render(a, keyA)
        let imgA = try #require(p.preview.image(for: keyA))
        type(try #require(p.selectedBuffer), " changed")
        _ = await p.settle()
        let b = try #require(p.preview.pages.first)
        #expect(b.hash != a.hash)
        let keyB = ImageKey(b.hash, pixelsPerPoint: 2)
        #expect(p.preview.image(for: keyB, index: 0) === imgA)       // fallback, no white flash
        await p.preview.render(b, keyB)
        let imgB = try #require(p.preview.image(for: keyB, index: 0))
        #expect(imgB !== imgA)
        #expect(p.preview.image(for: keyA) == nil)                   // old image dropped once replaced
    }
}

@MainActor @Suite struct PreviewRenderSharingTests {
    private func setup() async throws -> (PreviewModel, PageInfo, ImageKey) {
        let (p, _) = try await TestEnv.project("proj-a")
        _ = await p.settle()
        let a = try #require(p.preview.pages.first)
        return (p.preview, a, ImageKey(a.hash, pixelsPerPoint: 2))
    }

    private func settleQueue() async { for _ in 0..<10 { await Task.yield() } }

    @Test func restartedRenderAfterCancelledOneStillGetsImage() async throws {
        let (m, page, key) = try await setup()
        await m.renderSlots.acquire(); await m.renderSlots.acquire()      // both slots busy: renders queue
        let first = Task { await m.render(page, key) }
        await settleQueue()
        first.cancel()
        let second = Task { await m.render(page, key) }
        await settleQueue()
        await m.renderSlots.release(); await m.renderSlots.release()
        await second.value
        await first.value
        #expect(m.image(for: key) != nil)
    }

    @Test func allWaitersCancelledSkipsRenderAndLeaksNoSlot() async throws {
        let (m, page, key) = try await setup()
        await m.renderSlots.acquire(); await m.renderSlots.acquire()
        let a = Task { await m.render(page, key) }
        let b = Task { await m.render(page, key) }
        await settleQueue()
        a.cancel(); b.cancel()
        await settleQueue()
        await m.renderSlots.release(); await m.renderSlots.release()
        await a.value; await b.value
        await settleQueue()
        #expect(m.renderCount == 0)
        #expect(m.image(for: key) == nil)
        #expect(m.inFlight.isEmpty)
        await m.render(page, key)                                          // slots still free
        #expect(m.renderCount == 1)
        #expect(m.image(for: key) != nil)
    }
}
