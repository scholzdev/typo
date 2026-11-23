import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct DeferredCompileTests {
    private static let main = RelPath("main.typ")!

    @Test func editsDoNotCompileOnSaveModeUntilRecompile() async throws {
        let (_, root) = try await TestEnv.project(files: ["main.typ": "hello"])
        let e = try Engine(runtime: await TestEnv.runtime.value, root: root, main: Self.main)
        e.setDefersEdits(true)
        e.send(.setText(Self.main, "hello", Seq(raw: 1)))
        _ = await e.flush()
        let first = await e.compileCount
        e.send(.edit(Edit(seq: Seq(raw: 2), file: Self.main, range: NSRange(location: 5, length: 0), replacement: "!", newLength: 6)))
        e.send(.edit(Edit(seq: Seq(raw: 3), file: Self.main, range: NSRange(location: 6, length: 0), replacement: "!", newLength: 7)))
        // A request answered in the same drain proves the edits were applied.
        _ = await withCheckedContinuation { c in
            e.send(.cursor(CursorRequest(file: Self.main, cursor: 0, reply: { c.resume(returning: $0 == nil) })))
        }
        #expect(await e.overlayText(Self.main) == "hello!!")       // applied to the world, not compiled
        #expect(await e.compileCount == first)
        e.send(.recompile)                                          // a save
        #expect(await e.flush()?.seq == Seq(raw: 3))
        #expect(await e.compileCount == first + 1)
    }
}
