import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct RefactoringTests {
    private func r(_ l: Int, _ n: Int = 0) -> NSRange { NSRange(location: l, length: n) }

    private func offered(_ text: String, _ sel: NSRange) -> [Refactoring] {
        Refactorings.available(in: text, selection: sel, syntax: SyntaxMirror(text))
    }

    /// `text` after applying the refactoring called `title`; nil when it is not offered.
    private func apply(_ title: String, _ text: String, _ sel: NSRange) -> String? {
        offered(text, sel).first { $0.title == title }.map { (text as NSString).replacingCharacters(in: $0.range, with: $0.snippet.text) }
    }

    @Test func mathDelimitersAreTaggedOneByOne() {
        for t in ["$x^2$", "$ x^2 $"] {
            let d = SyntaxMirror(t).spans(in: r(0, t.utf16.count)).filter { $0.tag == .mathDelimiter }.map(\.range)
            #expect(d == [r(0, 1), r(t.utf16.count - 1, 1)])
        }
    }

    @Test func equationToggles() {
        #expect(apply("Convert to Block Equation", "a $x^2$ b", r(4)) == "a $ x^2 $ b")
        #expect(apply("Convert to Inline Equation", "a $ x^2 $ b", r(5, 2)) == "a $x^2$ b")
        #expect(apply("Convert to Inline Equation", "$\n  x\n  y\n$", r(3)) == "$x\n  y$")
        let round = apply("Convert to Block Equation", "$x$", r(1))!
        #expect(apply("Convert to Inline Equation", round, r(2)) == "$x$")
        #expect(offered("a $x$ b", r(0)).isEmpty)
        #expect(offered("a $x$ b $y$", r(5, 4)).filter { $0.title.hasPrefix("Convert") }.isEmpty)
    }

    @Test func headings() {
        #expect(apply("Promote Heading", "== A\ntext", r(2)) == "= A\ntext")
        #expect(apply("Demote Heading", "== A\ntext", r(2)) == "=== A\ntext")
        #expect(offered("= A", r(1)).map(\.title) == ["Demote Heading"])
        #expect(apply("Demote Heading", "x\n= Last", r(5)) == "x\n== Last")
        #expect(offered("text\n= A", r(1)).isEmpty)
        #expect(offered("#let a = 1", r(5)).isEmpty)
        #expect(offered("```\n= raw\n```", r(6)).isEmpty)
    }

    @Test func extractInMarkup() throws {
        let text = "Hello big world"
        let x = try #require(offered(text, r(6, 3)).first { $0.title == "Extract to Variable" })
        #expect(x.range == r(0, 9))
        #expect(x.snippet.text == "#let name = [big]\nHello #name")
        #expect(x.snippet.placeholders == [r(5, 4), r(25, 4)] && x.snippet.groups == [1, 1])
        #expect(offered("a\nb", r(0, 3)).filter { $0.title == "Extract to Variable" }.isEmpty)
        #expect(offered(text, r(6)).filter { $0.title == "Extract to Variable" }.isEmpty)
    }

    @Test func extractInsideAWordEndsTheName() throws {
        let x = try #require(offered("Hello bigger", r(6, 3)).first { $0.title == "Extract to Variable" })
        #expect(x.snippet.text == "#let name = [big]\nHello #name;")
        #expect(x.snippet.placeholders == [r(5, 4), r(25, 4)])
        let m = try #require(offered("$ a b $", r(2, 1)).first { $0.title == "Extract to Variable" })
        #expect(m.snippet.text == "#let name = $a$\n$ name")
    }

    @Test func extractInMath() throws {
        let text = "$ a + b $"
        let x = try #require(offered(text, r(2, 5)).first { $0.title == "Extract to Variable" })
        #expect(x.snippet.text == "#let name = $a + b$\n$ name")
        #expect(x.snippet.groups == [1, 1] && x.snippet.placeholders.map(\.length) == [4, 4])
        // The equation starts on an earlier line: not offered.
        #expect(offered("$\n  a + b\n$", r(4, 1)).filter { $0.title == "Extract to Variable" }.isEmpty)
        #expect(offered("#let a = 1 + 2", r(9, 5)).filter { $0.title == "Extract to Variable" }.isEmpty)
    }
}
