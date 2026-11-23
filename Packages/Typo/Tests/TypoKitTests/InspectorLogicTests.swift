import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct InspectorLogicTests {
    func apply(_ r: Replacement?, to s: String) -> String {
        guard let r else { return s }
        return (s as NSString).replacingCharacters(in: r.range, with: r.text)
    }

    let figure = "= A\n#figure(\n  image(\"a.png\", width: 50%),\n  caption: [A (nice) cat],\n  placement: top,\n) <cat>\nText"

    @Test func figureFields() throws {
        let at = (figure as NSString).range(of: "image").location
        let f = try #require(FigureInfo.at(at, in: figure))
        #expect(f.value(.caption) == "A (nice) cat")
        #expect(f.value(.placement) == "top")
        #expect(f.value(.label) == "cat")
        #expect(f.value(.kind) == "")
        #expect(FigureInfo.at(0, in: figure) == nil)
    }

    @Test func figureEdits() throws {
        let f = try #require(FigureInfo.at((figure as NSString).range(of: "image").location, in: figure))
        #expect(apply(f.edit(.caption, to: "Dog"), to: figure).contains("caption: [Dog],"))
        #expect(apply(f.edit(.label, to: "dog"), to: figure).contains(") <dog>\n"))
        #expect(apply(f.edit(.label, to: ""), to: figure).contains(",\n)\nText"))
        #expect(f.edit(.label, to: "no good") == nil)
        #expect(apply(f.edit(.placement, to: ""), to: figure).contains("[A (nice) cat],\n)"))
        #expect(apply(f.edit(.kind, to: "table"), to: figure).contains("placement: top, kind: table"))
        #expect(apply(f.edit(.caption, to: "x]"), to: figure).contains("caption: \"x]\""))
    }

    @Test func figureWithoutArgumentsOrLabel() throws {
        let s = "#figure(image(\"a.png\"))[x]"
        let f = try #require(FigureInfo.at(10, in: s))
        #expect(f.labelRange == nil)
        #expect(apply(f.edit(.caption, to: "Hi"), to: s) == "#figure(image(\"a.png\"), caption: [Hi])[x]")
        #expect(apply(f.edit(.label, to: "a"), to: s) == s + " <a>")
        let empty = "#figure()"
        #expect(apply(FigureInfo.at(8, in: empty)?.edit(.kind, to: "raw"), to: empty) == "#figure(kind: raw)")
    }

    @Test func editAnchoredToShownFigure() throws {
        let s = "#figure([a], caption: [One]) <a>\n#figure([b], caption: [Two]) <b>"
        let first = try #require(FigureInfo.at(3, in: s))
        let reparsed = try #require(FigureInfo.at(first.call.range.location + 1, in: s))
        #expect(reparsed.call == first.call)
        #expect(apply(reparsed.edit(.caption, to: "X"), to: s).hasPrefix("#figure([a], caption: [X]) <a>"))
        #expect(FigureInfo.at((s as NSString).range(of: "[b]").location, in: s)?.value(.caption) == "Two")
    }

    @Test func stringCaptionStaysString() throws {
        let s = "#figure(caption: \"Hi\", [x])"
        let f = try #require(FigureInfo.at(10, in: s))
        #expect(f.value(.caption) == "Hi")
        #expect(apply(f.edit(.caption, to: "Yo"), to: s) == "#figure(caption: \"Yo\", [x])")
    }

    @Test func callsSkipStringsAndNest() {
        let s = "#table(columns: 2, [a], figure(x)) // figure(\n\"figure(\""
        #expect(TypstCalls.calls(named: ["figure"], in: s).count == 1)
        let t = TypstCalls.calls(named: ["table"], in: s)
        #expect(t.first?.args.count == 3)
        #expect(t.first?.arg("columns") != nil)
    }

    @Test func packagesAndFonts() {
        let s = "#import \"@preview/cetz:0.3.1\": canvas\n#import \"@preview/cetz:0.3.1\"\n#include \"@local/x:1.0.0\"\n#set text(font: (\"Libertinus Serif\", \"Noto\"), lang: \"de\")\n#text(font: \"Inter\")[x]"
        #expect(InspectorScan.packages(in: s).map(\.spec) == ["@preview/cetz:0.3.1", "@local/x:1.0.0"])
        #expect(InspectorScan.fonts(in: s) == ["Libertinus Serif", "Noto", "Inter"])
    }

    @Test func includes() throws {
        let file = try #require(RelPath("ch/one.typ"))
        let s = "#include \"two.typ\"\n#import \"../main.typ\": x\n#include \"/lib/a.typ\"\n#include \"@preview/x:1.0.0\""
        #expect(InspectorScan.includedFiles(in: s, from: file).map(\.path.raw) == ["ch/two.typ", "main.typ", "lib/a.typ"])
    }

    @Test func citedAndReading() {
        #expect(InspectorScan.uncited(keys: ["b", "a", "c"], referenced: ["b"]) == ["a", "c"])
        #expect(InspectorScan.readingMinutes(words: 0) == 0)
        #expect(InspectorScan.readingMinutes(words: 100) == 1)
        #expect(InspectorScan.readingMinutes(words: 2300) == 10)
    }
}
