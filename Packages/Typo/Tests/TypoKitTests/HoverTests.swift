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

private final class Replies: Sendable {
    private let log = Mutex<[(id: Int, answer: HoverAnswer?)]>([])
    func reply(_ id: Int) -> @Sendable (HoverAnswer?) -> Void { { a in self.log.withLock { $0.append((id, a)) } } }
    /// Waits for `n` replies, then a grace period in which a double resume would show up as an extra.
    func settle(_ n: Int) async throws -> [(id: Int, answer: HoverAnswer?)] {
        for _ in 0..<400 where log.withLock({ $0.count }) < n { try await Task.sleep(for: .milliseconds(25)) }
        try await Task.sleep(for: .milliseconds(200))
        return log.withLock { $0 }
    }
}

@Suite(.serialized) @MainActor struct HoverTests {
    static let main = RelPath("main.typ")!

    static func project(_ text: String) async throws -> (Project, Buffer) {
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(main)
        _ = await p.settle()
        return (p, b)
    }

    static func plain(_ t: Tooltip?) -> String {
        switch t {
        case .text(let a)?, .code(let a)?: String(a.characters)
        case nil: ""
        }
    }

    @Test func functionDocs() async throws {
        let (p, _) = try await Self.project("#text(fill: red)[Hi]")
        let info = try #require(await p.hover(in: Self.main, at: 2))
        guard case .text? = info.tooltip else { Issue.record("not text: \(String(describing: info.tooltip))"); return }
        #expect(!Self.plain(info.tooltip).isEmpty)
        #expect(info.range == NSRange(location: 1, length: 4))
        #expect(info.diagnostics.isEmpty)
    }

    @Test func parameterDocs() async throws {
        let (p, _) = try await Self.project("#text(fill: red)[Hi]")
        let info = try #require(await p.hover(in: Self.main, at: 7))
        guard case .text? = info.tooltip else { Issue.record("not text: \(String(describing: info.tooltip))"); return }
        #expect(!Self.plain(info.tooltip).isEmpty)
        #expect(info.range == NSRange(location: 6, length: 4))
    }

    @Test func valueIsCode() async throws {
        let (p, b) = try await Self.project("#let x = 1 + 2\n#x")
        let at = (b.storage.string as NSString).length - 1
        let info = try #require(await p.hover(in: Self.main, at: at))
        guard case .code? = info.tooltip else { Issue.record("not code: \(String(describing: info.tooltip))"); return }
        #expect(Self.plain(info.tooltip).contains("3"))
    }

    @Test func triviaGivesNothing() async throws {
        let (p, _) = try await Self.project("#text(fill: red)[Hi]   \n\nplain")
        #expect(await p.hover(in: Self.main, at: 21) == nil)
    }

    @Test func labelTooltipNeedsACompiledDocument() async throws {
        let text = "#set heading(numbering: \"1.\")\n= Intro <intro>\nSee @intro."
        let (_, root) = try await TestEnv.project(files: ["main.typ": text])
        let e = try Engine(runtime: await TestEnv.runtime.value, root: root, main: Self.main)
        let at = (text as NSString).range(of: "@intro").location + 2
        let before = Replies()
        e.send([.setText(Self.main, text, Seq(raw: 1)), .hover(HoverRequest(file: Self.main, cursor: at, reply: before.reply(1)))])
        let b = try await before.settle(1)
        #expect(b.count == 1 && b[0].answer != nil && b[0].answer?.tip == nil, "label tooltip before any compile")   // answered before the batch's compile
        _ = await e.flush()
        let after = Replies()
        e.send(.hover(HoverRequest(file: Self.main, cursor: at, reply: after.reply(1))))
        let a = try await after.settle(1)
        let tip = try #require(a.first?.answer?.tip)
        #expect(!tip.isCode && !tip.text.isEmpty)
    }

