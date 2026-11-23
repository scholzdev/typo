import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct LabelIndexTests {
    static func file(_ s: String) -> RelPath { RelPath(s)! }

    @Test func findsDefinitionsReferencesAndSkipsSupplementsCommentsStringsRaw() {
        let text = """
        = Intro <intro>
        See @intro. And @intro[Section] or @sec:one, @intro[see @other].
        // @intro <intro> in a comment
        #let s = "@intro <intro>"
        `@intro <intro>`
        #cite(<knuth>) #figure[x] <fig:a>
        """
        let ix = LabelIndex.build([(Self.file("a.typ"), text)])
        let ns = text as NSString
        func t(_ d: [String: [LabelSite]], _ n: String) -> [String] { (d[n] ?? []).map { ns.substring(with: $0.token) } }
        #expect(t(ix.definitions, "intro") == ["<intro>"])
        #expect(t(ix.references, "intro") == ["@intro", "@intro", "@intro"])
        #expect(t(ix.references, "sec:one") == ["@sec:one"])
        #expect(t(ix.references, "other") == ["@other"])
        #expect(t(ix.definitions, "fig:a") == ["<fig:a>"])
        #expect(ix.definitions["knuth"] == nil && t(ix.references, "knuth") == ["<knuth>"])
    }

    @Test func labelStringFormsAreIndexedButRefStringsAndPlainStringsAreNot() {
        let text = "= H <x>\n#ref(label(\"x\")) #show label(\"x\"): set text(red)\n#ref(\"x\") #mylabel(\"x\") #let s = \"x\"\n"
        let f = Self.file("a.typ")
        let ix = LabelIndex.build([(f, text)])
        #expect(ix.target(of: "x")?.site.token.location == 4 && ix.target(of: "x")?.count == 1)
        #expect(ix.validate("y", replacing: "x") == nil)
        #expect(ix.renameSummary(of: "x") == "1 definition and 2 references in 1 file")
        var ns = text as NSString
        for r in (ix.rename("x", to: "yy")[f] ?? []).sorted(by: { $0.range.location > $1.range.location }) { ns = ns.replacingCharacters(in: r.range, with: r.text) as NSString }
        #expect(ns as String == "= H <yy>\n#ref(label(\"yy\")) #show label(\"yy\"): set text(red)\n#ref(\"x\") #mylabel(\"x\") #let s = \"x\"\n")
    }

    @Test func insertedLabelCallIsADefinition() {
        let text = "#figure([A], caption: [c]) #label(\"z\")\n@z"
        let f = Self.file("a.typ")
        let ix = LabelIndex.build([(f, text)])
        #expect(ix.target(of: "z") != nil)
        #expect(ix.hit(in: f, at: 36)?.kind == .definition)
        #expect(ix.renameSites(of: "z").defs.count == 1 && ix.renameSites(of: "z").refs.count == 1)
    }

    @Test func bibliographyKeys() {
        let bib = "@comment{x,}\n@book{knuth84,\n  title={T}}\n@article {lamport94 ,\n}"
        let yml = "# c\nsmith20:\n  type: Book\n  title: T\nlee21:\n  type: Web\n"
        let ix = LabelIndex.build([(Self.file("r.bib"), bib), (Self.file("r.yml"), yml)])
        #expect(Set(ix.bibKeys.keys) == ["knuth84", "lamport94", "smith20", "lee21"])
        let s = ix.bibKeys["knuth84"]![0]
        #expect((bib as NSString).substring(with: s.token) == "knuth84")
    }

    @Test func targetPrefersLabelAndCountsDuplicates() {
        let ix = LabelIndex.build([(Self.file("a.typ"), "<x> <x>"), (Self.file("r.bib"), "@book{x,\n}\n@book{y,\n}")])
        #expect(ix.target(of: "x")?.count == 2 && ix.target(of: "x")?.site.token.location == 0)
        #expect(ix.target(of: "y")?.site.file == Self.file("r.bib"))
        #expect(ix.target(of: "z") == nil)
        #expect(ix.hit(in: Self.file("a.typ"), at: 3)?.name == "x")
    }

    @Test func validation() {
        let ix = LabelIndex.build([(Self.file("a.typ"), "<a> <b> @a"), (Self.file("r.bib"), "@book{k,\n}")])
        #expect(ix.validate("", replacing: "a") != nil)
        #expect(ix.validate("a b", replacing: "a") != nil)
        #expect(ix.validate("b", replacing: "a") != nil)
        #expect(ix.validate("k", replacing: "a") != nil)
        #expect(ix.validate("a", replacing: "a") != nil)
        #expect(ix.validate("c:1-x.y_z", replacing: "a") == nil)
        #expect(ix.renameSummary(of: "a") == "1 definition and 1 reference in 1 file")
    }

    @Test @MainActor func renameAcrossFilesIncludingClosedOnesKeepsSupplements() async throws {
        let (p, root) = try await TestEnv.project(files: [
            "main.typ": "#include \"b.typ\"\n= H <old>\n@old[Sec] and @old. // @old\n`@old`",
            "b.typ": "See @old, @older.\n",
            "refs.bib": "@book{k1,\n}\n",
        ])
        let ix = await p.labelIndex()
        for (file, edits) in ix.rename("old", to: "new") { try await p.edit(file, edits, actionName: "Rename Label") }
        #expect(p.buffer(for: Self.file("b.typ"))?.storage.string == "See @new, @older.\n")
        #expect(p.buffer(for: Self.file("main.typ"))?.storage.string == "#include \"b.typ\"\n= H <new>\n@new[Sec] and @new. // @old\n`@old`")
        try await p.saveAll()
        #expect(try String(contentsOf: root.appending(path: "b.typ"), encoding: .utf8) == "See @new, @older.\n")
    }

    @Test @MainActor func renamesABibliographyKeyAndItsReferences() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "As @k1 says, @k1[p. 3].", "refs.bib": "@book{k1,\n  title={T}}\n"])
        let ix = await p.labelIndex()
        #expect(ix.renameSummary(of: "k1") == "1 key and 2 references in 2 files")
        for (file, edits) in ix.rename("k1", to: "knuth") { try await p.edit(file, edits) }
        #expect(p.buffer(for: Self.file("main.typ"))?.storage.string == "As @knuth says, @knuth[p. 3].")
        #expect(p.buffer(for: Self.file("refs.bib"))?.storage.string == "@book{knuth,\n  title={T}}\n")
    }

    @Test func todoItemsComeFromCommentsOnly() {
        let text = "= TODO heading\n#let s = \"TODO str\"\n// TODO: first\nText // FIXME second one\n/* XXX block\nsecond line TODO inner */\nTODOS // TODOS no"
        let items = TodoScan.items(in: Self.file("a.typ"), text: text)
        #expect(items.map(\.text) == ["first", "second one", "block", "inner"])
        #expect(items.map(\.line) == [3, 4, 5, 6])
        #expect(items.map(\.marker) == ["TODO", "FIXME", "XXX", "TODO"])
        let ns = text as NSString
        #expect(ns.substring(with: items[1].range) == "FIXME second one")
        #expect(ns.substring(with: items[2].range) == "XXX block")
    }

    @Test @MainActor func projectTodosUseOpenTextAndCache() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "#include \"b.typ\"\n// TODO one", "b.typ": "// FIXME two"])
        var (items, cache) = await p.todos(cache: [:])
        #expect(items.map(\.text).sorted() == ["one", "two"])
        let b = try await p.open(Self.file("main.typ"))
        type(b, " more")
        (items, cache) = await p.todos(cache: cache)
        #expect(items.map(\.text).sorted() == ["one more", "two"])
        #expect(cache.count == 2)
    }
}
