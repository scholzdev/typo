import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit

/// The split editor: a file moving between two TextKit 2 views, and the focused pane driving completion.
@Suite(.serialized) @MainActor struct EditorPaneTests {
    private func view() -> NSTextView {
        let tv = NSTextView(usingTextLayoutManager: true)
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        tv.isRichText = false
        return tv
    }

    private func laidOut(_ tv: NSTextView) -> String {
        let tlm = tv.textLayoutManager!
        var s = ""
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { f in
            s += (f.textElement as? NSTextParagraph)?.attributedString.string ?? ""
            return true
        }
        return s
    }

    /// Pane B takes the file pane A shows, then A swaps to another file (the order SwiftUI may update them in).
    @Test func aFileMovesBetweenPanesAndBothKeepLayingOut() {
        let s = NSTextStorage(string: "one\ntwo\n"), t = NSTextStorage(string: "other\n")
        let a = view(), b = view()
        a.textContentStorage!.adopt(s)
        b.textContentStorage!.adopt(s)
        a.textContentStorage!.adopt(t)
        b.insertText("Y", replacementRange: NSRange(location: 0, length: 0))
        b.insertText("X", replacementRange: NSRange(location: 4, length: 0))
        #expect(s.string == "YoneX\ntwo\n")
        #expect(laidOut(b) == "YoneX\ntwo\n")
        #expect(laidOut(a) == "other\n")
        a.insertText("!", replacementRange: NSRange(location: 0, length: 0))
        #expect(laidOut(a) == "!other\n")
    }

    @Test func completionFollowsTheFocusedPane() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "other.typ": "ab #"])
        let other = try await p.open(RelPath("other.typ")!)
        #expect(p.selectedFile?.raw == "main.typ")
        let list = try #require(await p.complete(in: other.path, at: 4, explicit: true))
        type(other, "re")
        #expect(p.live(list, caret: 6) == nil)               // main.typ is the active editor
        p.focusedEditorFile = other.path
        #expect(p.live(list, caret: 6)?.range == NSRange(location: 4, length: 2))
        p.focusedEditorFile = nil
        #expect(p.live(list, caret: 6) == nil)
    }
}
#endif
