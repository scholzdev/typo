import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct LintTests {
    static func f(_ s: String) -> RelPath { RelPath(s)! }

    /// Hints of `files` as "file:token message", the token being the hinted text.
    static func lint(_ files: [String: String], extra: [String] = [], compiler: [Location] = []) -> [String] {
        let sources = files.keys.sorted().map { (file: f($0), text: files[$0]!) }
        let existing = Set((files.keys.map(f) + extra.map(f)))
        return Lint.hints(LabelIndex.build(sources), sources: sources, existing: existing, compiler: compiler).map { d in
            guard case .project(let loc) = d.origin else { return d.message }
            #expect(d.severity == .hint)
            return "\(loc.file.raw):\((files[loc.file.raw]! as NSString).substring(with: loc.range)) \(d.message)"
        }
    }

    // MARK: Label classification

    @Test func labelsInMarkupDefineAndLabelsInCodeReference() {
        let defs = ["= A <x>", "#figure([a]) <x>", "#[a] <x>", "$ a $ <x>", "#heading[a] <x>", "#let f = [a <x>]", "#label(\"x\")"]
        let refs = ["#show <x>: set text(red)", "#show <x>: it => it", "#context query(<x>)", "#link(<x>)[a]", "#ref(<x>)", "#let l = <x>",
                    "#{ let l = <x> }", "#(<x>)", "#locate(<x>)", "#show heading.where(label: <x>): it => it", "#cite(<x>)", "#ref(label(\"x\"))", "@x"]
        for t in defs {
            let ix = LabelIndex.build([(Self.f("a.typ"), t)])
            #expect(ix.definitions["x"]?.count == 1 && ix.references["x"] == nil, "\(t)")
        }
        for t in refs {
            let ix = LabelIndex.build([(Self.f("a.typ"), t)])
            #expect(ix.definitions["x"] == nil && ix.references["x"]?.count == 1, "\(t)")
        }
    }

    // MARK: Unused labels

    @Test func unusedLabelIsHinted() {
        #expect(Self.lint(["a.typ": "= A <x>\n= B <y>\n@y"]) == ["a.typ:<x> Label <x> is never referenced"])
    }

    @Test func labelsUsedAnywhereAreNotHinted() {
        for use in ["@x", "@x[Sec]", "#ref(<x>)", "#show <x>: set text(red)", "#context query(<x>)", "#link(<x>)[a]",
                    "#ref(label(\"x\"))", "#show heading.where(label: <x>): it => it"] {
            #expect(Self.lint(["a.typ": "= A <x>\n", "b.typ": use]) == [], "\(use)")
        }
    }

    @Test func dynamicLabelNamesSilenceUnusedRules() {
        #expect(Self.lint(["a.typ": "= A <fig-1>\n#for i in range(2) [#ref(label(\"fig-\" + str(i)))]"]) == [])
        #expect(Self.lint(["a.typ": "= A <x>\n#let n = \"x\"\n#ref(label(n))"]) == [])
    }

    // MARK: Duplicate labels

    @Test func duplicateLabelsPointAtEachOther() {
        #expect(Self.lint(["a.typ": "= A <x>\n= B <x>\n@x"]) == [
            "a.typ:<x> Label <x> is also defined at a.typ:2",
            "a.typ:<x> Label <x> is also defined at a.typ:1",
        ])
        #expect(Self.lint(["main.typ": "#include \"ch.typ\"\n= A <x>\n@x", "ch.typ": "= B <x>"]) == [
            "ch.typ:<x> Label <x> is also defined at main.typ:2",
            "main.typ:<x> Label <x> is also defined at ch.typ:1",
        ])
    }

    @Test func sameLabelInSeparateDocumentsOrAsUsesIsNotADuplicate() {
        #expect(Self.lint(["paper.typ": "= A <x>\n@x", "slides.typ": "= A <x>\n@x"]) == [])
        #expect(Self.lint(["a.typ": "= A <x>\n#show <x>: set text(red)\n@x"]) == [])
    }

    // MARK: Uncited bibliography entries

    static let bib = "@book{k1,\n  title={A}}\n@book{k2,\n  title={B}}\n"

    @Test func uncitedKeyOfABibliographyIsHinted() {
        #expect(Self.lint(["main.typ": "@k1\n#bibliography(\"refs.bib\")", "refs.bib": Self.bib]) == ["refs.bib:k2 Bibliography entry “k2” is never cited"])
    }

    @Test func citedFullOrUnusedBibliographiesAreNotHinted() {
        for cite in ["@k2", "@k2[p. 3]", "#cite(<k2>)", "#cite(label(\"k2\"))"] {
            #expect(Self.lint(["main.typ": "@k1 \(cite)\n#bibliography(\"refs.bib\")", "refs.bib": Self.bib]) == [], "\(cite)")
        }
        #expect(Self.lint(["main.typ": "@k1\n#bibliography(\"refs.bib\", full: true)", "refs.bib": Self.bib]) == [])
        #expect(Self.lint(["main.typ": "@k1", "refs.bib": Self.bib]) == [])          // no bibliography call names it
        #expect(Self.lint(["main.typ": "#let d = yaml(\"data.yml\")\n#d.a", "data.yml": "a: 1\nb: 2\n"]) == [])
    }

    // MARK: Missing files

    @Test func missingFileInAPathArgumentIsHinted() {
        #expect(Self.lint(["main.typ": "#image(\"figs/cat.png\")"]) == ["main.typ:\"figs/cat.png\" File “figs/cat.png” does not exist"])
        #expect(Self.lint(["ch/a.typ": "#include \"b.typ\"\n#import \"../lib.typ\": x\n#let t = read(\n  \"t.txt\",\n)"]) == [
            "ch/a.typ:\"b.typ\" File “ch/b.typ” does not exist",
            "ch/a.typ:\"../lib.typ\" File “lib.typ” does not exist",
            "ch/a.typ:\"t.txt\" File “ch/t.txt” does not exist",
        ])
    }

    @Test func pathsThatResolveOrAreNotPathsAreNotHinted() {
        let text = """
        #image("../figs/cat.png") #image("/figs/cat.png", width: 50%) #image("Cat.PNG")
        #import "@preview/cetz:0.3.0": canvas
        #image("https://example.com/a.png")
        #let s = "missing.png"
        #image("figs/" + s)
        #image(".hidden/a.png") #image("a\\.png")
        #x.read("missing.txt") #myimage("missing.png")
        #bibliography(("a.bib", "b.bib"))
        #include "ch" + "1.typ"
        Text with "quotes.png" in markup and image("x.png").
        """
        #expect(Self.lint(["ch/a.typ": text], extra: ["figs/cat.png", "ch/cat.png"]) == [])
    }

    @Test func compilerDiagnosticAtTheSamePlaceWins() {
        let text = "#image(\"cat.png\")"
        #expect(Self.lint(["main.typ": text], compiler: [Location(file: Self.f("main.typ"), range: NSRange(location: 1, length: 16))]) == [])
        #expect(Self.lint(["main.typ": text], compiler: [Location(file: Self.f("main.typ"), range: NSRange(location: 8, length: 0))]) == [])
        #expect(Self.lint(["main.typ": text], compiler: [Location(file: Self.f("other.typ"), range: NSRange(location: 8, length: 7))]).count == 1)
    }
}

@Suite struct ProjectLintTests {
    @Test @MainActor func hintsFollowEditsAcrossCompilesAndStopWhenOff() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= A <x>\n#image(\"gone.png\")\n", "b.typ": "= B <y>\n"])
        _ = await p.settle()
        await p.runLint()
        let main = LintTests.f("main.typ")
        func tokens() -> [String] {
            let text = p.buffer(for: main)!.storage.string as NSString
            return p.lintHints(in: main).compactMap { if case .project(let l) = $0.origin { text.substring(with: l.range) } else { nil } }
        }
        // The compiler reports the missing image itself, so only the label is hinted there.
        #expect(tokens() == ["<x>"])
        #expect(p.lintHints.count == 2)
        let b = try await p.open(main)
        type(b, "Intro ", at: 0)
        #expect(tokens() == ["<x>"])
        _ = await p.settle()                  // a compile trims the log; the hints still need the edit
        #expect(tokens() == ["<x>"])
        p.lintEnabled = false
        #expect(p.lintHints.isEmpty)
        await p.runLint()
        #expect(p.lintHints.isEmpty)
    }
}
