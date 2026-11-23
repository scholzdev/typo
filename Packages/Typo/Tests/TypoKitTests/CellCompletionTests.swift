import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct CellCompletionTests {
    private func req(_ s: String, _ caret: Int? = nil) -> CellCompletion.Request? {
        CellCompletion.request(in: s, caret: caret ?? (s as NSString).length)
    }

    @Test func detectsTriggerAndTypedName() {
        #expect(req("see @fig:a")?.typed == "fig:a")
        #expect(req("see @fig:a")?.range == NSRange(location: 5, length: 5))
        #expect(req("@")?.typed == "")
        #expect(req("x #my-var")?.trigger == "#")
        #expect(req("@fig rest", 4)?.typed == "fig")          // caret mid-text
        #expect(req("plain text") == nil)
        #expect(req("a@b") == nil)                             // an address, not a reference
        #expect(req("#a.b") == nil)                            // field access is not a name
        #expect(req("@fig ") == nil)
    }

    @Test func listsLetAndImportNames() {
        let text = """
        #let x = 1
          #let f(a) = a
        #let (p, q) = (1, 2)
        a #let inline = 3
        #import "@preview/pkg:0.1.0": one, two as three, *
        #import "lib.typ": (four)
        #import "lib.typ" as lib
        """
        #expect(CellCompletion.letNames(in: text) == ["x", "f", "one", "three", "four"])
    }

    @Test func mergesLabelsAndBibKeysPrefixFirst() {
        let f = RelPath("a.typ")!
        let index = LabelIndex.build([(f, "= A <intro>\n#figure[x] <fig:a>\n#cite(<knuth>)"), (RelPath("r.bib")!, "@book{knuth, title={T}}")])
        let bib = [BibFile(id: RelPath("r.bib")!, entries: [BibEntry(key: "knuth", title: "TAOCP", authors: "Knuth", year: 1968, kind: "book")], error: nil)]
        let c = CellCompletion(labels: index, bibliography: bib, sources: [(f, "#let total = 1\n#bibliography(\"r.bib\")")], main: f, file: f)
        let at = c.items(for: .init(trigger: "@", range: NSRange(), typed: ""))
        #expect(at.map(\.label) == ["fig:a", "intro", "knuth"])
        #expect(at.first { $0.label == "knuth" }?.detail == "Knuth (1968): TAOCP")
        #expect(at.first { $0.label == "intro" }?.detail == "<intro> in a.typ")
        #expect(c.items(for: .init(trigger: "@", range: NSRange(), typed: "k")).map(\.label) == ["knuth"])
        #expect(c.items(for: .init(trigger: "#", range: NSRange(), typed: "to")).map(\.label) == ["total"])
    }

    @Test func offersOnlyWhatTheDocumentReaches() {
        let main = RelPath("main.typ")!, ch = RelPath("ch/one.typ")!, other = RelPath("draft.typ")!, util = RelPath("lib/util.typ")!
        let sources: [(file: RelPath, text: String)] = [
            (main, "#include \"ch/one.typ\"\n#bibliography((\"refs.bib\"))"),
            (ch, "= One <one>\n#import \"../lib/util.typ\": helper"),
            (util, "#let helper = 1\n#let shade = red\n<util-label>"),
            (other, "= Draft <draft>\n#let secret = 2"),
        ]
        let index = LabelIndex.build(sources + [(RelPath("refs.bib")!, "@book{a1, title={A}}"), (RelPath("old.bib")!, "@book{b2, title={B}}")])
        #expect(CellCompletion.reachable(from: main, text: Dictionary(uniqueKeysWithValues: sources.map { ($0.file, $0.text) })) == [main, ch, util])
        let c = CellCompletion(labels: index, bibliography: [], sources: sources, main: main, file: ch)
        #expect(c.items(for: .init(trigger: "@", range: NSRange(), typed: "")).map(\.label) == ["a1", "one", "util-label"])
        let hash = c.items(for: .init(trigger: "#", range: NSRange(), typed: ""))
        #expect(hash.map(\.label) == ["helper", "secret", "shade"])
        #expect(hash.first { $0.label == "helper" }?.detail == nil && hash.first { $0.label == "shade" }?.detail == "Imports it from lib/util.typ")
        #expect(c.missingImports(cells: ["#shade and #helper", "#secret", "#text[x]"], file: ch)
                == "#import \"../draft.typ\": secret\n#import \"../lib/util.typ\": shade\n")
    }

    @Test func importsGoAfterTheLastImport() {
        #expect(CellCompletion.importInsertionPoint(in: "= Hi") == 0)
        let t = "#import \"a.typ\": x\n#set text(lang: \"de\")\n#import \"b.typ\": y\n= Ä"
        #expect(CellCompletion.importInsertionPoint(in: t) == (t as NSString).range(of: "= Ä").location)
    }

    @Test func pathsResolveLikeTypst() {
        let f = RelPath("a/b.typ")!
        #expect(CellCompletion.resolve("c.typ", from: f)?.raw == "a/c.typ")
        #expect(CellCompletion.resolve("/c.typ", from: f)?.raw == "c.typ")
        #expect(CellCompletion.resolve("../x/./y.typ", from: f)?.raw == "x/y.typ")
        #expect(CellCompletion.resolve("@preview/x:1.0.0", from: f) == nil)
        #expect(CellCompletion.relativePath(to: RelPath("a/c.typ")!, from: f) == "c.typ")
        #expect(CellCompletion.relativePath(to: RelPath("d/e.typ")!, from: f) == "../d/e.typ")
        #expect(CellCompletion.relativePath(to: RelPath("e.typ")!, from: RelPath("m.typ")!) == "e.typ")
    }
}

