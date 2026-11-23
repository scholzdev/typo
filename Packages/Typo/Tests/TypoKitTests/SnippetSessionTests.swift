import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit

@Suite struct SnippetSessionTests {
    @Test func parsesNumberedAndMirrored() {
        let s = Snippet.parse("#f(${1:a}, ${2:b}, ${1})${0}")
        #expect(s.text == "#f(a, b, a)")
        #expect(s.placeholders == [NSRange(location: 3, length: 1), NSRange(location: 6, length: 1), NSRange(location: 9, length: 1), NSRange(location: 11, length: 0)])
        #expect(s.groups == [1, 2, 1, 0])
        #expect(s.tabOrder == [[NSRange(location: 3, length: 1), NSRange(location: 9, length: 1)], [NSRange(location: 6, length: 1)]])
        #expect(s.exit == NSRange(location: 11, length: 0))
    }

    @Test func numberedBeforeUnnumbered() {
        let s = Snippet.parse("${} ${x} ${2:two} ${1:one}")
        #expect(s.text == " x two one")
        #expect(s.tabOrder.map { $0.map(\.location) } == [[7], [3], [0], [1]])
        #expect(s.selection(insertedAt: 10) == NSRange(location: 17, length: 3))
    }

    @Test func laterMirrorTakesFirstDefault() {
        let s = Snippet.parse("${1}-${1:x}-${1:y}")
        #expect(s.text == "x-x-y")
    }

    @Test func dollarStaysLiteral() {
        let s = Snippet.parse("$ x ${1:y} $")
        #expect(s.text == "$ x y $")
        #expect(s.placeholders == [NSRange(location: 4, length: 1)])
        let m = LibrarySnippet(id: "t", title: "t", summary: "", category: "c", symbol: "s", apply: "$${x}$", isBlock: false).snippet(mode: .markup)
        #expect(m.text == "$x$")
        #expect(m.placeholders == [NSRange(location: 1, length: 1)])
    }

    @Test func exitOnlySelectsExit() {
        let s = Snippet.parse("a${0}b")
        #expect(s.tabOrder.isEmpty)
        #expect(s.selection(insertedAt: 5) == NSRange(location: 6, length: 0))
    }

    @Test func nextPreviousAndExit() {
        var ses = SnippetSession(snippet: .parse("${1:a} ${2:b}${0}"), insertedAt: 10)
        #expect(ses.current == [NSRange(location: 10, length: 1)])
        #expect(ses.next() == NSRange(location: 12, length: 1))
        #expect(ses.previous() == NSRange(location: 10, length: 1))
        #expect(ses.previous() == NSRange(location: 10, length: 1))
        _ = ses.next()
        #expect(ses.next() == NSRange(location: 13, length: 0))
        #expect(ses.isFinished)
        #expect(ses.next() == nil)
    }

    @Test func endsAtSnippetEndWithoutExit() {
        var ses = SnippetSession(snippet: .parse("${}x ${}"), insertedAt: 0)
        _ = ses.next()
        #expect(ses.next() == NSRange(location: 2, length: 0))
    }

    @Test func shiftsAroundEdits() {
        // "a b c": stops at 0, 2, 4. Typing two chars into stop 1 replaces it and moves the later stop.
        var ses = SnippetSession(snippet: .parse("${1:a} ${2:b} ${3:c}"), insertedAt: 0)
        #expect(ses.textDidChange(at: NSRange(location: 0, length: 1), replacementLength: 3, in: "xyz b c") == [])
        #expect(ses.allStops == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 1), NSRange(location: 6, length: 1)])
        // Insert at the end of the first stop grows it.
        #expect(ses.textDidChange(at: NSRange(location: 3, length: 0), replacementLength: 1, in: "xyz! b c") == [])
        #expect(ses.allStops[0] == NSRange(location: 0, length: 4))
        // Edit in literal text between stops ends the session.
        #expect(ses.textDidChange(at: NSRange(location: 4, length: 1), replacementLength: 0, in: "xyz!b c") == nil)
        #expect(ses.isFinished)
    }

    @Test func mirrorsAreReplaced() {
        var ses = SnippetSession(snippet: .parse("${1:ab}+${1}=${2:c}"), insertedAt: 0)   // "ab+ab=c"
        let r = ses.textDidChange(at: NSRange(location: 2, length: 0), replacementLength: 1, in: "abX+ab=c")
        #expect(r == [.init(range: NSRange(location: 4, length: 2), text: "abX")])
        #expect(ses.allStops == [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3), NSRange(location: 8, length: 1)])
        // Editing the mirror updates the first occurrence.
        let r2 = ses.textDidChange(at: NSRange(location: 4, length: 3), replacementLength: 0, in: "abX+=c")
        #expect(r2 == [.init(range: NSRange(location: 0, length: 3), text: "")])
        #expect(ses.allStops == [NSRange(location: 0, length: 0), NSRange(location: 1, length: 0), NSRange(location: 2, length: 1)])
    }

    @Test func containsAndSelect() {
        var ses = SnippetSession(snippet: .parse("${1:a} ${2:b}"), insertedAt: 0)
        #expect(ses.contains(NSRange(location: 2, length: 1)))
        #expect(!ses.contains(NSRange(location: 1, length: 1)))
        let selected = ses.select(NSRange(location: 2, length: 0))
        #expect(selected)
        #expect(ses.current == [NSRange(location: 2, length: 1)])
    }

    @Test func indentationKeepsGroups() {
        let s = Snippet.parse("#f(\n${2:b},\n${1:a}, ${1}\n)")
        let i = s.indentedKeepingGroups(by: "  ")
        #expect(i.groups == s.groups)
        #expect(i.tabOrder.count == 2 && i.tabOrder[0].count == 2)
        #expect((i.text as NSString).substring(with: i.tabOrder[0][0]) == "a")
        #expect(i.needsSession)
        #expect(!Snippet.parse("${}").needsSession)
    }
}
