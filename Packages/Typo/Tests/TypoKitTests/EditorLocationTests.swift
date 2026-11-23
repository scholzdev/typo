import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct EditorLocationTests {
    private func pos(_ o: Int, _ t: String) -> String { let p = EditorLocation.position(of: o, in: t); return "\(p.line):\(p.column)" }

    @Test func linesAndColumns() {
        #expect(pos(0, "abc\ndef") == "1:1")
        #expect(pos(2, "abc\ndef") == "1:3")
        #expect(pos(4, "abc\ndef") == "2:1")
        #expect(pos(7, "abc\ndef") == "2:4")        // last line, no trailing newline
        #expect(pos(4, "abc\n") == "2:1")           // after the trailing newline
        #expect(pos(1, "\tx") == "1:2")             // a tab is one column
        #expect(pos(99, "ab") == "1:3")             // clamped
    }

    @Test func charactersNotUTF16Units() {
        #expect(pos(2, "😀x") == "1:2")             // the emoji is two UTF-16 units
        #expect(pos(2, "e\u{301}x") == "1:2")       // e + combining acute is one character
        #expect(pos(2, "a😀b") == "1:3")
    }

    @Test func crlfIsOneBreak() {
        #expect(pos(5, "ab\r\ncd") == "2:2")
        #expect(pos(4, "ab\r\ncd") == "2:1")
        #expect(pos(3, "ab\rcd") == "2:1")
    }

    @Test func statusText() {
        let t = "one\ntwo\nthree"
        #expect(EditorLocation.status(selection: NSRange(location: 5, length: 0), in: t) == "Line 2, Col 2")
        #expect(EditorLocation.status(selection: NSRange(location: 1, length: 2), in: t) == "1 line, 2 characters selected")
        #expect(EditorLocation.status(selection: NSRange(location: 1, length: 9), in: t) == "3 lines, 9 characters selected")
        #expect(EditorLocation.status(selection: NSRange(location: 0, length: 4), in: t) == "1 line, 4 characters selected")
        #expect(EditorLocation.status(selection: NSRange(location: 0, length: 2), in: "😀") == "1 line, 1 character selected")
    }

    @Test func offsetOfLine() {
        let t = "a\nbb\r\nccc"
        #expect(EditorLocation.offset(ofLine: 1, in: t) == 0)
        #expect(EditorLocation.offset(ofLine: 2, in: t) == 2)
        #expect(EditorLocation.offset(ofLine: 3, in: t) == 6)
        #expect(EditorLocation.offset(ofLine: 99, in: t) == 9)
    }
}

@Suite struct NavigationHistoryTests {
    private let a = RelPath("a.typ")!, b = RelPath("b.typ")!
    private let text = (0..<40).map { _ in "line" }.joined(separator: "\n")      // 5 UTF-16 units per line

    /// At (a, 0) with the file's own start entry behind it.
    private func seeded() -> NavigationHistory {
        var h = NavigationHistory()
        h.record(from: a, to: NavPlace(file: a, offset: 0), text: text)
        return h
    }

    private func depth(_ h: NavigationHistory) -> Int {
        var h = h, n = 0
        while h.back() != nil { n += 1 }
        return n
    }

    @Test func smallMoveInSameFileIsNotRecorded() {
        var h = seeded()
        h.record(from: a, to: NavPlace(file: a, offset: 10), text: text)        // 2 lines
        #expect(depth(h) == 1)
    }

    @Test func bigJumpAndOtherFileAreRecorded() {
        var h = seeded()
        h.record(from: a, to: NavPlace(file: a, offset: 100), text: text)
        #expect(depth(h) == 2)
        h.record(from: a, to: NavPlace(file: b), text: nil)
        #expect(depth(h) == 3)
    }

    @Test func reselectingTheOpenFileIsNotRecorded() {
        var h = NavigationHistory()
        h.record(from: a, to: NavPlace(file: a), text: nil)
        #expect(!h.canGoBack)
    }

    @Test func newVisitAfterBackDropsForward() {
        var h = NavigationHistory()
        h.record(from: a, to: NavPlace(file: b), text: nil)
        #expect(h.back() == NavPlace(file: a))
        #expect(h.canGoForward)
        h.record(from: a, to: NavPlace(file: a, offset: 150), text: text)
        #expect(!h.canGoForward)
        #expect(h.canGoBack)
    }

    @Test func backAndForwardDoNotRecord() {
        var h = NavigationHistory()
        h.record(from: a, to: NavPlace(file: b), text: nil)
        _ = h.back(); _ = h.forward()
        #expect(h.forward() == nil)
        #expect(depth(h) == 1)
    }
}