@Suite(.serialized) @MainActor struct CellEngineCompletionTests {
    private static let main = """
    #import "lib.typ": shade
    #let total = 1
    = Intro <intro>
    #table(
      columns: 2,
      [a], [b],
    )
    #text[x]
    """

    private func setUp() async throws -> (Project, Buffer, TableModel, String) {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.main, "lib.typ": "#let shade(x) = x\n"])
        let b = try await p.open(RelPath("main.typ")!)
        _ = try await p.exportPageCount()                                   // the compiled document supplies labels
        let text = b.storage.string
        let at = (text as NSString).range(of: "table").location
        guard case .table(let m)? = b.table(at: at) else { throw CancellationError() }
        return (p, b, m, text)
    }

    @Test func hashCompletesScopeAndImportsWithoutTouchingTheEditorList() async throws {
        let (p, b, m, text) = try await setUp()
        let fallback = CellCompletion()
        let first = await p.complete(in: b.path, at: (text as NSString).length - 4, explicit: true)          // sets the editor's active list
        #expect(first != nil)
        let before = try #require(p.activeList)
        let r = try #require(CellCompletion.request(in: "#", caret: 1))
        let items = await p.completeCell(m, row: 0, column: 1, text: "#", caret: 1, request: r, in: b.path, buffer: text, fallback: fallback, timeout: .seconds(10))
        let labels = items.map(\.label)
        #expect(labels.contains("total") && labels.contains("shade") && labels.contains("text"))
        let at = CellCompletion.request(in: "@", caret: 1)!
        let refs = await p.completeCell(m, row: 0, column: 1, text: "@", caret: 1, request: at, in: b.path, buffer: text, fallback: fallback, timeout: .seconds(10))
        #expect(refs.map(\.label).contains("intro"))
        #expect(p.activeList?.seq == before.seq && p.activeList?.from == before.from && p.activeList?.items == before.items)
    }

    @Test func aTooSlowEngineFallsBack() async throws {
        let (p, b, m, text) = try await setUp()
        let fallback = CellCompletion()
        let r = try #require(CellCompletion.request(in: "#", caret: 1))
        let items = await p.completeCell(m, row: 0, column: 1, text: "#", caret: 1, request: r, in: b.path, buffer: text, fallback: fallback, timeout: .zero)
        #expect(items == fallback.items(for: r))
    }
}
