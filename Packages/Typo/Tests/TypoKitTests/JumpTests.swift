import Foundation
import Synchronization
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

private final class Replies<A: Sendable>: Sendable {
    private let log = Mutex<[(id: Int, answer: A?)]>([])
    func reply(_ id: Int) -> @Sendable (A?) -> Void { { a in self.log.withLock { $0.append((id, a)) } } }
    /// Waits for `n` replies, then a grace period in which a double resume would show up as an extra.
    func settle(_ n: Int) async throws -> [(id: Int, answer: A?)] {
        for _ in 0..<400 where log.withLock({ $0.count }) < n { try await Task.sleep(for: .milliseconds(25)) }
        try await Task.sleep(for: .milliseconds(200))
        return log.withLock { $0 }
    }
}

private let mainText = "= Main heading\nFirst paragraph with several ordinary words inside.\n\nalpha *beta* gamma\n\n#pagebreak()\n#include \"kapitel.typ\"\n"
private let kapitelText = "= Kapitel Eins\nSecond file has other distinctive prose here.\n"

@Suite(.serialized) @MainActor struct JumpTests {
    static func ms(_ d: Duration) -> Double { Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15 }

    /// Reports a caret and waits for the preview to be aimed at it.
    static func aimed(_ p: Project, _ file: RelPath, _ cursor: Int) async throws -> PreviewPosition {
        let before = p.preview.targetSerial
        p.cursorMoved(in: file, to: cursor)
        for _ in 0..<400 where p.preview.targetSerial == before { try await Task.sleep(for: .milliseconds(10)) }
        return try #require(p.preview.targetSerial != before ? p.preview.target : nil)
    }

    static func word(in text: String, at offset: Int) -> NSRange {
        let ns = text as NSString
        let isW: (Int) -> Bool = { $0 >= 0 && $0 < ns.length && CharacterSet.alphanumerics.contains(UnicodeScalar(ns.character(at: $0))!) }
        var a = offset, b = offset
        while isW(a - 1) { a -= 1 }
        while isW(b) { b += 1 }
        return NSRange(location: a, length: b - a)
    }

    static func two() async throws -> (Project, Buffer, Buffer) {
        let (p, _) = try await TestEnv.project(files: ["main.typ": mainText, "kapitel.typ": kapitelText])
        p.preview.followsCursor = true
        let m = try await p.open(RelPath("main.typ")!)
        let k = try await p.open(RelPath("kapitel.typ")!)
        _ = await p.settle()
        return (p, m, k)
    }

    /// typst-ide jumps at the granularity of a Text leaf, and a leaf runs from one markup break to the next
    /// ("First paragraph with ..." is one leaf), so the leaf is the unit that must round-trip.
    static func leaf(in text: String, at offset: Int) -> NSRange {
        let ns = text as NSString
        let isBreak: (Int) -> Bool = { ["\n", "*", "_", "#", "[", "]", "=", "$"].contains(ns.substring(with: NSRange(location: $0, length: 1))) }
        var a = offset, b = offset
        while a > 0, !isBreak(a - 1) { a -= 1 }
        while b < ns.length, !isBreak(b) { b += 1 }
        return NSRange(location: a, length: b - a)
    }

