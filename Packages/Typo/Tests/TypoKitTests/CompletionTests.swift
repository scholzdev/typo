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

private final class ReplyLog: Sendable {
    private let log = Mutex<[(id: Int, answer: CompletionAnswer?)]>([])
    func request(_ id: Int, _ file: String, _ cursor: Int) -> EngineMessage {
        .complete(CompletionRequest(file: RelPath(file)!, cursor: cursor, explicit: false, reply: { a in self.log.withLock { $0.append((id, a)) } }))
    }
    /// Waits for `n` replies, then a grace period in which a double resume would show up as an extra.
    func settle(_ n: Int) async throws -> [(id: Int, answer: CompletionAnswer?)] {
        for _ in 0..<400 where log.withLock({ $0.count }) < n { try await Task.sleep(for: .milliseconds(25)) }
        try await Task.sleep(for: .milliseconds(200))
        return log.withLock { $0 }
    }
}

@Suite(.serialized) @MainActor struct CompletionTests {
    static func engine(_ files: [String: String]) async throws -> Engine {
        let (p, root) = try await TestEnv.project(files: files)
        _ = p
        return try Engine(runtime: await TestEnv.runtime.value, root: root, main: RelPath("main.typ")!)
    }

    static func labels(_ l: CompletionList?) -> [String] { l?.items.map(\.label) ?? [] }

