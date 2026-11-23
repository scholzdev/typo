import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

struct BracketMatchTests {
    /// `|` is the caret; returns [opener, closer] locations.
    func pair(_ marked: String) -> [Int]? {
        let text = marked.replacingOccurrences(of: "|", with: "")
        let caret = (marked as NSString).range(of: "|").location
        let mirror = SyntaxMirror(text)
        return BracketMatch.pair(in: text as NSString, caret: caret, mode: { mirror.mode(at: $0) })
            .map { [$0.0.location, $0.1.location] }
    }

    @Test func afterCloser() { #expect(pair("#f(a, (b))|") == [2, 9]) }
    @Test func beforeOpener() { #expect(pair("#f|(x)") == [2, 4]) }
    @Test func nested() { #expect(pair("#{| let a = (1, [2]) }") == [1, 20]) }
    @Test func stringIgnored() { #expect(pair("#f(|\"(\")") == [2, 6]) }
    @Test func commentIgnored() { #expect(pair("#f(|a // (\n)") == [2, 10]) }
    @Test func mismatch() { #expect(pair("#f(]|") == nil) }
    @Test func contentBlock() { #expect(pair("#box[hi]|") == [4, 7]) }
    @Test func noBracket() { #expect(pair("ab|c") == nil) }
    @Test func fallsBackToAfter() { #expect(pair("#f(x))|[y]") == [6, 8]) }

    @Test func depths() {
        let text = "#f(a, [b], \"(\") // {\n)]"
        let mirror = SyntaxMirror(text)
        let d = BracketMatch.depths(in: text as NSString, mode: { mirror.mode(at: $0) })
        #expect(d.map(\.depth) == [0, 1, 1, 0, -1, -1])
    }
}
