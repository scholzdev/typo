import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

struct PairEditTests {
    func decide(_ typed: String, _ text: String, _ sel: NSRange, _ mode: SyntaxMode = .code,
                auto: Set<Int> = [], marked: Bool = false) -> PairAction {
        PairEdit.decide(typed: typed, text: text, selection: sel, mode: mode, autoInserted: auto, marked: marked)
    }
    func caret(_ n: Int) -> NSRange { NSRange(location: n, length: 0) }
    func pair(_ opener: String, _ closer: String, at n: Int) -> PairAction {
        .edit(range: caret(n), replacement: opener + closer, selection: caret(n + 1), autoCloser: n + 1)
    }

    @Test func markedTextDoesNothing() {
        #expect(decide("(", "", caret(0), marked: true) == .none)
    }

    @Test func nextCharacterRule() {
        #expect(decide("(", "", caret(0)) == pair("(", ")", at: 0))
        #expect(decide("(", "a ", caret(2)) == pair("(", ")", at: 2))
        #expect(decide("(", "a b", caret(2)) == .none)                              // before a word: just `(`
        #expect(decide("(", "(x)", caret(2)) == pair("(", ")", at: 2))
        #expect(decide("[", "()", caret(1)) == pair("[", "]", at: 1))               // before a closer
        #expect(decide("{", "x\n", caret(1)) == pair("{", "}", at: 1))              // before whitespace
    }

    @Test func selectionWraps() {
        #expect(decide("(", "ab cd", NSRange(location: 3, length: 2)) ==
                .edit(range: NSRange(location: 3, length: 2), replacement: "(cd)", selection: NSRange(location: 4, length: 2), autoCloser: nil))
        #expect(decide("$", "ab cd", NSRange(location: 0, length: 2), .markup) ==
                .edit(range: NSRange(location: 0, length: 2), replacement: "$ab$", selection: NSRange(location: 1, length: 2), autoCloser: nil))
    }

    @Test func stepOverOnlyAutoInsertedAdjacentCloser() {
        #expect(decide(")", "(x)", caret(2), auto: [2]) == .stepOver)
        #expect(decide(")", "(x)", caret(2), auto: []) == .none)              // typed by hand: insert normally
        #expect(decide(")", "(x)", caret(2), auto: [5]) == .none)             // not adjacent
        #expect(decide(")", "(x)y", caret(2), auto: [3]) == .none)            // closer is not directly after the caret
        #expect(decide("\"", "f(\"\")", caret(3), .code, auto: [3]) == .stepOver)
        #expect(decide("]", "(x)", caret(2), auto: [2]) == .none)             // a different closer
    }

    @Test func quoteAndDollarByMode() {
        #expect(decide("\"", "", caret(0), .markup) == .none)                  // smart quote in prose
        #expect(decide("\"", "", caret(0), .text) == .none)
        #expect(decide("\"", "", caret(0), .code) == pair("\"", "\"", at: 0))
        #expect(decide("\"", "", caret(0), .math) == pair("\"", "\"", at: 0))
        #expect(decide("$", "", caret(0), .markup) == pair("$", "$", at: 0))
        #expect(decide("$", "", caret(0), .math) == .none)
        #expect(decide("$", "", caret(0), .code) == .none)
        #expect(decide("(", "", caret(0), .markup) == pair("(", ")", at: 0))   // brackets everywhere
        #expect(decide("(", "", caret(0), .text) == pair("(", ")", at: 0))
    }

    @Test func multiCharacterInsertsAreIgnored() {
        #expect(decide("()", "", caret(0)) == .none)
        #expect(decide("a", "", caret(0)) == .none)
    }

    @Test func backspaceDeletesEmptyAutoPair() {
        let del = PairAction.edit(range: NSRange(location: 1, length: 2), replacement: "", selection: caret(1), autoCloser: nil)
        #expect(PairEdit.decideBackspace(text: "a()", selection: caret(2), autoInserted: [2]) == del)
        #expect(PairEdit.decideBackspace(text: "a()", selection: caret(2), autoInserted: []) == .none)       // typed by hand
        #expect(PairEdit.decideBackspace(text: "a(x)", selection: caret(3), autoInserted: [3]) == .none)     // not empty
        #expect(PairEdit.decideBackspace(text: "a\"\"", selection: caret(2), autoInserted: [2]) == del)
        #expect(PairEdit.decideBackspace(text: "a()", selection: caret(2), autoInserted: [2], marked: true) == .none)
    }

    @Test func trackedClosersFollowEdits() {
        #expect(PairEdit.shift([5], edit: NSRange(location: 2, length: 0), newLength: 3) == [8])
        #expect(PairEdit.shift([5], edit: NSRange(location: 5, length: 0), newLength: 1) == [6])    // typed right before it
        #expect(PairEdit.shift([5], edit: NSRange(location: 6, length: 0), newLength: 1) == [5])
        #expect(PairEdit.shift([5], edit: NSRange(location: 4, length: 2), newLength: 0) == [])     // deleted with it
    }
}

struct PairEditSwitchTests {
    @Test func disabledMakesEveryCasePlain() {
        func caret(_ n: Int) -> NSRange { NSRange(location: n, length: 0) }
        let cases: [(String, String, NSRange, Set<Int>)] = [("(", "", caret(0), []), (")", "(x)", caret(2), [2]), ("(", "ab cd", NSRange(location: 3, length: 2), []), ("\"", "", caret(0), [])]
        for (t, text, sel, auto) in cases {
            #expect(PairEdit.decide(typed: t, text: text, selection: sel, mode: .code, autoInserted: auto, enabled: false) == .none)
        }
        #expect(PairEdit.decideBackspace(text: "()", selection: caret(1), autoInserted: [1], enabled: false) == .none)
        #expect(PairEdit.decideBackspace(text: "()", selection: caret(1), autoInserted: [1]) != .none)
    }
}
