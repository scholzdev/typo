import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct MultiCursorTests {
    func r(_ l: Int, _ n: Int = 0) -> NSRange { NSRange(location: l, length: n) }
    func apply(_ e: (edits: [Replacement], ranges: [NSRange]), to s: String) -> String {
        var ns = s as NSString
        for x in e.edits.sorted(by: { $0.range.location > $1.range.location }) { ns = ns.replacingCharacters(in: x.range, with: x.text) as NSString }
        return ns as String
    }

    @Test func mergeJoinsOverlapsAndDuplicates() {
        #expect(MultiCursor.merge([r(5), r(1, 3), r(5), r(2, 4), r(9)]) == [r(1, 5), r(9)])
    }

    @Test func selectNextWordThenOccurrences() {
        let t = "foo bar foo baz foo" as NSString
        let a = MultiCursor.selectNext(in: t, selected: [r(1)], primary: r(1))!
        #expect(a.primary == r(0, 3))
        let b = MultiCursor.selectNext(in: t, selected: a.ranges, primary: a.primary)!
        #expect(b.primary == r(8, 3))
        let c = MultiCursor.selectNext(in: t, selected: b.ranges, primary: b.primary)!
        #expect(c.ranges == [r(0, 3), r(8, 3), r(16, 3)])
        #expect(MultiCursor.selectNext(in: t, selected: c.ranges, primary: c.primary) == nil)   // all taken
        #expect(MultiCursor.selectAll(in: t, selected: [r(5)], primary: r(1))!.ranges == [r(0, 3), r(8, 3), r(16, 3)])
    }

    @Test func columnSelection() {
        let t = "abcdef\nab\nabcdef" as NSString
        #expect(MultiCursor.column(in: t, from: 1, to: 14) == [r(1, 3), r(8, 1), r(11, 3)])
    }

    @Test func caretOnAdjacentLineClamps() {
        let t = "abcdef\nab\nabcdef" as NSString
        #expect(MultiCursor.caretOnAdjacentLine(in: t, from: 5, up: false) == 9)
        #expect(MultiCursor.caretOnAdjacentLine(in: t, from: 9, up: false) == 12)
        #expect(MultiCursor.caretOnAdjacentLine(in: t, from: 2, up: true) == nil)
        #expect(MultiCursor.caretOnAdjacentLine(in: t, from: 12, up: false) == nil)
    }

    @Test func typingAndDeletingFanOut() {
        let s = "ab\ncd\nef"
        let typed = MultiCursor.insert("X", at: [r(1), r(4), r(7)])
        #expect(apply(typed, to: s) == "aXb\ncXd\neXf")
        #expect(typed.ranges == [r(2), r(6), r(10)])
        let del = MultiCursor.delete(in: s as NSString, at: [r(1), r(4), r(7)], forward: false)
        #expect(apply(del, to: s) == "b\nd\nf")
        #expect(del.ranges == [r(0), r(2), r(4)])
        let fwd = MultiCursor.delete(in: s as NSString, at: [r(0, 2), r(3)], forward: true)
        #expect(apply(fwd, to: s) == "\nd\nef")
    }

    @Test func adjacentBackspacesDoNotOverlap() {
        let s = "abcd"
        let del = MultiCursor.delete(in: s as NSString, at: [r(2), r(3)], forward: false)
        #expect(apply(del, to: s) == "ad")
        #expect(del.ranges == [r(1)])
    }

    @Test func pasteLinePerCaretOrWhole() {
        let s = "a\nb\nc"
        #expect(apply(MultiCursor.paste("1\n2\n3", at: [r(1), r(3), r(5)]), to: s) == "a1\nb2\nc3")
        #expect(apply(MultiCursor.paste("1\n2", at: [r(1), r(3), r(5)]), to: s) == "a1\n2\nb1\n2\nc1\n2")
        #expect(MultiCursor.copied(s as NSString, [r(0, 1), r(4, 1)]) == "a\nc")
    }

    @Test func movesKeepAnchorsWhenExtending() {
        let t = "ab cd\nef gh" as NSString
        let m = MultiCursor.move([.init(r(1)), .init(r(7))], in: t, .wordRight, extend: true)
        #expect(m.map(\.range) == [r(1, 1), r(7, 1)])
        let down = MultiCursor.move([.init(r(1))], in: t, .down, extend: false)
        #expect(down == [.init(anchor: 7, head: 7)])
        let collapse = MultiCursor.move([.init(r(1, 3))], in: t, .left, extend: false)
        #expect(collapse == [.init(anchor: 1, head: 1)])
    }

    @Test func deleteToLineEdges() {
        let t = "abc def\nghi\n" as NSString
        let back = MultiCursor.deleteToLineEdge(in: t, at: [r(2), r(10)], forward: false)
        #expect(apply(back, to: t as String) == "c def\ni\n")
        #expect(back.ranges == [r(0), r(6)])
        let fwd = MultiCursor.deleteToLineEdge(in: t, at: [r(2), r(7)], forward: true)
        #expect(apply(fwd, to: t as String) == "abghi\n")                    // the second takes the newline
    }

    @Test func transposePerCaret() {
        let t = "abcd\nefgh" as NSString
        let x = MultiCursor.transpose(in: t, at: [r(1), r(5), r(7)])
        #expect(apply(x, to: t as String) == "bacd\negfh")
        #expect(x.ranges == [r(2), r(5), r(8)])
    }

    @Test func outdentOncePerLine() {
        let t = "    a\n\tb\n  c\nd" as NSString
        let x = MultiCursor.outdent(in: t, at: [r(4), r(5), r(7), r(11), r(13)], width: 4)
        #expect(apply(x, to: t as String) == "a\nb\nc\nd")
        #expect(x.ranges == [r(0), r(1), r(2), r(4), r(6)])
    }

    @Test func typedPairsPerCaret() {
        let t = "a b" as String
        let x = MultiCursor.typed("(", at: [r(1), r(3)]) { PairEdit.decide(typed: "(", text: t, selection: $0, mode: .code, autoInserted: []) }
        #expect(apply((x.edits, x.ranges), to: t) == "a() b()")
        #expect(x.ranges == [r(2), r(6)])
        #expect(x.closers == [2, 6])
        let step = MultiCursor.typed(")", at: [r(2)]) { PairEdit.decide(typed: ")", text: "a() b", selection: $0, mode: .code, autoInserted: [2]) }
        #expect(step.ranges == [r(3)])
    }
}
