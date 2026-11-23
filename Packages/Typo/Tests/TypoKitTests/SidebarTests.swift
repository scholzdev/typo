import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct SidebarTests {
    // MARK: Outline

    @Test func outlineHasLevelsNumberingPagesAndFileOffsets() async throws {
        let main = "#set heading(numbering: \"1.1\")\n= Alpha\n== Beta ä😀\n#include \"kapitel.typ\"\n#pagebreak()\n= Gamma\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": main, "kapitel.typ": "== Included\nText.\n"])
        _ = await p.settle()
        let o = p.outline
        #expect(o.map(\.title) == ["Alpha", "Beta ä😀", "Included", "Gamma"])
        #expect(o.map(\.level) == [1, 2, 2, 1])
        #expect(o.map(\.numbering) == ["1", "1.1", "1.2", "2"])
        #expect(o.map(\.page) == [0, 0, 0, 1])
        #expect(o[0].y < o[1].y && o[1].y < o[2].y)
        #expect(o.map(\.file.raw) == ["main.typ", "main.typ", "kapitel.typ", "main.typ"])
        let ns = main as NSString
        #expect(o[1].offset == ns.range(of: "== Beta").location)
        #expect(o[3].offset == ns.range(of: "= Gamma").location)
        #expect(o[2].offset == 0)
    }

    @Test func outlineOffsetsFollowLaterEditsAndSurviveAFailedCompile() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= One\n= Two\n"])
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        type(b, "😀 ", at: 0)
        #expect(p.outline.map(\.offset) == [0 + 3, 6 + 3].map { $0 })
        type(b, "#undefinedfunc()\n", at: 0)
        _ = await p.settle()                                      // fails: no document, outline is the last good one
        #expect(p.outline.map(\.title) == ["One", "Two"])
        let ns = b.storage.string as NSString
        #expect(p.outline[1].offset == ns.range(of: "= Two").location)
    }

    @Test func outlineOfDemoFixture() async throws {
        let (p, _) = try await TestEnv.project("demo", main: "ui-test.typ")
        _ = await p.settle()
        let titles = p.outline.map(\.title)
        #expect(titles == ["Einleitung", "Unterabschnitt", "Hauptteil", "Tabelle", "Formeln", "Schluss", "Bibliografie"])
        #expect(p.outline.map(\.level) == [1, 2, 1, 2, 2, 1, 1])
    }

    // MARK: Symbols

    @Test func symbolCatalog() {
        let all = SymbolCatalog.all
        #expect(all.first { $0.name == "alpha" && !$0.isEmoji }?.text == "α")
        #expect(all.first { $0.name == "arrow.r.long" }?.text == "⟶")
        let emoji = all.first { $0.isEmoji }
        #expect(emoji != nil && !(emoji?.text.isEmpty ?? true))
        #expect(all.contains { $0.isEmoji && $0.name == "face.grin" })
        #expect(all.count > 1000)
    }

    @Test func symbolInsertionPerMode() throws {
        let alpha = try #require(SymbolCatalog.all.first { $0.name == "alpha" && !$0.isEmoji })
        #expect(SymbolCatalog.insertion(for: alpha, mode: .math) == "alpha")
        #expect(SymbolCatalog.insertion(for: alpha, mode: .markup) == "#sym.alpha")
        #expect(SymbolCatalog.insertion(for: alpha, mode: .code) == "sym.alpha")
        #expect(SymbolCatalog.insertion(for: alpha, mode: .text) == "α")
        let grin = try #require(SymbolCatalog.all.first { $0.isEmoji && $0.name == "face.grin" })
        #expect(SymbolCatalog.insertion(for: grin, mode: .markup) == "#emoji.face.grin")
        #expect(SymbolCatalog.insertion(for: grin, mode: .code) == "emoji.face.grin")
        #expect(SymbolCatalog.insertion(for: grin, mode: .math) == "emoji.face.grin")
    }

    @Test func insertedSymbolCodeCompilesInEachMode() async throws {
        let alpha = try #require(SymbolCatalog.all.first { $0.name == "alpha" && !$0.isEmoji })
        let grin = try #require(SymbolCatalog.all.first { $0.isEmoji && $0.name == "face.grin" })
        let text = "$\(SymbolCatalog.insertion(for: alpha, mode: .math))$ \(SymbolCatalog.insertion(for: alpha, mode: .markup)) "
            + "#\(SymbolCatalog.insertion(for: grin, mode: .code)) #{\(SymbolCatalog.insertion(for: alpha, mode: .code))}\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let r = try #require(await p.settle())
        #expect(r.snapshot.diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(r.snapshot.pageCount == 1)
    }

    @Test func recentSymbolsComeFirstAndPersist() throws {
        let defaults = UserDefaults(suiteName: "typstcore-recent-\(UUID().uuidString)")!
        let recents = RecentSymbols(defaults: defaults)
        let list = SymbolCatalog.all
        let beta = try #require(list.first { $0.name == "beta" && !$0.isEmoji })
        let alpha = try #require(list.first { $0.name == "alpha" && !$0.isEmoji })
        recents.use(beta); recents.use(alpha); recents.use(beta)
        #expect(recents.ids == [beta.id, alpha.id])
        #expect(RecentSymbols(defaults: defaults).ids == [beta.id, alpha.id])
        let shown = SymbolCatalog.filter(list, query: "", recent: recents.ids)
        #expect(Array(shown.prefix(2)) == [beta, alpha])
        let hits = SymbolCatalog.filter(list, query: "arrow.r.long", recent: [])
        #expect(hits.contains { $0.text == "⟶" })
        #expect(SymbolCatalog.filter(list, query: "α", recent: []).contains { $0.name == "alpha" })
    }

    // MARK: Bibliography

    @Test func bibliographyOfDemoFixture() async throws {
        let (p, _) = try await TestEnv.project("demo", main: "ui-test.typ")
        let files = await p.references()
        #expect(files.map(\.id.raw) == ["refs.bib"])
        let e = try #require(files.first).entries
        #expect(e.map(\.key) == ["knuth84", "madje2022", "typstdocs"])
        #expect(e.map(\.title) == ["The TeXbook", "A Programmable Markup Language for Typesetting", "Typst Documentation"])
        #expect(e.map(\.year) == [1984, 2022, 2026])
        #expect(e[0].authors == "Donald E. Knuth")
        #expect(e[0].kind == "Book")
        #expect(files[0].error == nil)
    }

    @Test func malformedBibliographyReportsAnError() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= x\n", "bad.bib": "@book{x, title = {unclosed", "ok.yml": "a:\n  type: Book\n  title: Y\n  date: 2001\n", "bad.yml": "a: [1, 2\n"])
        let files = Dictionary(uniqueKeysWithValues: await p.references().map { ($0.id.raw, $0) })
        #expect(files["bad.bib"]?.error?.isEmpty == false)
        #expect(files["bad.bib"]?.entries.isEmpty == true)
        #expect(files["bad.yml"]?.error?.isEmpty == false)
        #expect(files["ok.yml"]?.entries.map(\.key) == ["a"])
        #expect(files["ok.yml"]?.entries.first?.year == 2001)
    }

    @Test func citationInsertionPerMode() {
        #expect(BibliographyFile.citation("knuth84", mode: .markup) == "@knuth84")
        #expect(BibliographyFile.citation("knuth84", mode: .code) == "cite(<knuth84>)")
    }

    @Test func editingABibBufferChangesTheCompiledBibliography() async throws {
        let (p, root) = try await TestEnv.project("demo", main: "ui-test.typ")
        let bib = try await p.open(RelPath("refs.bib")!)
        #expect(!bib.isTypst)
        let before = try await p.exportPDF()
        #expect(!TestEnv.pdfText(before).contains("ZEBRATITLE"))
        let ns = bib.storage.string as NSString
        replace(bib, ns.range(of: "The TeXbook"), with: "ZEBRATITLE ä")
        let pdf = try await p.exportPDF()
        #expect(TestEnv.pdfText(pdf).contains("ZEBRATITLE"))
        #expect(bib.isDirty)
        #expect(try !String(contentsOf: root.appending(path: "refs.bib"), encoding: .utf8).contains("ZEBRATITLE"))
        #expect(await p.engine.overlayText(bib.path) == bib.storage.string)
        let refs = await p.references()
        #expect(refs.first?.entries.first?.title == "ZEBRATITLE ä")      // the unsaved text, not disk
    }

    @Test func plainFilesAreNotHighlightedOrSpellChecked() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= x\n", "notes.txt": "#let x = *bold*\n"])
        let b = try await p.open(RelPath("notes.txt")!)
        var range = NSRange(location: 0, length: 0)
        let color = b.storage.attribute(.foregroundColor, at: 1, effectiveRange: &range) as? PlatformColor
        #expect(color == Highlighter.label)
        #expect(range.length == b.storage.length)
        #expect(b.proseRanges(in: NSRange(location: 0, length: b.storage.length)).isEmpty)
        #expect(b.mode(at: 3) == .text)
        let m = try await p.open(RelPath("main.typ")!)
        #expect(m.isTypst)
    }

    // MARK: Preview This Document

    @Test func settingMainSwitchesTheCompiledDocumentAndDiagnosticsFollow() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Main page\nMAINWORD\n", "other.typ": "= Other page\nOTHERWORD\n", "broken.typ": "#undefinedfunc()\n"])
        let m = try await p.open(RelPath("main.typ")!)
        let o = try await p.open(RelPath("other.typ")!)
        let br = try await p.open(RelPath("broken.typ")!)
        #expect(TestEnv.pdfText(try await p.exportPDF()).contains("MAINWORD"))
        #expect(p.diagnostics.isEmpty)

        p.setMain(RelPath("other.typ")!)
        let pdf = try await p.exportPDF()
        #expect(TestEnv.pdfText(pdf).contains("OTHERWORD") && !TestEnv.pdfText(pdf).contains("MAINWORD"))
        #expect(p.main.raw == "other.typ")
        #expect(p.outline.map(\.title) == ["Other page"])

        p.setMain(RelPath("broken.typ")!)
        _ = await p.settle()
        #expect(p.diagnostics.contains { if case .project(let l) = $0.origin { l.file.raw == "broken.typ" } else { false } })

        p.setMain(RelPath("main.typ")!)
        _ = await p.settle()
        #expect(p.diagnostics.isEmpty)
        for b in [m, o, br] { #expect(await p.engine.overlayText(b.path) == b.storage.string) }
    }

    // MARK: Search

    private static let searchFiles = ["main.typ": "Needle in main\nneedles plural\nthe needle\n", "notes.txt": "a NEEDLE here\nnone\n", "data.bin": "needle in a binary", "sub/x.csv": "needle,1\n"]

    @Test func plainSearchCaseSensitiveWholeWordAndRegex() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.searchFiles["main.typ"]!, "notes.txt": Self.searchFiles["notes.txt"]!, "data.bin": "needle in a binary"])
        let plain = try #require(await p.search("needle", options: SearchOptions()))
        #expect(plain.files.map(\.id.raw) == ["main.typ", "notes.txt"])          // data.bin is not a text file
        #expect(plain.matchCount == 4)                                           // Needle, needles, needle, NEEDLE
        let first = try #require(plain.files.first?.hits.first)
        #expect(first.line == 1 && first.range == NSRange(location: 0, length: 6))
        #expect((first.context as NSString).substring(with: first.contextMatch) == "Needle")

        let cs = try #require(await p.search("needle", options: SearchOptions(caseSensitive: true)))
        #expect(cs.matchCount == 2)
        let ww = try #require(await p.search("needle", options: SearchOptions(wholeWord: true)))
        #expect(ww.matchCount == 3)                                              // not "needles"
        let re = try #require(await p.search("ne+dles?\\b", options: SearchOptions(caseSensitive: true, regex: true)))
        #expect(re.files.map(\.id.raw) == ["main.typ"] && re.matchCount == 2)
        let bad = try #require(await p.search("(", options: SearchOptions(regex: true)))
        #expect(bad.error != nil && bad.files.isEmpty)
    }

    @Test func searchFindsNestedFilesAndUsesLineNumbers() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= x\n", "sub/x.csv": "a\nb\nneedle,1\n"])
        let r = try #require(await p.search("needle", options: SearchOptions()))
        #expect(r.files.map(\.id.raw) == ["sub/x.csv"])
        #expect(r.files[0].hits[0].line == 3)
    }

    @Test func openBufferTextBeatsDisk() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "disk-only-word\n", "other.typ": "= o\n"])
        let b = try await p.open(RelPath("main.typ")!)
        replace(b, NSRange(location: 0, length: b.storage.length), with: "memory-only-word ä😀 tail\n")
        let mem = try #require(await p.search("memory-only-word", options: SearchOptions()))
        #expect(mem.matchCount == 1)
        let hit = try #require(mem.files.first?.hits.first)
        #expect((b.storage.string as NSString).substring(with: hit.range) == "memory-only-word")
        let disk = try #require(await p.search("disk-only-word", options: SearchOptions()))
        #expect(disk.matchCount == 0)
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "disk-only-word\n")
    }

    @Test func replaceAllOpensOnlyMatchingFilesAndUndoesPerFile() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "Needle and needles\n", "notes.txt": "a NEEDLE\n", "other.typ": "none\n"])
        let n = try await p.replace("needle", options: SearchOptions(wholeWord: true), with: "pin")
        #expect(n == 2)
        let main = try await p.open(RelPath("main.typ")!)
        #expect(main.storage.string == "pin and needles\n")
        #expect(try await p.open(RelPath("notes.txt")!).storage.string == "a pin\n")
        #expect(p.buffers[RelPath("other.typ")!] == nil)                         // no match: never opened
        main.undoManager.undo()
        #expect(main.storage.string == "Needle and needles\n")
    }

    @Test func replaceSelectedHitsUsesRegexTemplatesAndSkipsStaleHits() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "a1 a2 a3\n"])
        let r = try #require(await p.search("a(\\d)", options: SearchOptions(regex: true)))
        let hits = r.files[0].hits
        #expect(hits[0].replacement(query: "a(\\d)", options: SearchOptions(regex: true), template: "b$1") == "b1")
        let b = try await p.open(RelPath("main.typ")!)
        replace(b, NSRange(location: 0, length: 0), with: "x")                   // shifts every hit: all stale now
        #expect(try await p.replace("a(\\d)", options: SearchOptions(regex: true), with: "b$1", only: [hits[1]]) == 0)
        replace(b, NSRange(location: 0, length: 1), with: "")
        #expect(try await p.replace("a(\\d)", options: SearchOptions(regex: true), with: "b$1", only: [hits[0], hits[2]]) == 2)
        #expect(b.storage.string == "b1 a2 b3\n")
    }

    @Test func aNewerSearchCancelsTheOlder() async throws {
        var files = ["main.typ": "= x\n"]
        for i in 0..<300 { files["f\(i).txt"] = String(repeating: "lorem ipsum needle\n", count: 200) }
        let (p, _) = try await TestEnv.project(files: files)
        let older = Task { await p.search("lorem", options: SearchOptions()) }
        await Task.yield()
        let newer = await p.search("needle", options: SearchOptions())
        #expect(newer != nil)
        #expect(await older.value == nil)
    }

    @Test func revealingAHitSelectsItsRange() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= x\n", "notes.txt": "abc needle def\n"])
        let r = try #require(await p.search("needle", options: SearchOptions()))
        p.reveal(try #require(r.files.first?.hits.first))
        for _ in 0..<200 where p.selectionRequests == 0 { try await Task.sleep(for: .milliseconds(10)) }
        let b = try #require(p.selectedBuffer)
        #expect(b.path.raw == "notes.txt")
        #expect(b.takePendingSelection() == NSRange(location: 4, length: 6))
        #expect(b.takePendingFlash())
    }

    // MARK: File kinds

    @Test func fileKindMapping() {
        func k(_ s: String, dir: Bool = false) -> FileKind { FileKind(path: s, isDirectory: dir) }
        #expect(k("a", dir: true) == .folder)
        #expect(k("sub/main.typ") == .typst)
        #expect(k("x.PDF") == .pdf)
        #expect(k("a/logo.png") == .image && k("a.svg") == .image)
        #expect(k("refs.bib") == .bib)
        #expect(k("typst.toml") == .package && k("sub/typst.toml") == .package)
        #expect(k("other.toml") == .data && k("d.csv") == .data && k("d.yml") == .data && k("d.json") == .data && k("d.xml") == .data)
        #expect(k("f.otf") == .font && k("f.ttf") == .font)
        #expect(k("README") == .other && k("a.zip") == .other)
        #expect(FileKind.typst.symbol == nil)
        #expect(FileKind.bib.symbol == "book.closed.fill" && FileKind.package.symbol == "shippingbox.fill" && FileKind.font.symbol == "textformat")
        #expect(FileKind.pdf.isPreviewOnly && FileKind.image.isPreviewOnly && !FileKind.bib.isPreviewOnly)
        for t in ["a.typ", "a.bib", "a.toml", "a.csv", "a.json", "a.yaml", "a.yml", "a.txt", "a.md", "a.xml"] { #expect(FileKind.isText(t)) }
        for t in ["a.pdf", "a.png", "a.svg", "a.ttf", "a"] { #expect(!FileKind.isText(t)) }
    }

    @Test func allFilesListsEveryFileSkippingHidden() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= x\n", "sub/b.bib": "", ".hidden/x.typ": "", ".secret": ""])
        #expect(Set(p.allFiles.map(\.raw)) == ["main.typ", "sub/b.bib"])
    }
}
