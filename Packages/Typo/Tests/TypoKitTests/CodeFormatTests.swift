import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct CodeFormatTests {
    func applied(_ text: String, _ r: Replacement?) -> String {
        guard let r else { return text }
        return (text as NSString).replacingCharacters(in: r.range, with: r.text)
    }

    @Test func formatsDocument() {
        let t = "#let  x=( 1,2 )\n"
        #expect(applied(t, CodeFormat.edit(t)).contains("#let x = (1, 2)"))
    }

    @Test func syntaxErrorIsNil() { #expect(CodeFormat.edit("#let x = (1,\n") == nil) }

    @Test func formattedIsNil() { #expect(CodeFormat.edit("#let x = (1, 2)\n") == nil) }

    @Test func selectionOnlyTouchesNode() {
        let a = "#let  a=( 1,2 )", b = "#let  b=( 3,4 )"
        let t = a + "\n\n" + b + "\n"
        let loc = (t as NSString).range(of: "b=").location
        let out = applied(t, CodeFormat.edit(t, range: NSRange(location: loc, length: 1)))
        #expect(out.hasPrefix(a))
        #expect(out.contains("#let b = (3, 4)"))
    }

    @Test func replacementIsMinimal() throws {
        let t = "#let x = (1, 2)\n#let  y=( 1,2 )\n"
        let r = try #require(CodeFormat.edit(t))
        #expect(r.range.location > 0)
        #expect(applied(t, r).contains("#let y = (1, 2)"))
    }
}