    // 1
    @Test func roundTripLandsInTheSameLeaf() async throws {
        let (p, m, k) = try await Self.two()
        var checked = 0
        for (b, words) in [(m, ["paragraph", "several", "ordinary", "inside", "beta", "alpha", "gamma"]), (k, ["Second", "distinctive", "prose"])] {
            p.selectedFile = b.path
            let text = b.storage.string
            for w in words {
                let at = (text as NSString).range(of: w).location + 2
                let pos = try await Self.aimed(p, b.path, at)
                #expect(await p.click(page: pos.page, at: CGPoint(x: pos.point.x + 1, y: pos.point.y - 1)) == nil)
                let sel = try #require(b.takePendingSelection(), "no caret for \(w)")
                let want = Self.leaf(in: text, at: at), got = sel.location
                #expect(p.selectedFile == b.path)
                #expect(got >= want.location && got <= NSMaxRange(want), "\(w): caret \(got) outside leaf \(want)")
                if w == "beta" { #expect(Self.word(in: text, at: got) == Self.word(in: text, at: at)) }   // a one-word leaf is the word
                #expect(b.takePendingFlash())
                checked += 1
            }
        }
        #expect(checked == 10)
    }

    // 2
    @Test func linkClickReturnsTheURL() async throws {
        let text = "#link(\"https://typst.app\")[Typst]\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        let pos = try await Self.aimed(p, b.path, (text as NSString).range(of: "Typst").location + 1)
        let url = await p.click(page: pos.page, at: CGPoint(x: pos.point.x + 1, y: pos.point.y - 1))
        #expect(url == URL(string: "https://typst.app"))
    }

    // 3
    @Test func outlineEntryClickAimsAtTheHeadingPage() async throws {
        let text = "#outline()\n#pagebreak()\n= Later heading\nBody.\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        _ = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        let before = p.preview.targetSerial
        // The entry sits under the outline title near the top-left margin; scan rows until a click aims.
        var y = 60.0
        while y < 220, p.preview.targetSerial == before {
            _ = await p.click(page: 0, at: CGPoint(x: 80, y: y))
            y += 3
        }
        #expect(p.preview.targetSerial != before, "no click on page 1 hit the outline entry")
        let t = try #require(p.preview.target)
        #expect(t.page == 1)
        #expect(p.preview.targetDecision == syncDecision(.navigation, userScrolled: false))
    }

    // 4
    @Test func staleClickMapsThroughTheEditLog() async throws {
        let (p, m, _) = try await Self.two()
        let text = m.storage.string
        let target = (text as NSString).range(of: "alpha")
        let leaf = Self.leaf(in: text, at: target.location)
        let pos = try await Self.aimed(p, m.path, target.location + 1)
        let shownBefore = p.preview.pages.first?.hash
        let insert = "A brand new first paragraph that shifts everything.\n\n"
        replace(m, NSRange(location: 15, length: 0), with: insert)     // after the heading, before every other paragraph
        #expect(p.preview.pages.first?.hash == shownBefore)             // still the old document
        _ = await p.click(page: pos.page, at: CGPoint(x: pos.point.x + 1, y: pos.point.y - 1))
        let sel = try #require(m.takePendingSelection(), "the old document's span did not resolve in the new text")
        let now = m.storage.string as NSString
        #expect(sel.location == leaf.location + insert.utf16.count)
        #expect(now.substring(with: NSRange(location: sel.location, length: 5)) == "alpha")
    }

    // 4b: an edit inside the target's own leaf replaces that node, so its old span is gone. The click must
    // then miss or land on the leaf start; it must never land somewhere else.
    @Test func staleClickAfterAnEditInsideTheLeaf() async throws {
        let (p, m, _) = try await Self.two()
        let text = m.storage.string as NSString
        let leaf = text.range(of: "First paragraph")
        let pos = try await Self.aimed(p, m.path, leaf.location + 2)
        replace(m, NSRange(location: text.range(of: "several").location, length: 0), with: "really ")
        _ = await p.click(page: pos.page, at: CGPoint(x: pos.point.x + 1, y: pos.point.y - 1))
        if let sel = m.takePendingSelection() { #expect(sel.location == leaf.location) }
    }

    // 5
    @Test func cursorSyncOnAHeadingGivesItsPage() async throws {
        let (p, _, k) = try await Self.two()
        p.selectedFile = k.path
        let pos = try await Self.aimed(p, k.path, 4)
        #expect(pos.page == 1)
        p.selectedFile = RelPath("main.typ")!
        let first = try await Self.aimed(p, RelPath("main.typ")!, 4)
        #expect(first.page == 0)
    }

    // 6
    @Test func triggerPolicy() {
        #expect(syncDecision(.navigation, userScrolled: false) == SyncDecision(request: true, scrollIfOutside: true, marker: true))
        #expect(syncDecision(.navigation, userScrolled: true) == SyncDecision(request: true, scrollIfOutside: true, marker: true))
        #expect(syncDecision(.typing, userScrolled: false) == SyncDecision(request: true, scrollIfOutside: true, marker: false))
        #expect(syncDecision(.typing, userScrolled: true) == SyncDecision(request: true, scrollIfOutside: false, marker: false))
        #expect(syncDecision(.resync, userScrolled: false) == SyncDecision(request: true, scrollIfOutside: true, marker: false))
        #expect(syncDecision(.resync, userScrolled: true) == SyncDecision(request: true, scrollIfOutside: false, marker: false))
        #expect(syncDecision(.programmatic, userScrolled: false).request == false)
        #expect(syncDecision(.programmatic, userScrolled: true).request == false)
    }

    // 6b: the project derives the reason from the buffer, and never asks for programmatic selections.
    @Test func cursorMovedDerivesTheReason() async throws {
        let (p, m, _) = try await Self.two()
        let f = m.path
        _ = try await Self.aimed(p, f, 4)                          // no edit since the last report: navigation
        #expect(p.preview.targetDecision.marker)
        type(m, "x", at: 4)
        let before = p.preview.targetSerial
        p.cursorMoved(in: f, to: 5)                                // an edit since the last report: typing
        for _ in 0..<400 where p.preview.targetSerial == before { try await Task.sleep(for: .milliseconds(10)) }
        #expect(p.preview.targetSerial != before && !p.preview.targetDecision.marker)
        let asked = p.preview.targetSerial
        p.cursorMoved(in: f, to: 6, programmatic: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(p.preview.targetSerial == asked)
        p.preview.followsCursor = false
        p.cursorMoved(in: f, to: 7)
        try await Task.sleep(for: .milliseconds(300))
        #expect(p.preview.targetSerial == asked)
        p.preview.followsCursor = true
    }

    // 7
    @Test func everyJumpRequestResumesExactlyOnce() async throws {
        let main = RelPath("main.typ")!
        let (p, root) = try await TestEnv.project(files: ["main.typ": mainText, "kapitel.typ": kapitelText])
        _ = p
        func engine() async throws -> Engine { try Engine(runtime: await TestEnv.runtime.value, root: root, main: main) }
        let e = try await engine()
        e.send(.setText(main, mainText, Seq(raw: 1)))
        let shown = try #require(await e.flush()?.snapshot)

        let click = Replies<ClickAnswer>(), cur = Replies<CursorAnswer>()
        func c(_ id: Int, _ r: Replies<ClickAnswer>) -> EngineMessage { .click(ClickRequest(shown: shown, page: 0, point: CGPoint(x: 80, y: 80), reply: r.reply(id))) }
        func u(_ id: Int, _ r: Replies<CursorAnswer>, _ file: RelPath = main) -> EngineMessage { .cursor(CursorRequest(file: file, cursor: 3, reply: r.reply(id))) }

        // Superseded, and the two kinds do not supersede each other.
        e.send([c(1, click), c(2, click), u(1, cur), u(2, cur)])
        let s = try await click.settle(2), t = try await cur.settle(2)
        #expect(s.count == 2 && s.first { $0.id == 1 }?.answer == nil && s.first { $0.id == 2 }?.answer != nil)
        #expect(t.count == 2 && t.first { $0.id == 1 }?.answer == nil && t.first { $0.id == 2 }?.answer != nil)
        #expect(t.first { $0.id == 2 }?.answer?.positions.isEmpty == false)

        // Diverged: the edit's newLength is wrong.
        let bad = Replies<CursorAnswer>()
        e.send([.edit(Edit(seq: Seq(raw: 2), file: main, range: NSRange(location: 0, length: 0), replacement: "X", newLength: 99)), u(1, bad)])
        let d = try await bad.settle(1)
        #expect(d.count == 1 && d[0].answer == nil)

        // No overlay: answered once, with nothing found.
        let none = Replies<CursorAnswer>()
        e.send(u(1, none, RelPath("missing.typ")!))
        let n = try await none.settle(1)
        #expect(n.count == 1 && n[0].answer?.positions.isEmpty == true)

        // Closed with requests queued, and after close.
        let closed = try await engine()
        let gate = DispatchSemaphore(value: 0)
        Task { await closed.stall(gate) }
        try await Task.sleep(for: .milliseconds(100))
        let qc = Replies<ClickAnswer>(), qu = Replies<CursorAnswer>()
        closed.send([.setText(main, mainText, Seq(raw: 1)), c(1, qc), u(1, qu)])
        closed.close()
        gate.signal()
        let c1 = try await qc.settle(1), u1 = try await qu.settle(1)
        #expect(c1.count == 1 && c1[0].answer == nil)
        #expect(u1.count == 1 && u1[0].answer == nil)
        closed.send([c(2, qc), u(2, qu)])
        let c2 = try await qc.settle(2), u2 = try await qu.settle(2)
        #expect(c2.count == 2 && c2.allSatisfy { $0.answer == nil })
        #expect(u2.count == 2 && u2.allSatisfy { $0.answer == nil })
    }

    // 8
    @Test func timing() async throws {
        let (p, _) = try await TestEnv.project("sample")
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        let pages = p.preview.pages.count
        let text = b.storage.string as NSString
        let at = text.range(of: "She writes a paragraph", options: .backwards).location + 4
        let pos = try await Self.aimed(p, b.path, at)
        var clicks: [Double] = [], cursors: [Double] = []
        for _ in 0..<15 {
            let t = ContinuousClock.now
            _ = await p.click(page: pos.page, at: CGPoint(x: pos.point.x + 1, y: pos.point.y - 1))
            clicks.append(Self.ms(ContinuousClock.now - t))
            _ = b.takePendingSelection()
            let t2 = ContinuousClock.now
            let a: CursorAnswer? = await withCheckedContinuation { c in
                p.engine.send(.cursor(CursorRequest(file: b.path, cursor: at, reply: { c.resume(returning: $0) })))
            }
            cursors.append(Self.ms(ContinuousClock.now - t2))
            #expect(a?.positions.first?.page == pos.page)
        }
        func med(_ v: [Double]) -> String { String(format: "%.2f", v.sorted()[v.count / 2]) }
        #if DEBUG
        let profile = "debug"
        #else
        let profile = "release"
        #endif
        print("JUMP TIMING [\(profile)] \(pages) pages (target on page \(pos.page + 1)): click median \(med(clicks)) ms; cursor sync median \(med(cursors)) ms")
    }
}
