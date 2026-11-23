import Foundation
import Testing
@testable import TypstEngine

@Test func scanFindsLabelsRefsStringsAndComments() {
    let text = "= Intro <intro>\nSee @intro. // TODO fix\n#include \"ch/a.typ\"\n#image(\"img.png\")"
    let ns = text as NSString
    let tokens = TypstSyntax.tokens(in: text)
    func texts(_ t: SyntaxTag) -> [String] { tokens.filter { $0.tag == t }.map { ns.substring(with: $0.range) } }
    #expect(texts(.label) == ["<intro>"])
    #expect(texts(.ref).contains("@intro"))
    #expect(texts(.string) == ["\"ch/a.typ\"", "\"img.png\""])
    #expect(texts(.comment) == ["// TODO fix"])
}