    // 1
    @Test func implicitCodeCompletionListsText() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#te"])
        let b = try await p.open(RelPath("main.typ")!)
        let list = try #require(await p.complete(in: b.path, at: 3, explicit: false))
        #expect(list.from == 1)
        #expect(list.items.first { $0.label == "text" }?.kind == .function)
    }

    // 2
    @Test func mathSymbolCarriesGlyph() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "$al$"])
        let b = try await p.open(RelPath("main.typ")!)
        let list = try #require(await p.complete(in: b.path, at: 3, explicit: false))
        #expect(list.items.first { $0.label == "alpha" }?.kind == .symbol("α"))
    }

    // 3
    @Test func includePathListsProjectFile() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#include \"\"", "kapitel.typ": "= K\n", ".hidden.typ": ""])
        let b = try await p.open(RelPath("main.typ")!)
        let list = try #require(await p.complete(in: b.path, at: 10, explicit: false))
        #expect(list.from == 9)                                  // the opening quote
        #expect(list.items.contains { $0.label.contains("kapitel.typ") && $0.kind == .path })
        #expect(!list.items.contains { $0.label.contains(".hidden") })
    }

    // 4
    @Test func labelsNeedACompiledDocument() async throws {
        let text = "= Intro <intro>\n\n@"
        let e = try await Self.engine(["main.typ": text])
        let log = ReplyLog()
        let at = text.utf16.count
        e.send([.setText(RelPath("main.typ")!, text, Seq(raw: 1)), log.request(0, "main.typ", at)])
        let before = try await log.settle(1)
        #expect(try #require(before.first?.answer).items.allSatisfy { $0.label != "intro" })
        _ = await e.flush()
        let after = ReplyLog()
        e.send(after.request(0, "main.typ", at))
        let r = try #require(try await after.settle(1).first?.answer)
        #expect(r.items.contains { $0.label == "intro" && $0.kind == .label })
    }

    // 5: engine-side order. The reply runs on the engine queue, and the compile's first event is yielded
    // later on that same queue, so a consumer that has seen the event must already find the reply recorded.
    // (Delivery order on the main actor says nothing about this, which made the old version flaky.)
    @Test func replyArrivesBeforeTheCompileOfItsBatch() async throws {
        let text = "#rec"
        let e = try await Self.engine(["main.typ": text])
        let replied = Mutex<CompletionAnswer?>(nil)
        let request = EngineMessage.complete(CompletionRequest(file: RelPath("main.typ")!, cursor: text.utf16.count, explicit: false,
                                                                reply: { a in replied.withLock { $0 = a } }))
        e.send([.setText(RelPath("main.typ")!, text, Seq(raw: 1)), request])
        for await event in e.events {
            guard case .status(.compiling) = event else { continue }
            let answer = try #require(replied.withLock { $0 })
            #expect(answer.items.contains { $0.label == "rect" })
            #expect(answer.seq == Seq(raw: 1))
            return
        }
        Issue.record("the batch never compiled")
    }

    // 6
    @Test func everyRequestResumesExactlyOnce() async throws {
        let text = "#te"
        let main = RelPath("main.typ")!
        let e = try await Self.engine(["main.typ": text])
        e.send(.setText(main, text, Seq(raw: 1)))

        let sup = ReplyLog()                                     // superseded: two requests for one file, one batch
        e.send([sup.request(1, "main.typ", 3), sup.request(2, "main.typ", 3)])
        let s = try await sup.settle(2)
        #expect(s.count == 2)
        #expect(s.first { $0.id == 1 }?.answer == nil)
        #expect(s.first { $0.id == 2 }?.answer != nil)

        let bad = ReplyLog()                                     // diverged: the edit's newLength is wrong
        e.send([.edit(Edit(seq: Seq(raw: 2), file: main, range: NSRange(location: 0, length: 0), replacement: "X", newLength: 99)),
                bad.request(1, "main.typ", 3)])
        let d = try await bad.settle(1)
        #expect(d.count == 1 && d[0].answer == nil)

        let none = ReplyLog()                                    // no overlay
        e.send(none.request(1, "missing.typ", 0))
        let n = try await none.settle(1)
        #expect(n.count == 1 && n[0].answer == nil)

        let closed = try await Self.engine(["main.typ": text])   // closed with a request queued
        let gate = DispatchSemaphore(value: 0)
        Task { await closed.stall(gate) }
        try await Task.sleep(for: .milliseconds(100))
        let q = ReplyLog()
        closed.send([.setText(main, text, Seq(raw: 1)), q.request(1, "main.typ", 3)])
        closed.close()
        gate.signal()
        let c = try await q.settle(1)
        #expect(c.count == 1 && c[0].answer == nil)
        closed.send(q.request(2, "main.typ", 3))                 // after close: refused at once
        #expect(try await q.settle(2).count == 2)
    }

    // 7
    @Test func liveSurvivesALogTrimByACompile() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n"])
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        type(b, "#re")
        let list = try #require(await p.complete(in: b.path, at: b.storage.length, explicit: false))
        type(b, "ct")
        _ = await p.settle()                                     // a result newer than the list lands and trims
        let live = try #require(p.live(list, caret: b.storage.length))
        #expect(live.range == NSRange(location: 6, length: 4))
        #expect(live.items.first?.label == "rect")
        #expect(live.items.allSatisfy { $0.label.contains("r") })
    }

    // 8
    @Test func liveDismissesOnEditsBeforeFromAndOrdersPrefixFirst() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "ab #"])
        let b = try await p.open(RelPath("main.typ")!)
        let list = try #require(await p.complete(in: b.path, at: 4, explicit: true))
        type(b, "re")
        let live = try #require(p.live(list, caret: 6))
        let labels = live.items.map(\.label)
        let isPrefix = { (l: String) in l.lowercased().hasPrefix("re") }
        let lastPrefix = try #require(labels.lastIndex(where: isPrefix))
        let firstOther = try #require(labels.firstIndex { !isPrefix($0) })
        #expect(lastPrefix < firstOther)
        #expect(labels.filter(isPrefix) == list.items.map(\.label).filter(isPrefix))

        replace(b, NSRange(location: 0, length: 0), with: "ä")    // before `from`: shifts, still valid
        #expect(p.live(list, caret: 7)?.range == NSRange(location: 5, length: 2))
        replace(b, NSRange(location: 4, length: 1), with: "")     // deletes the `#`: touches the text before `from`
        #expect(p.live(list, caret: 6) == nil)
        p.endCompletion()
        #expect(p.live(list, caret: 6) == nil)
    }

    // 9
    @Test func snippetParse() {
        let a = Snippet.parse("rect(${})")
        #expect(a.text == "rect()" && a.placeholders == [NSRange(location: 5, length: 0)])
        let b = Snippet.parse("let ${name} = ${value}")
        #expect(b.text == "let name = value" && b.placeholders == [NSRange(location: 4, length: 4), NSRange(location: 11, length: 5)])
        let c = Snippet.parse("$${x}$")
        #expect(c.text == "$x$" && c.placeholders == [NSRange(location: 1, length: 1)])
        let d = Snippet.parse("${2:2}")
        #expect(d.text == "2" && d.placeholders == [NSRange(location: 0, length: 1)])
        let e = Snippet.parse("plain {braces} $")
        #expect(e.text == "plain {braces} $" && e.placeholders.isEmpty)
        #expect(e.selection(insertedAt: 3) == NSRange(location: 3 + 16, length: 0))
        #expect(CompletionItem(kind: .function, label: "f", apply: nil,
                               detail: "Creates a [rectangle]($rect) with `x` and *bold*. More text.\n\nSecond.").summary == "Creates a rectangle with x and bold.")
    }

    // 10
    @Test func acceptEndToEnd() async throws {
        // Replaces [range] with snippet.text through the storage, as the app does, then selects.
        func accept(_ p: Project, _ b: Buffer, _ list: CompletionList, label: String) throws -> NSRange {
            let live = try #require(p.live(list, caret: b.storage.length))
            let item = try #require(live.items.first { $0.label == label })
            let snip = Snippet.parse(item.apply ?? item.label)
            replace(b, live.range, with: snip.text)
            return snip.selection(insertedAt: live.range.location)
        }

        let (p, _) = try await TestEnv.project(files: ["main.typ": "", "kapitel.typ": "= K\n"])
        let b = try await p.open(RelPath("main.typ")!)
        type(b, "#rec")
        var list = try #require(await p.complete(in: b.path, at: b.storage.length, explicit: false))
        let sel = try accept(p, b, list, label: "rect")
        #expect(b.storage.string == "#rect()")
        #expect(sel == NSRange(location: 6, length: 0))

        // typst-ide offers paths only inside a terminated string, so the closing quote is always already there.
        replace(b, NSRange(location: 0, length: b.storage.length), with: "#include \"ka\"")
        list = try #require(await p.complete(in: b.path, at: 12, explicit: false))
        let live = try #require(p.live(list, caret: 12))
        let item = try #require(live.items.first { $0.label.contains("kapitel.typ") })
        replace(b, live.range, with: Snippet.parse(item.apply ?? item.label).text)
        #expect(b.storage.string == "#include \"kapitel.typ\"")

        replace(b, NSRange(location: 0, length: b.storage.length), with: "$al$")
        list = try #require(await p.complete(in: b.path, at: 3, explicit: false))
        let m = try #require(p.live(list, caret: 3))
        let alpha = try #require(m.items.first { $0.label == "alpha" })
        replace(b, m.range, with: Snippet.parse(alpha.apply ?? alpha.label).text)
        #expect(b.storage.string == "$alpha$")
        _ = await p.settle()
        #expect(await p.engine.overlayText(b.path) == b.storage.string)
    }

    // 11
    @Test func timing() async throws {
        let (p, _) = try await TestEnv.project("sample")
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        func median(_ label: String, _ tail: String) async throws -> String {
            let at = (b.storage.string as NSString).length
            type(b, tail)
            _ = await p.settle()                                 // no compile in flight while measuring
            var ms: [Double] = []
            var n = 0
            for _ in 0..<15 {
                let t = ContinuousClock.now
                let l = await p.complete(in: b.path, at: b.storage.length, explicit: false)
                let d = (ContinuousClock.now - t).components
                ms.append(Double(d.seconds) * 1e3 + Double(d.attoseconds) / 1e15)
                n = l?.items.count ?? 0
            }
            replace(b, NSRange(location: at, length: b.storage.length - at), with: "")
            _ = await p.settle()
            return "\(label): median \(String(format: "%.1f", ms.sorted()[ms.count / 2])) ms (\(n) items)"
        }
        let rows = try await [median("#te", "\n#te"), median("#calc.", "\n#calc."),
                              median("#d.", "\n#let d = (a: 1)\n#d.")]
        #if DEBUG
        let profile = "debug"
        #else
        let profile = "release"
        #endif
        print("COMPLETION TIMING [\(profile)] " + rows.joined(separator: "; "))
    }
}
