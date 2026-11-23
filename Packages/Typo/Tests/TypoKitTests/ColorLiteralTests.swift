import Testing
import Foundation
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct ColorLiteralTests {
    /// Pins what the filter relies on: the `rgb` name is a `function` token, its argument a `string` token.
    @Test func tokensOfRgbLiteral() {
        let t = TypstSyntax.tokens(in: "#rect(fill: rgb(\"#ff8800\"))").map { "\($0.tag)\($0.range.location),\($0.range.length)" }
        #expect(t == ["function0,1", "function1,4", "punctuation5,1", "punctuation10,1", "function12,3", "punctuation15,1", "string16,9", "punctuation25,1", "punctuation26,1"])
    }

    @Test func detectsAllForms() {
        let text = "#let a = (rgb(\"#f80\"), rgb(\"#f80a\"), rgb(\"#ff8800\"), rgb(\"#ff880080\"), rgb(255, 136, 0), rgb(255, 136, 0, 128), luma(51), luma(50%))"
        let l = ColorLiterals.scan(text)
        #expect(l.count == 8)
        #expect(l.map { (text as NSString).substring(with: $0.range) }[2] == "rgb(\"#ff8800\")")
        #expect(l[0].red == 1 && abs(l[0].green - 136.0 / 255) < 1e-9 && l[0].blue == 0 && l[0].alpha == 1)
        #expect(abs(l[1].alpha - 170.0 / 255) < 1e-9)
        #expect(abs(l[3].alpha - 128.0 / 255) < 1e-9)
        #expect(l[4].range == (text as NSString).range(of: "rgb(255, 136, 0)"))
        #expect(abs(l[5].alpha - 128.0 / 255) < 1e-9)
        #expect(abs(l[6].red - 0.2) < 1e-9 && l[6].red == l[6].blue)
        #expect(l[7].green == 0.5)
    }

    @Test func ignoresCommentsRawStringsAndMarkup() {
        let text = "// rgb(1, 2, 3)\n/* luma(5) */\n`rgb(1,2,3)`\n```\nrgb(1,2,3)\n```\n#let s = \"rgb(1,2,3)\"\nplain rgb(1,2,3) text\n"
        #expect(ColorLiterals.scan(text).isEmpty)
    }

    @Test func rejectsInvalidValues() {
        #expect(ColorLiterals.scan("#let a = rgb(300, 0, 0)").isEmpty)
        #expect(ColorLiterals.scan("#let a = rgb(\"#ff88\")").count == 1)   // 4 digits is #rgba
        #expect(ColorLiterals.scan("#let a = rgb(\"#ff880\")").isEmpty)
        #expect(ColorLiterals.scan("#let a = luma(300)").isEmpty)
        #expect(ColorLiterals.scan("#let a = luma(120%)").isEmpty)
    }

    @Test func sourceRoundTrips() {
        for (r, g, b, a) in [(1.0, 136.0 / 255, 0.0, 1.0), (0.0, 0.2, 1.0, 128.0 / 255)] {
            let s = ColorLiterals.source(red: r, green: g, blue: b, alpha: a)
            let back = ColorLiterals.scan("#let x = " + s)
            #expect(back.count == 1)
            #expect(abs(back[0].red - r) < 1e-9 && abs(back[0].green - g) < 1e-9 && abs(back[0].alpha - a) < 1e-9)
        }
        #expect(ColorLiterals.source(red: 1, green: 0.5333333, blue: 0, alpha: 1) == "rgb(\"#ff8800\")")
        #expect(ColorLiterals.source(red: 0, green: 0, blue: 0, alpha: 0.5).hasSuffix("80\")"))
    }
}

@MainActor @Suite struct ColorKernTests {
    private func kerned(_ b: Buffer) -> [Int] {
        var out: [Int] = []
        b.storage.enumerateAttribute(.kern, in: NSRange(location: 0, length: b.storage.length)) { v, r, _ in
            if v != nil { out += Array(r.location..<NSMaxRange(r)) }
        }
        return out
    }

    @Test func onlyTheClosingParenCarriesKern() async throws {
        let src = "#rect(fill: rgb(\"#ff8800\"))\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": src])
        let b = try await p.open(RelPath("main.typ")!)
        let close = (src as NSString).range(of: "\")").location + 1
        #expect(kerned(b) == [close])

        type(b, "#let c = luma(20)\n")        // a new literal gains one
        #expect(kerned(b).count == 2)
        replace(b, NSRange(location: 0, length: 0), with: "ab ")   // typing elsewhere keeps the set stable
        #expect(kerned(b).count == 2)
        replace(b, (b.storage.string as NSString).range(of: "rgb(\"#ff8800\")"), with: "")
        #expect(kerned(b).count == 1)
        b.colorSwatches = false
        #expect(kerned(b).isEmpty)
        b.colorSwatches = true
        #expect(kerned(b).count == 1)
    }
}
