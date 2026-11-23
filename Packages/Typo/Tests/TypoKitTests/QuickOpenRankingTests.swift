import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct QuickOpenRankingTests {
    private func file(_ raw: String) -> QuickOpenItem { QuickOpenItem(kind: .file, name: RelPath(raw)!.name, file: RelPath(raw)!) }
    private func names(_ q: String, _ items: [QuickOpenItem], recent: [QuickOpenItem.Identity] = [], open: [RelPath] = []) -> [String] {
        QuickOpen.results(q, items: items, recent: recent, open: open).map { $0.item.file?.raw ?? $0.item.name }
    }

    @Test func subsequenceOnlyCaseInsensitive() {
        #expect(QuickOpen.fuzzy("itp", "intro.typ") != nil)
        #expect(QuickOpen.fuzzy("ITRO", "intro.typ") != nil)
        #expect(QuickOpen.fuzzy("pti", "intro.typ") == nil)
        #expect(QuickOpen.fuzzy("", "intro.typ") == nil)
    }

    @Test func prefixBeatsWordStartBeatsScattered() {
        let items = ["xintro.typ", "my-intro.typ", "intro.typ"].map(file)
        #expect(names("intro", items) == ["intro.typ", "my-intro.typ", "xintro.typ"])
    }

    @Test func camelWordStartsAndContiguousRuns() {
        let a = QuickOpen.fuzzy("fb", "fooBar")!.score, b = QuickOpen.fuzzy("fb", "fabulous")!.score
        #expect(a > b)
        #expect(QuickOpen.fuzzy("abc", "abcxyz")!.score > QuickOpen.fuzzy("abc", "axbxcxyz")!.score)
    }

    @Test func shorterNameWinsAndRecentFirst() {
        #expect(names("main", ["main-old.typ", "main.typ"].map(file)) == ["main.typ", "main-old.typ"])
        let same = ["a/notes.typ", "b/notes.typ"].map(file)
        #expect(names("notes", same, recent: [same[1].identity]) == ["b/notes.typ", "a/notes.typ"])
        #expect(names("notes", same, open: [RelPath("b/notes.typ")!]) == ["b/notes.typ", "a/notes.typ"])
    }

    @Test func projectSymbolsAboveBuiltins() {
        let items = [QuickOpenItem(kind: .builtin, name: "text", file: nil), QuickOpenItem(kind: .function, name: "text", file: RelPath("lib.typ")!)]
        #expect(QuickOpen.results("text", items: items, recent: []).map(\.item.kind) == [.function, .builtin])
    }

    @Test func matchedRangesForBold() {
        #expect(QuickOpen.fuzzy("intro", "my-intro.typ")!.matched == [NSRange(location: 3, length: 5)])
        #expect(QuickOpen.fuzzy("mt", "main.typ")!.matched == [NSRange(location: 0, length: 1), NSRange(location: 5, length: 1)])
    }

    @Test func sameNamedSymbolsCollapseToAlternates() {
        let s = { (f: String) in QuickOpenItem(kind: .label, name: "intro", file: RelPath(f)!, line: 1) }
        let r = QuickOpen.results("intro", items: [s("a.typ"), s("b.typ"), s("c.typ")], recent: [])
        #expect(r.count == 1)
        #expect(r[0].alternates.count == 2)
    }

    @Test func emptyQueryListsRecentResultsThenOpenFiles() {
        let items = ["a.typ", "b.typ", "c.typ"].map(file) + [QuickOpenItem(kind: .heading(level: 1), name: "Intro", file: RelPath("a.typ")!, line: 7)]
        let gone = QuickOpenItem(kind: .label, name: "gone", file: RelPath("a.typ")!, line: 1).identity
        // The heading was chosen at line 3; edits above it moved it to 7 since.
        let chosen = QuickOpenItem(kind: .heading(level: 1), name: "Intro", file: RelPath("a.typ")!, line: 3).identity
        #expect(names("  ", items, recent: [chosen, gone, items[2].identity], open: [RelPath("b.typ")!, RelPath("c.typ")!]) == ["a.typ", "c.typ", "b.typ"])
        #expect(QuickOpen.results("", items: items, recent: [chosen]).first?.item.line == 7)
    }

    @Test func theRecencyBonusGoesToTheChosenItemOnly() {
        let h = { (n: String) in QuickOpenItem(kind: .heading(level: 1), name: n, file: RelPath("a.typ")!, line: 1) }
        let items = [h("Results"), h("Rationale")]
        #expect(QuickOpen.results("r", items: items, recent: [items[1].identity]).first?.item.name == "Rationale")
        #expect(QuickOpen.results("r", items: items, recent: [items[0].identity]).first?.item.name == "Results")
    }

    @Test func recentsArePersistedPerProjectNewestFirstAndCapped() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = QuickOpenRecents(ProjectID(), defaults: defaults), other = QuickOpenRecents(ProjectID(), defaults: defaults)
        let a = file("a.typ"), b = file("b.typ")
        store.record(a); store.record(b)
        // The same heading chosen again after it moved replaces its old entry.
        store.record(QuickOpenItem(kind: .heading(level: 2), name: "X", file: RelPath("a.typ")!, line: 3))
        store.record(QuickOpenItem(kind: .heading(level: 2), name: "X", file: RelPath("a.typ")!, line: 9))
        store.record(a)
        #expect(store.load().map(\.name) == ["a.typ", "X", "b.typ"] && store.load()[1].line == 9 && other.load().isEmpty)
        for i in 0..<40 { store.record(QuickOpenItem(kind: .label, name: "l\(i)", file: RelPath("a.typ")!)) }
        #expect(store.load().count == 30 && store.load().first?.name == "l39")
        store.clear()
        #expect(store.load().isEmpty)
    }

    @Test func alternatesExpandIntoRowsOfTheirOwn() {
        let s = { (f: String) in QuickOpenItem(kind: .label, name: "intro", file: RelPath(f)!, line: 1) }
        let r = QuickOpen.results("intro", items: [s("a.typ"), s("b.typ"), s("c.typ"), file("intro.typ")], recent: [])
        let group = r.firstIndex { !$0.alternates.isEmpty }!
        #expect(QuickOpen.rows(r, expanded: []).count == 2)
        let rows = QuickOpen.rows(r, expanded: [group])
        #expect(rows.count == 4 && rows.filter { $0.alternate != nil }.map(\.result) == [group, group])
        let child = r[group].alternate(1)
        #expect(child.item.file == r[group].alternates[1].file && child.matched == r[group].matched && child.alternates.isEmpty)
    }

    @Test func bookmarksAreItemsNamedLikeTheNavigator() {
        var titled = CodeBookmark(path: RelPath("ch/intro.typ")!, line: 4)
        titled.title = "Check this"
        let items = QuickOpen.bookmarks([CodeBookmark(path: RelPath("ch/intro.typ")!, line: 4), titled,
                                         CodeBookmark(path: RelPath("refs.bib")!, line: 0, isFile: true)],
                                        snippets: [titled.id: "= Intro"])
        #expect(items.map(\.name) == ["intro: 5", "Check this", "refs.bib"])
        #expect(items.map(\.line) == [5, 5, 0] && items[1].detail == "= Intro" && items[1].kind == .bookmark(titled.id))
        #expect(QuickOpen.results("check", items: items, recent: []).first?.item.kind == .bookmark(titled.id))
    }

    @Test func fileLineQueries() {
        #expect(QuickOpen.location("main:42")! == ("main", 42, nil))
        #expect(QuickOpen.location("main.typ:42:7")! == ("main.typ", 42, 7))
        #expect(QuickOpen.location("fig:intro") == nil)
        #expect(QuickOpen.location("main") == nil)
        let r = QuickOpen.results("main:3", items: ["main.typ", "other.typ"].map(file), recent: [])
        #expect(r.first?.item.file?.raw == "main.typ")
        #expect(r.first?.line == 3)
    }

    @Test func goToLineInput() {
        #expect(QuickOpen.lineTarget("42", current: 5)! == (42, nil))
        #expect(QuickOpen.lineTarget(" 42:7 ", current: 5)! == (42, 7))
        #expect(QuickOpen.lineTarget("+10", current: 5)! == (15, nil))
        #expect(QuickOpen.lineTarget("-10", current: 5)! == (1, nil))
        #expect(QuickOpen.lineTarget("abc", current: 5) == nil)
        #expect(QuickOpen.lineTarget("0", current: 5) == nil)
    }

    @Test func lineRanges() {
        let t = "one\ntwo\nthree"
        #expect(QuickOpen.range(ofLine: 2, column: nil, in: t) == NSRange(location: 4, length: 3))
        #expect(QuickOpen.range(ofLine: 2, column: 2, in: t) == NSRange(location: 5, length: 0))
        #expect(QuickOpen.range(ofLine: 2, column: 99, in: t) == NSRange(location: 7, length: 0))
        #expect(QuickOpen.range(ofLine: 99, column: nil, in: t) == NSRange(location: 13, length: 0))
    }

    @Test func symbolsOfASmallProject() {
        let main = "= Intro <intro>\n#let accent = red\n#let note(body) = body\n== Details\n#{ let inner = 1 }\n"
        let ch = "#import \"main.typ\": note\n= Chapter\n"
        let bib = "@book{knuth84, title = {The TeXbook}, author = {Knuth}, year = 1984}\n"
        let items = QuickOpen.symbols([(RelPath("main.typ")!, main), (RelPath("ch/one.typ")!, ch), (RelPath("refs.bib")!, bib)])
        let found = Set(items.map { "\($0.kind) \($0.name) \($0.file!.raw):\($0.line)" })
        #expect(found == [
            "heading(level: 1) Intro main.typ:1", "label intro main.typ:1", "variable accent main.typ:2", "function note main.typ:3",
            "heading(level: 2) Details main.typ:4", "heading(level: 1) Chapter ch/one.typ:2", "bibKey knuth84 refs.bib:1",
        ])
        let note = items.first { $0.name == "note" }!
        #expect((main as NSString).substring(with: note.range) == "note")
        let intro = items.first { $0.kind == .heading(level: 1) && $0.name == "Intro" }!
        #expect((main as NSString).substring(with: intro.range) == "Intro")
    }

    @Test func builtinsOpenBundledDocs() {
        #expect(QuickOpen.builtins.contains { $0.name == "text" })
        #expect(TypstDocs.doc("text")?.signature.hasPrefix("text(") == true)
    }
}
