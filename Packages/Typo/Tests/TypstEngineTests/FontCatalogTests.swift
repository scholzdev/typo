import Foundation
import Testing
@testable import TypstEngine

struct FontCatalogTests {
    func face(_ family: String, _ weight: Int = 400, italic: Bool = false, mono: Bool = false, design: FontDesign = .sans, source: FontSource = .system) -> FontFace {
        FontFace(family: family, style: "\(weight)", weight: weight, italic: italic, monospaced: mono, design: design, source: source)
    }

    @Test func coreTextTraitsMapToCSS() {
        #expect(FontFace.weight(fromTrait: 0) == 400)
        #expect(FontFace.weight(fromTrait: 0.4) == 700)
        #expect(FontFace.weight(fromTrait: -0.45) == 300)
        #expect(FontFace.weight(fromTrait: 0.7) == 900)
        #expect(FontFace.design(fromClass: 2) == .serif && FontFace.design(fromClass: 8) == .sans && FontFace.design(fromClass: 10) == .other)
    }

    @Test func groupsFacesIntoSortedFamilies() {
        let f = FontCatalog.group([face("b", 700), face("a", 400, italic: true), face("a", 400), face("B2")])
        #expect(f.map(\.name) == ["a", "b", "B2"])
        #expect(f[0].faces.map(\.italic) == [false, true] && f[0].hasItalic && f[0].weights == [400])
    }

    @Test func filtersByCategoryAndQuery() {
        let fams = FontCatalog.group([face("Serifo", design: .serif), face("Sansa"), face("Mona", mono: true), face("Mine", source: .project)])
        func names(_ q: String, _ c: FontCategory) -> [String] { FontCatalog.filter(fams, query: q, category: c).map(\.name) }
        #expect(names("", .serif) == ["Serifo"] && names("", .sans) == ["Mine", "Sansa"] && names("", .mono) == ["Mona"] && names("", .project) == ["Mine"])
        #expect(names("sa", .all) == ["Sansa"])
    }

    @Test func reconcileUsesTypstSpellingAndBuiltIns() {
        let system = FontCatalog.group([face("arial"), face("Hidden"), face("Libertinus Serif", design: .serif)])
        let r = FontCatalog.reconcile(system: system, typstNames: ["Arial", "Libertinus Serif", "DejaVu Sans Mono"])
        #expect(r.map(\.name) == ["Arial", "Libertinus Serif", "DejaVu Sans Mono"])
        #expect(r.map(\.source) == [.system, .builtin, .builtin])
        #expect(r[2].isMonospaced && r[2].hasItalic)
        #expect(FontCatalog.reconcile(system: system, typstNames: []).map(\.name).contains("DejaVu Sans Mono"))
    }

    @Test func unmatchedTypstFamiliesGetNoMadeUpFaces() {
        let r = FontCatalog.reconcile(system: [], typstNames: ["Odd Name", ".Hidden"])
        #expect(r.map(\.name) == ["Odd Name"] && r[0].faces.isEmpty && r[0].source == .system)
    }

    @Test func projectFamilyBeatsInstalledCopy() {
        let m = FontCatalog.merge(project: FontCatalog.group([face("Inter", source: .project), face("Own", source: .project)]), system: FontCatalog.group([face("inter"), face("Other")]))
        #expect(m.map(\.name) == ["Inter", "Own", "Other"] && m[0].source == .project)
    }

    @Test func buildsSourceText() {
        #expect(FontCatalog.setRule(["Fira Sans"]) == #"#set text(font: "Fira Sans")"#)
        #expect(FontCatalog.value(["A", "B"]) == #"("A", "B")"#)
        #expect(FontCatalog.value([#"We"ird\"#]) == #""We\"ird\\""#)
    }

    @Test func replacesTheFontStringUnderTheCaret() throws {
        let text = #"#set text(font: "Old", size: 11pt)"#
        let r = try #require(FontCatalog.insertion(of: ["New"], in: text, caret: 20))
        #expect(r.range == NSRange(location: 16, length: 5) && r.text == #""New""#)
        let list = try #require(FontCatalog.insertion(of: ["A", "B"], in: text, caret: 16))
        #expect(list.text == #"("A", "B")"#)
    }

    @Test func replacesAFallbackList() throws {
        let text = #"#text(font: ("A", "B)"), [x])"#
        let r = try #require(FontCatalog.valueRange(at: 18, in: text))
        #expect((text as NSString).substring(with: r) == #"("A", "B)")"#)
    }

    @Test func insertsARuleOutsideAFontString() throws {
        let text = #"#set text(font: "Old")"# + "\nHello"
        let r = try #require(FontCatalog.insertion(of: ["X"], in: text, caret: text.utf16.count))
        #expect(r.range.length == 0 && r.text == #"#set text(font: "X")"#)
        #expect(FontCatalog.valueRange(at: 2, in: text) == nil)
        #expect(FontCatalog.valueRange(at: 5, in: #"#set text(size: 1pt, myfont: "x")"#) == nil)
        #expect(FontCatalog.insertion(of: [], in: text, caret: 0) == nil)
    }
}
