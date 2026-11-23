import CoreGraphics
import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite(.serialized) @MainActor struct WorkspaceUITests {
    // MARK: Formatting

    /// Applies `c` to `text` with `selection` and returns the new text and selection.
    private func apply(_ c: Formatting.Command, _ text: String, _ selection: NSRange) throws -> (text: String, selection: NSRange) {
        let e = try #require(Formatting.edit(c, in: text, selection: selection, syntax: SyntaxMirror(text)))
        return ((text as NSString).replacingCharacters(in: e.range, with: e.replacement), e.selection)
    }

    /// The published word count after the background count of the latest compile has finished.
    private func words(_ p: Project) async -> Int {
        _ = await p.settle()
        await p.wordsTask?.value
        return p.wordCount
    }

    private func r(_ l: Int, _ n: Int = 0) -> NSRange { NSRange(location: l, length: n) }

    /// No errors. An empty `**` or `__` pair is a warning ("no text within stars"): it compiles, and the caret sits inside it.
    private func compilesClean(_ text: String) async throws -> Bool {
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        _ = await p.settle()
        return !p.diagnostics.contains { $0.severity == .error }
    }

    @Test func wrapSelectionAndEmptyPair() throws {
        var x = try apply(.bold, "hello world", r(6, 5))
        #expect(x.text == "hello *world*" && x.selection == r(7, 5))
        x = try apply(.italic, "hello world", r(0, 5))
        #expect(x.text == "_hello_ world" && x.selection == r(1, 5))
        x = try apply(.underline, "hello world", r(6, 5))
        #expect(x.text == "hello #underline[world]" && x.selection == r(17, 5))
        x = try apply(.bold, "hello", r(5))
        #expect(x.text == "hello**" && x.selection == r(6))
        x = try apply(.italic, "", r(0))
        #expect(x.text == "__" && x.selection == r(1))
        x = try apply(.underline, "ab", r(1))
        #expect(x.text == "a#underline[]b" && x.selection == r(12))
        x = try apply(.bold, " word ", r(0, 6))                 // delimiters hug the text
        #expect(x.text == " *word* " && x.selection == r(2, 4))
        x = try apply(.bold, "a  b", r(1, 2))                   // only blanks selected: an empty pair, nothing deleted
        #expect(x.text == "a**  b" && x.selection == r(2))
    }

    @Test func wrapFollowsTheSyntaxMode() async throws {
        // Math: `$x y$` selecting y; empty pair at the caret.
        var x = try apply(.bold, "$x y$", r(3, 1))
        #expect(x.text == "$x bold(y)$" && x.selection == r(8, 1))
        x = try apply(.italic, "$x y$", r(3, 1))
        #expect(x.text == "$x italic(y)$")
        x = try apply(.underline, "$x y$", r(3, 1))
        #expect(x.text == "$x underline(y)$")
        x = try apply(.bold, "$ $", r(2))
        #expect(x.text == "$ bold()$" && x.selection == r(7))
        // Code: inside a call's content argument position and after `#let x = `.
        x = try apply(.bold, "#let x = a", r(9, 1))
        #expect(x.text == "#let x = strong[a]" && x.selection == r(16, 1))
        x = try apply(.italic, "#let x = a", r(9, 1))
        #expect(x.text == "#let x = emph[a]")
        x = try apply(.underline, "#let x = a", r(9, 1))
        #expect(x.text == "#let x = underline[a]")
        x = try apply(.bold, "#let x = ", r(9))
        #expect(x.text == "#let x = strong[]" && x.selection == r(16))
        // Markup inside a content block stays markup; math inside strong still gets the math form.
        x = try apply(.bold, "#[word]", r(2, 4))
        #expect(x.text == "#[*word*]")
        x = try apply(.bold, "*a $b$ c*", r(4, 1))
        #expect(x.text == "*a $bold(b)$ c*")
        // Every mode compiles without errors.
        for src in ["$x y$", "#let x = a\n#x", "#[word]", "word"] {
            let c = src.contains("$") ? 3 : src.hasPrefix("#let") ? 9 : src.hasPrefix("#[") ? 2 : 0
            for cmd in [Formatting.Command.bold, .italic, .underline] {
                let out = try apply(cmd, src, r(c, src.contains("word") ? 4 : 1)).text   // whole word: `*w*ord` is an error
                #expect(try await compilesClean(out), "\(cmd) in \(src) gave \(out)")
            }
        }
    }

    @Test func unwrapWhenInside() throws {
        var x = try apply(.bold, "a *bold* b", r(4, 2))
        #expect(x.text == "a bold b" && x.selection == r(3, 2))
        x = try apply(.bold, "a *bold* b", r(5))                // caret inside
        #expect(x.text == "a bold b" && x.selection == r(4))
        x = try apply(.bold, "a *bold* b", r(2, 6))             // the whole node selected
        #expect(x.text == "a bold b" && x.selection == r(2, 4))
        x = try apply(.italic, "x _it_ y", r(3, 2))
        #expect(x.text == "x it y")
        x = try apply(.underline, "x #underline[word] y", r(13, 4))
        #expect(x.text == "x word y" && x.selection == r(2, 4))
        x = try apply(.underline, "x #underline[word] y", r(13))   // caret right after the bracket
        #expect(x.text == "x word y" && x.selection == r(2))
        // Outside the markup (caret just after the closing delimiter) it inserts a pair instead of unwrapping.
        x = try apply(.bold, "*a* b", r(3))
        #expect(x.text == "*a*** b")
    }

    @Test func nestedMarkup() throws {
        var x = try apply(.italic, "*a _b_ c*", r(4, 1))          // innermost matching kind unwraps
        #expect(x.text == "*a b c*" && x.selection == r(3, 1))
        x = try apply(.bold, "*a _b_ c*", r(4, 1))
        #expect(x.text == "a _b_ c" && x.selection == r(3, 1))
        x = try apply(.italic, "*a b c*", r(3, 1))               // wrapping inside another kind
        #expect(x.text == "*a _b_ c*" && x.selection == r(4, 1))
        x = try apply(.underline, "*a b*", r(1, 3))
        #expect(x.text == "*#underline[a b]*")
        let twice = try apply(.bold, x.text, x.selection)        // bold again unwraps the outer node
        #expect(twice.text == "#underline[a b]")
        for c in [Formatting.Command.bold, .italic, .underline] {   // toggling twice restores the text
            let on = try apply(c, "one two", r(4, 3))
            #expect(try apply(c, on.text, on.selection).text == "one two")
        }
    }

    @Test func listsToggleAndConvert() throws {
        var x = try apply(.bulletList, "one\ntwo\nthree", r(0, 13))
        #expect(x.text == "- one\n- two\n- three" && x.selection == r(2, 17))
        x = try apply(.bulletList, x.text, x.selection)            // all bullets: removed again
        #expect(x.text == "one\ntwo\nthree")
        x = try apply(.numberedList, "- a\n- b\n", r(0, 8))        // convert, keep the trailing newline
        #expect(x.text == "+ a\n+ b\n")
        x = try apply(.bulletList, "- a\nb\n+ c", r(0, 9))         // mixed: every line becomes a bullet
        #expect(x.text == "- a\n- b\n- c")
        x = try apply(.bulletList, "a\n\nb", r(0, 4))              // blank lines are left alone
        #expect(x.text == "- a\n\n- b")
        x = try apply(.bulletList, "a\nb\nc", r(0, 4))             // ends at the start of line c: c is not included
        #expect(x.text == "- a\n- b\nc")
        x = try apply(.bulletList, "  x", r(2))                    // indentation stays before the marker
        #expect(x.text == "  - x" && x.selection == r(4))
        x = try apply(.numberedList, "one\ntwo", r(5))             // a caret stays on its character
        #expect(x.text == "one\n+ two" && x.selection == r(7))
        x = try apply(.bulletList, "", r(0))
        #expect(x.text == "- " && x.selection == r(2))
        x = try apply(.bulletList, "- x", r(3))
        #expect(x.text == "x" && x.selection == r(1))
    }

    @Test func mathInlineAndOnAnEmptyLine() throws {
        var x = try apply(.math, "let x^2 here", r(4, 3))
        #expect(x.text == "let $x^2$ here" && x.selection == r(5, 3))
        x = try apply(.math, "a b", r(1))
        #expect(x.text == "a$$ b" && x.selection == r(2))
        x = try apply(.math, "a\n\nb", r(2))
        #expect(x.text == "a\n$  $\nb" && x.selection == r(4))
    }

    @Test func everyFormattedResultCompiles() async throws {
        let cases: [(Formatting.Command, String, NSRange)] = [
            (.bold, "hello world", r(6, 5)), (.bold, "hello ", r(6)), (.bold, "*a _b_ c*", r(4, 1)),
            (.italic, "hello world", r(0, 5)), (.italic, "*a b c*", r(3, 1)),
            (.underline, "hello world", r(6, 5)), (.underline, "x #underline[w] y", r(13, 1)), (.underline, "", r(0)),
            (.bulletList, "one\ntwo", r(0, 7)), (.numberedList, "- a\n- b", r(0, 7)), (.bulletList, "", r(0)),
            (.math, "x^2", r(0, 3)), (.math, "", r(0)), (.math, "a b", r(1)),
        ]
        for (c, text, sel) in cases {
            let out = try apply(c, text, sel).text
            #expect(try await compilesClean(out), "\(c) on \(text.debugDescription) gave \(out.debugDescription)")
        }
    }

    @Test func bufferFormatsOnlyTypstFiles() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "word", "notes.txt": "word"])
        let m = try await p.open(RelPath("main.typ")!)
        let n = try await p.open(RelPath("notes.txt")!)
        #expect(m.formatEdit(.bold, selection: r(0, 4))?.replacement == "*word*")
        #expect(n.formatEdit(.bold, selection: r(0, 4)) == nil)
    }

    // MARK: Word count

    @Test func wordCountCountsOnlyWhatTheAuthorWrote() async throws {
        let text = "#set page(numbering: \"1\")\n#set heading(numbering: \"1.\")\n= Heading here <h>\nOne two three four five, see @h and @f.\n#figure([x], caption: [A caption]) <f>\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        _ = await p.settle()
        // 2 heading + 7 body + 1 figure body + 2 caption; no numbering, page number, "Figure 1" or "Section 1"
        #expect(await words(p) == 12)
        let b = try await p.open(RelPath("main.typ")!)
        type(b, "#pagebreak()\nSix seven\n")
        _ = await p.settle()
        #expect(await words(p) == 14)
    }

    @Test func wordCountFollowsEditsAndKeepsTheLastGoodDocument() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "alpha beta"])
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        #expect(await words(p) == 2)
        type(b, " gamma")
        _ = await p.settle()
        #expect(await words(p) == 3)
        type(b, " #nope()")
        _ = await p.settle()
        #expect(await words(p) == 3)                                  // a failed compile leaves the preview's document
    }

    @Test func selectionCountUsesProseOnly() async throws {
        let text = "A *bold* word and #lorem(5) code $x y z$ `raw words`.\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let all = NSRange(location: 0, length: b.storage.length)
        #expect(b.selectedWordCount(all) == 5)                     // A, bold, word, and, code
        #expect(b.selectedWordCount(NSRange(location: 0, length: 0)) == 0)
        let ns = text as NSString
        #expect(b.selectedWordCount(NSRange(location: 0, length: ns.range(of: "word").upperBound)) == 3)   // A *bold* word
        #expect(b.selectedWordCount(ns.range(of: "$x y z$")) == 0)
        #expect(b.selectedWordCount(ns.range(of: "`raw words`")) == 0)
    }

    @Test func wordCountLabelIsLocaleFormatted() {
        let en = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        #expect(WordCount.label(total: 4075, locale: en) == "4,075 words")
        #expect(WordCount.label(total: 4075, selected: 12, locale: en) == "12 of 4,075 words")
        #expect(WordCount.label(total: 4075, locale: de) == "4.075 words")
        #expect(WordCount.label(total: 1, locale: en) == "1 word")
        #expect(WordCount.label(total: 0, locale: en) == "0 words")
        #expect(WordCount.label(total: 1234, goal: 20000, locale: en) == "1,234 / 20,000 words")
        #expect(WordCount.label(total: 1234, selected: 12, goal: 20000, locale: en) == "12 of 1,234 words")
    }

    @Test func wordCountTiming() async throws {
        let (p, _) = try await TestEnv.project("sample-long")
        let b = try await p.open(RelPath("main.typ")!)
        _ = await p.settle()
        var counts: [Double] = [], compiles: [Double] = []
        var words = 0
        for _ in 0..<7 {
            type(b, " ", at: 0)                                    // a real edit, so the engine recompiles
            var t = ContinuousClock.now
            let r = try #require(await p.engine.flush())
            compiles.append(JumpTests.ms(ContinuousClock.now - t))
            t = ContinuousClock.now
            words = await r.snapshot.words()
            counts.append(JumpTests.ms(ContinuousClock.now - t))
        }
        #expect(words > 10_000 && p.preview.pages.count > 100)
        #if DEBUG
        let profile = "debug"
        #else
        let profile = "release"
        #endif
        print("WORD COUNT TIMING [\(profile)] \(p.preview.pages.count) pages, \(words) words: compile without counting median \(String(format: "%.0f", compiles.sorted()[3])) ms; separate count median \(String(format: "%.2f", counts.sorted()[3])) ms")
    }

    // MARK: Lock and previewed document

    @Test func lockedSelectionNeverChangesTheDocumentUnlockedDoes() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= Main\nMAINWORD\n", "other.typ": "= Other\nOTHERWORD\n", "notes.txt": "plain"])
        let other = RelPath("other.typ")!
        #expect(p.previewLocked)
        p.select(other)
        #expect(p.selectedFile == other && p.main.raw == "main.typ")
        p.previewLocked = false
        p.select(RelPath("notes.txt")!)                            // not a Typst file
        #expect(p.main.raw == "main.typ")
        p.select(other)
        #expect(p.main == other)
        let pdf = try await p.exportPDF()
        #expect(TestEnv.pdfText(pdf).contains("OTHERWORD") && !TestEnv.pdfText(pdf).contains("MAINWORD"))
    }

    @Test func switchingTheDocumentKeepsEveryOverlayExactAndUnsavedEditsReachTheCompile() async throws {
        let files = ["main.typ": "= Main\nMAINWORD\n", "top.typ": "#include \"part.typ\"\nTOPWORD\n", "part.typ": "PARTWORD\n"]
        let (p, _) = try await TestEnv.project(files: files)
        let m = try await p.open(RelPath("main.typ")!)
        let t = try await p.open(RelPath("top.typ")!)
        let part = try await p.open(RelPath("part.typ")!)
        type(part, "UNSAVED ", at: 0)                              // never saved
        type(m, "é😀 ", at: 0)
        p.previewLocked = false
        p.select(t.path)
        let pdf = try await p.exportPDF()
        #expect(TestEnv.pdfText(pdf).contains("UNSAVED PARTWORD TOPWORD"))
        type(part, "MORE ", at: 0)                                 // an edit after the switch reaches the new document too
        #expect(TestEnv.pdfText(try await p.exportPDF()).contains("MORE UNSAVED PARTWORD"))
        p.select(m.path)
        p.select(part.path)
        _ = await p.settle()
        for b in [m, t, part] { #expect(await p.engine.overlayText(b.path) == b.storage.string) }
        #expect(p.main == part.path)
    }

    @Test func outlineDiagnosticsWordCountAndCursorSyncFollowTheNewDocument() async throws {
        let files = ["main.typ": "= Main page\nMAINWORD\n", "other.typ": "= Other page\nOTHERWORD one two\n", "bad.typ": "#nope()\n"]
        let (p, _) = try await TestEnv.project(files: files)
        let other = RelPath("other.typ")!, bad = RelPath("bad.typ")!
        let m = try await p.open(RelPath("main.typ")!)
        let o = try await p.open(other)
        let b = try await p.open(bad)
        _ = await p.settle()
        let w0 = await words(p)
        #expect(w0 == 3 && p.outline.map(\.title) == ["Main page"] && p.diagnostics.isEmpty)

        p.selectedFile = other                                     // the caret is in a file the shown document does not contain
        p.cursorMoved(in: other, to: 14)
        try await Task.sleep(for: .milliseconds(200))
        let before = p.preview.targetSerial
        p.setMain(other)
        _ = await p.settle()
        #expect(await words(p) == 5)                                  // Other page OTHERWORD one two
        #expect(p.outline.map(\.title) == ["Other page"])
        for _ in 0..<400 where p.preview.targetSerial == before { try await Task.sleep(for: .milliseconds(10)) }
        #expect(p.preview.targetSerial != before && p.preview.target?.page == 0)   // re-synced without a caret move

        p.setMain(bad)
        _ = await p.settle()
        #expect(p.diagnostics.contains { if case .project(let l) = $0.origin { l.file == bad } else { false } })
        p.setMain(RelPath("main.typ")!)
        _ = await p.settle()
        let w = await words(p)
        #expect(p.diagnostics.isEmpty && w == 3)
        for buf in [m, o, b] { #expect(await p.engine.overlayText(buf.path) == buf.storage.string) }
    }

    @Test func lockStateAndPinnedDocumentPersistInRecents() throws {
        let suite = "typstcore-recents-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appending(path: "typstcore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let recents = RecentProjects(defaults: defaults)
        let id = try recents.register(root: root, main: RelPath("main.typ")!)
        #expect(recents.isLocked(id))                              // the default
        recents.setLocked(false, for: id)
        recents.setMain(RelPath("chapters/two.typ")!, for: id)
        let reloaded = RecentProjects(defaults: defaults)
        #expect(!reloaded.isLocked(id) && reloaded.record(id)?.main.raw == "chapters/two.typ")
        reloaded.setLocked(true, for: id)
        #expect(RecentProjects(defaults: defaults).isLocked(id))
    }

    @Test func recordsFromBeforeTheLockExistedDecodeAsLocked() throws {
        let old = #"[{"id":{"uuid":"\#(UUID().uuidString)"},"bookmark":"AAAA","rootPath":"/tmp/x","main":{"raw":"main.typ"},"name":"x","lastOpened":0}]"#
        let suite = "typstcore-recents-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(old.utf8), forKey: "TypstCore.recentProjects")
        let recents = RecentProjects(defaults: defaults)
        #expect(recents.records.count == 1 && recents.isLocked(recents.records[0].id))
    }

    @Test func projectOpenRestoresTheLockFromRecents() async throws {
        let suite = "typstcore-recents-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let (_, root) = try await TestEnv.project(files: ["main.typ": "x"])
        let recents = RecentProjects(defaults: defaults)
        let id = try recents.register(root: root, main: RelPath("main.typ")!)
        let a = try await Project.open(id, recents: recents)
        #expect(a.previewLocked)
        a.previewLocked = false
        #expect(!recents.isLocked(id))
        let b = try await Project.open(id, recents: recents)
        #expect(!b.previewLocked)
    }

    // MARK: Zoom and paging arithmetic

    @Test func zoomPercentIsRelativeToTheNaturalPageSize() {
        // A4 page 595 pt in a column that fits 800 pt: zoom 1 (fit width) shows 134 %.
        #expect(PreviewMath.percent(zoom: 1, fitWidth: 800, pageWidth: 595) == 134)
        #expect(PreviewMath.percent(zoom: 0.5, fitWidth: 595, pageWidth: 595) == 50)
        #expect(abs(PreviewMath.zoom(percent: 100, fitWidth: 800, pageWidth: 595) - 595.0 / 800) < 1e-9)
        for pct in PreviewMath.presets {
            let z = PreviewMath.zoom(percent: pct, fitWidth: 700, pageWidth: 595)
            #expect(PreviewMath.percent(zoom: z, fitWidth: 700, pageWidth: 595) == pct)
        }
        #expect(PreviewMath.zoom(percent: 10_000, fitWidth: 100, pageWidth: 595) == 4)       // clamped
        #expect(PreviewMath.zoom(percent: 1, fitWidth: 800, pageWidth: 100) == 0.25)
        #expect(PreviewMath.percent(zoom: 1, fitWidth: 0, pageWidth: 595) == 0)
        #expect(PreviewMath.percent(zoom: 1, fitWidth: 800, pageWidth: 0) == 100)
        #expect(PreviewMath.zoom(percent: 100, fitWidth: 0, pageWidth: 595) == 1)
    }

    @Test func pageFramesAndTheMostVisiblePage() {
        let sizes = [CGSize(width: 100, height: 200), CGSize(width: 100, height: 200), CGSize(width: 100, height: 100)]
        let frames = PreviewMath.frames(sizes: sizes, width: 50, inset: 10)
        #expect(frames == [CGRect(x: 10, y: 10, width: 50, height: 100), CGRect(x: 10, y: 120, width: 50, height: 100),
                           CGRect(x: 10, y: 230, width: 50, height: 50)])
        func page(_ y: CGFloat, _ h: CGFloat) -> Int? { PreviewMath.mostVisiblePage(frames: frames, visible: CGRect(x: 0, y: y, width: 70, height: h)) }
        #expect(page(0, 100) == 0)
        #expect(page(70, 100) == 1)            // 50 pt of page 2 beats 40 pt of page 1
        #expect(page(60, 70) == 0)             // 50 vs 20 pt: the first
        #expect(page(100, 200) == 1)           // page 2 is visible for 100 pt, page 3 for 50
        #expect(page(250, 100) == 2)
        #expect(page(1000, 100) == nil)
        #expect(PreviewMath.mostVisiblePage(frames: [], visible: CGRect(x: 0, y: 0, width: 10, height: 10)) == nil)
    }
}