    @Test func errorRangeShowsTheDiagnosticFirst() async throws {
        let (p, b) = try await Self.project("#text(fill: red)[Hi]\n\n#undefinedfunc()")
        #expect(p.diagnostics.contains { $0.severity == .error })
        let at = (b.storage.string as NSString).range(of: "undefinedfunc").location + 4
        let info = try #require(await p.hover(in: Self.main, at: at))      // a HoverInfo even without a tooltip
        let d = try #require(info.diagnostics.first)
        #expect(d.severity == .error && !d.message.isEmpty)
        if case .project(let l) = d.origin { #expect((b.storage.string as NSString).substring(with: l.range) == "undefinedfunc") }
        // A tooltip comes after the diagnostics, and away from the error the diagnostic is gone.
        let other = try #require(await p.hover(in: Self.main, at: 2))
        #expect(other.diagnostics.isEmpty && other.tooltip != nil)
    }

    /// Holds the engine queue, sends a hover, makes the edit, then lets the engine answer: the reply is
    /// older than the edit and must be mapped through the log.
    static func staleHover(_ p: Project, at: Int, edit: () -> Void) async throws -> HoverInfo? {
        let gate = DispatchSemaphore(value: 0)
        Task { await p.engine.stall(gate) }
        try await Task.sleep(for: .milliseconds(100))
        let t = Task { await p.hover(in: main, at: at) }
        try await Task.sleep(for: .milliseconds(100))
        edit()
        gate.signal()
        return await t.value
    }

    @Test func staleReplyAfterAnEditBeforeTheRangeIsShifted() async throws {
        let (p, b) = try await Self.project("#text(fill: red)[Hi]")
        let info = try await Self.staleHover(p, at: 2) { replace(b, NSRange(location: 0, length: 0), with: "AB") }
        #expect(try #require(info).range == NSRange(location: 3, length: 4))
    }

    @Test func staleReplyAfterAnEditInsideTheRangeIsNil() async throws {
        let (p, b) = try await Self.project("#text(fill: red)[Hi]")
        let info = try await Self.staleHover(p, at: 2) { replace(b, NSRange(location: 3, length: 0), with: "x") }
        #expect(info == nil)
    }

    @Test func everyHoverRequestResumesExactlyOnce() async throws {
        let text = "#text(fill: red)[Hi]"
        let (_, root) = try await TestEnv.project(files: ["main.typ": text])
        func engine() async throws -> Engine { try Engine(runtime: await TestEnv.runtime.value, root: root, main: Self.main) }
        func h(_ id: Int, _ r: Replies) -> EngineMessage { .hover(HoverRequest(file: Self.main, cursor: 2, reply: r.reply(id))) }
        let e = try await engine()
        e.send(.setText(Self.main, text, Seq(raw: 1)))
        _ = await e.flush()

        let sup = Replies()
        e.send([h(1, sup), h(2, sup)])
        let s = try await sup.settle(2)
        #expect(s.count == 2 && s.first { $0.id == 1 }?.answer == nil && s.first { $0.id == 2 }?.answer?.tip != nil)

        let bad = Replies()
        e.send([.edit(Edit(seq: Seq(raw: 2), file: Self.main, range: NSRange(location: 0, length: 0), replacement: "X", newLength: 99)), h(1, bad)])
        let d = try await bad.settle(1)
        #expect(d.count == 1 && d[0].answer == nil)

        let closed = try await engine()
        let gate = DispatchSemaphore(value: 0)
        Task { await closed.stall(gate) }
        try await Task.sleep(for: .milliseconds(100))
        let q = Replies()
        closed.send([.setText(Self.main, text, Seq(raw: 1)), h(1, q)])
        closed.close()
        gate.signal()
        let c1 = try await q.settle(1)
        #expect(c1.count == 1 && c1[0].answer == nil)
        closed.send(h(2, q))
        let c2 = try await q.settle(2)
        #expect(c2.count == 2 && c2.allSatisfy { $0.answer == nil })
    }

    @Test func markdownDropsInternalLinksAndKeepsWebLinks() {
        let a = HoverText.markdown("[text]($text) and [site](https://typst.app)")
        #expect(String(a.characters) == "text and site")
        let links = a.runs.compactMap { r in r.link.map { (String(a[r.range].characters), $0.absoluteString) } }
        #expect(links.count == 1 && links[0].0 == "site" && links[0].1 == "https://typst.app")
        #expect(String(HoverText.markdown("one\n\ntwo").characters).contains("\n"))
    }

    @Test func codeIsMonospacedAndHighlighted() {
        let code = "(a: 1, b: \"x\")"
        let a = HoverText.code(code)
        #expect(String(a.characters) == code)
        let ns = NSAttributedString(a)
        var colors = Set<PlatformColor>()
        ns.enumerateAttributes(in: NSRange(location: 0, length: ns.length)) { attrs, _, _ in
            let font = attrs[.font] as? PlatformFont
            #if canImport(AppKit)
            #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
            #else
            #expect(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
            #endif
            if let c = attrs[.foregroundColor] as? PlatformColor { colors.insert(c) }
        }
        #expect(colors.count > 1)
    }

    @Test func timing() async throws {
        let (p, _) = try await TestEnv.project("sample")
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        let text = b.storage.string as NSString
        let at = text.range(of: "#showybox").location + 3     // a package function late in the document: evaluation covers most of it
        var times: [Double] = []
        for _ in 0..<15 {
            let t = ContinuousClock.now
            #expect(await p.hover(in: b.path, at: at) != nil)
            times.append(JumpTests.ms(ContinuousClock.now - t))
        }
        #if DEBUG
        let profile = "debug"
        #else
        let profile = "release"
        #endif
        print("HOVER TIMING [\(profile)] \(p.preview.pages.count) pages: hover median \(String(format: "%.2f", times.sorted()[times.count / 2])) ms")
    }
}
