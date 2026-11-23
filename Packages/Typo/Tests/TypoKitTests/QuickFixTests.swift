import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct QuickFixTests {
    static let main = RelPath("main.typ")!

    static func project(_ files: [String: String]) async throws -> (Project, Buffer) {
        let (p, _) = try await TestEnv.project(files: files)
        let b = try await p.open(main)
        _ = await p.settle()
        return (p, b)
    }

    /// Fixes for the first fixable diagnostic.
    static func fixes(_ p: Project) async -> [QuickFix] {
        guard let d = p.diagnostics.first(where: QuickFixes.mayFix) else { return [] }
        return await p.quickFixes(for: d)
    }

    static func apply(_ fix: QuickFix, in p: Project) async throws {
        for (file, edits) in fix.edits { try await p.edit(file, edits, actionName: "Quick Fix") }
        _ = await p.settle()
    }

    @Test func closestBasics() {
        #expect(QuickFixes.closest("greet", in: ["gret", "great", "grape", "other", "greet"]) == ["great", "gret"])
        #expect(QuickFixes.closest("ab", in: ["ba", "xyz"]) == ["ba"])
        #expect(QuickFixes.closest("intro", in: ["Intro"]) == ["Intro"])
        #expect(QuickFixes.closest("a", in: ["bb"]) == [])
        #expect(QuickFixes.closest("abcdef", in: ["abcdeg", "abcxyz", "abxyef"], limit: 1) == ["abcdeg"])
    }

    @Test func mayFixIsMessageOnly() {
        func d(_ m: String, _ origin: Diagnostic.Origin? = nil) -> Diagnostic {
            Diagnostic(id: 0, severity: .error, message: m, hints: [], origin: origin ?? .project(Location(file: Self.main, range: NSRange(location: 0, length: 1))))
        }
        #expect(QuickFixes.mayFix(d("unknown variable: foo")))
        #expect(QuickFixes.mayFix(d("label `<x>` does not exist in the document")))
        #expect(QuickFixes.mayFix(d("file not found (searched at /tmp/a.png)")))
        #expect(!QuickFixes.mayFix(d("expected expression")))
        #expect(!QuickFixes.mayFix(d("unknown variable: foo", .detached)))
    }

    @Test func unknownLabelChangesToClosest() async throws {
        let (p, b) = try await Self.project(["main.typ": "#set heading(numbering: \"1.\")\n= Intro <intro>\n@intor\n"])
        let fixes = await Self.fixes(p)
        #expect(fixes.map(\.title) == ["Change to @intro"])
        try await Self.apply(fixes[0], in: p)
        #expect(b.storage.string == "#set heading(numbering: \"1.\")\n= Intro <intro>\n@intro\n")
        #expect(p.diagnostics.isEmpty)
    }

    @Test func unknownLabelSuggestsBibKeys() async throws {
        let (p, _) = try await Self.project(["main.typ": "@smith2020\n#bibliography(\"refs.bib\")\n", "refs.bib": "@book{smith2021, title={X}, author={Y}, year={2021}}\n"])
        #expect(await Self.fixes(p).map(\.title) == ["Change to @smith2021"])
    }

    @Test func unknownVariableChangesToClosest() async throws {
        let (p, b) = try await Self.project(["main.typ": "#let great(x) = x\n#greet(1)\n"])
        let fixes = await Self.fixes(p)
        #expect(fixes.map(\.title) == ["Change to `great`"])
        try await Self.apply(fixes[0], in: p)
        #expect(b.storage.string == "#let great(x) = x\n#great(1)\n")
        #expect(p.diagnostics.isEmpty)
    }

    @Test func missingImportIsInsertedAtTop() async throws {
        let (p, b) = try await Self.project(["lib.typ": "#let foo = [F]\n", "main.typ": "= Title\n#foo\n"])
        let fixes = await Self.fixes(p)
        #expect(fixes.map(\.title) == ["Import `foo` from \"lib.typ\""])
        try await Self.apply(fixes[0], in: p)
        #expect(b.storage.string == "#import \"lib.typ\": foo\n= Title\n#foo\n")
        #expect(p.diagnostics.isEmpty)
    }

    /// The user's case: the demo document (set rules, an include) with the call at its end and `utils.typ` beside it.
    @Test func missingImportInARealDocument() async throws {
        let main = "#set page(paper: \"a4\", margin: 2cm)\n#set text(lang: \"de\")\n\n= Einleitung\n#include \"kapitel.typ\"\n\n#let x = 1 + 2\n#x\n#hallo[Welt]\n"
        let (p, b) = try await Self.project(["utils.typ": "#let hallo(name) = [Hallo #name]\n", "kapitel.typ": "= Zweites Kapitel\n", "main.typ": main])
        print("DIAG", p.diagnostics.map { ($0.message, $0.origin) })
        let fixes = await Self.fixes(p)
        #expect(fixes.map(\.title) == ["Import `hallo` from \"utils.typ\""])
        _ = b
    }

    @Test func missingImportGoesAfterExistingImports() async throws {
        let (p, b) = try await Self.project(["lib.typ": "#let foo = [F]\n", "other.typ": "#let bar = 1\n", "main.typ": "#import \"other.typ\": bar\n\n#bar #foo\n"])
        let fixes = await Self.fixes(p)
        try await Self.apply(fixes[0], in: p)
        #expect(b.storage.string == "#import \"other.typ\": bar\n#import \"lib.typ\": foo\n\n#bar #foo\n")
        #expect(p.diagnostics.isEmpty)
    }

    @Test func missingImportExtendsExistingList() async throws {
        let (p, b) = try await Self.project(["lib.typ": "#let foo = [F]\n#let bar = [B]\n", "main.typ": "#import \"lib.typ\": bar\n#bar #foo\n"])
        let fixes = await Self.fixes(p)
        #expect(fixes.map(\.title) == ["Import `foo` from \"lib.typ\""])
        try await Self.apply(fixes[0], in: p)
        #expect(b.storage.string == "#import \"lib.typ\": bar, foo\n#bar #foo\n")
        #expect(p.diagnostics.isEmpty)
    }

    @Test func missingImportUsesRelativePathFromSubfolder() async throws {
        let (p, b) = try await Self.project(["lib.typ": "#let foo = [F]\n", "main.typ": "#include \"ch/a.typ\"\n", "ch/a.typ": "#foo\n"])
        _ = b
        let a = RelPath("ch/a.typ")!
        _ = try await p.open(a)
        _ = await p.settle()
        let d = try #require(p.diagnostics.first { QuickFixes.mayFix($0) })
        let fixes = await p.quickFixes(for: d)
        #expect(fixes.map(\.title) == ["Import `foo` from \"../lib.typ\""])
    }

    @Test(arguments: [
        ("#image(\"logo.pgn\")\n", "logo.png", "Change to \"logo.png\"", "#image(\"logo.png\")\n"),
        ("#include \"chapter.typ\"\n", "chapters.typ", "Change to \"chapters.typ\"", "#include \"chapters.typ\"\n"),
        ("#bibliography(\"ref.bib\")\n", "refs.bib", "Change to \"refs.bib\"", "#bibliography(\"ref.bib\")\n".replacingOccurrences(of: "ref.bib", with: "refs.bib")),
        ("#image(\"logo.png\")\n", "img/logo.png", "Change to \"img/logo.png\"", "#image(\"img/logo.png\")\n"),
    ])
    func missingFileChangesToClosest(src: String, existing: String, title: String, fixed: String) async throws {
        let (p, b) = try await Self.project(["main.typ": src, existing: existing.hasSuffix(".bib") ? "@book{a, title={x}, author={y}, year={2000}}\n" : existing.hasSuffix(".typ") ? "x\n" : "png"])
        let fixes = await Self.fixes(p)
        #expect(fixes.first?.title == title)
        guard let first = fixes.first else { return }
        try await Self.apply(first, in: p)
        #expect(b.storage.string == fixed)
        #expect(!p.diagnostics.contains { $0.message.hasPrefix("file not found") })
    }

    @Test func noFixesForUnrelatedErrors() async throws {
        let (p, _) = try await Self.project(["main.typ": "#let x = \n#(1 + )\n"])
        #expect(!p.diagnostics.isEmpty)
        for d in p.diagnostics { #expect(await p.quickFixes(for: d).isEmpty) }
        let (q, _) = try await Self.project(["main.typ": "#zzzzzzzz\n", "lib.typ": "#let foo = 1\n"])
        #expect(await Self.fixes(q).isEmpty)
    }
}
