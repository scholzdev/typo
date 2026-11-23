import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine
#if canImport(AppKit)
import AppKit
#endif

@Suite(.serialized) @MainActor struct FoldingTests {
    static let text = "= A\nintro\n== A1\na1 text\n== A2\na2\n= B\nb\n"
    private func at(_ s: String, in text: String = Self.text) -> Int { (text as NSString).range(of: s).location }

    private func regions(_ text: String) -> [FoldRegion] {
        let ns = text as NSString
        let heads = Folding.candidates(ns).map { (line: ns.lineRange(for: NSRange(location: $0.marker, length: 0)).location, level: $0.level) }
        return Folding.regions(heads, in: ns)
    }

    @Test func sectionsEndBeforeTheNextHeadingOfTheSameOrHigherLevel() {
        let r = regions(Self.text)
        let ns = Self.text as NSString
        #expect(r.map(\.heading) == [0, at("== A1"), at("== A2"), at("= B")])
        #expect(r.map(\.level) == [1, 2, 2, 1])
        #expect(r.map { ns.substring(with: $0.hidden) } == ["intro\n== A1\na1 text\n== A2\na2\n", "a1 text\n", "a2\n", "b\n"])
        #expect(r.map(\.lines) == [5, 1, 1, 1])
        // A heading right before the next one has nothing to fold; a last line without a break still counts.
        #expect(regions("= A\n= B\nx").map(\.heading) == [4])
        #expect(regions("= A\n= B\nx").first?.lines == 1)
    }

    @Test func capsulesNestByDepthAndTheInnermostRegionHoldsAnOffset() {
        let r = regions(Self.text)
        let all = Folding.capsules(r, in: 0..<(Self.text as NSString).length)
        #expect(all.map(\.depth) == [0, 0, 1, 1])
        #expect(all.map(\.region.heading) == [0, at("= B"), at("== A1"), at("== A2")])
        #expect(Folding.capsules(r, in: at("= B")..<(Self.text as NSString).length).map(\.region.heading) == [at("= B")])
        #expect(Folding.innermost(r, at: at("a1 text"))?.heading == at("== A1"))
        #expect(Folding.innermost(r, at: at("intro"))?.heading == 0)
        #expect(Folding.innermost(r, at: (Self.text as NSString).length) == nil)
    }

    @Test func onlyRealHeadingsFold() async throws {
        let text = "= Real\nx\n```\n= raw\n```\n- = in a list\n#[= in content]\n  = Indented\ny\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text, "notes.txt": "= not typst\nx\n"])
        let b = try await p.open(RelPath("main.typ")!)
        #expect(b.foldRegions.map(\.heading) == [0, at("```", in: text), at("  = Indented", in: text)])   // the fence folds, its `= raw` is no heading
        #expect(try await p.open(RelPath("notes.txt")!).foldRegions.isEmpty)
    }

    @Test func nestedFoldsMergeUnderTheOuterHeading() {
        let r = regions(Self.text)
        let h = Folding.hidden([r[1], r[0]])
        #expect(h == [HiddenRange(range: r[0].hidden, heading: 0)])
        #expect(Folding.hidden([r[1], r[2]]).count == 2)
    }

    @Test func editsTouchingAFold() {
        let h = NSRange(location: 10, length: 20)             // heading line break at 9, next heading at 30
        #expect(Folding.touches(NSRange(location: 9, length: 0), h, length: 50))      // typing at the heading line's end
        #expect(!Folding.touches(NSRange(location: 8, length: 0), h, length: 50))     // inside the title
        #expect(!Folding.touches(NSRange(location: 7, length: 1), h, length: 50))     // deleting the title's last character
        #expect(Folding.touches(NSRange(location: 9, length: 1), h, length: 50))      // deleting the line break
        #expect(Folding.touches(NSRange(location: 15, length: 2), h, length: 50))     // hidden text
        #expect(Folding.touches(NSRange(location: 25, length: 10), h, length: 50))    // into the next section
        #expect(!Folding.touches(NSRange(location: 30, length: 0), h, length: 50))    // at the next heading
        #expect(Folding.touches(NSRange(location: 30, length: 0), h, length: 30))     // appending to a folded last section
    }

    @Test func selectionsAgainstFolds() {
        let hidden = [HiddenRange(range: NSRange(location: 10, length: 20), heading: 4)]
        let caret = { NSRange(location: $0, length: 0) }
        // The keyboard steps over a fold.
        #expect(Folding.resolve(caret(10), from: caret(9), keyboard: true, hidden: hidden, length: 50) == (caret(30), []))
        #expect(Folding.resolve(caret(29), from: caret(30), keyboard: true, hidden: hidden, length: 50) == (caret(9), []))
        #expect(Folding.resolve(caret(30), from: caret(9), keyboard: true, hidden: hidden, length: 30) == (caret(9), []))
        // A find match or a jump opens it.
        #expect(Folding.resolve(NSRange(location: 12, length: 3), from: caret(0), keyboard: true, hidden: hidden, length: 50).reveal == [12, 15])
        #expect(Folding.resolve(caret(20), from: caret(0), keyboard: false, hidden: hidden, length: 50).reveal == [20])
        #expect(Folding.resolve(NSRange(location: 2, length: 10), from: caret(0), keyboard: false, hidden: hidden, length: 50).reveal == [12])
        // A selection around the whole fold, or one ending where it starts, leaves it closed.
        #expect(Folding.resolve(NSRange(location: 0, length: 35), from: caret(0), keyboard: false, hidden: hidden, length: 50).reveal.isEmpty)
        #expect(Folding.resolve(NSRange(location: 4, length: 6), from: caret(0), keyboard: false, hidden: hidden, length: 50).reveal.isEmpty)
    }

    @Test func foldsFollowEditsAndOpenWhenTouched() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        let a1 = at("== A1")
        b.fold([a1])
        #expect(b.isFolded(a1))
        #expect(b.hiddenRanges.map { (b.storage.string as NSString).substring(with: $0.range) } == ["a1 text\n"])
        let rev = b.foldRevision

        replace(b, NSRange(location: 0, length: 0), with: "x\n")    // before: the fold moves along, still closed
        #expect(b.isFolded(a1 + 2))
        #expect(b.hiddenRanges.map { (b.storage.string as NSString).substring(with: $0.range) } == ["a1 text\n"])
        #expect(b.foldRevision == rev)

        let lineEnd = b.hiddenRanges[0].range.location - 1
        replace(b, NSRange(location: lineEnd, length: 0), with: "!")    // typing at the heading line's end
        #expect(b.folding.folded.isEmpty)
        #expect(b.hiddenRanges.isEmpty)
        #expect(b.foldRevision > rev)

        b.fold([b.foldRegion(at: at("== A2", in: b.storage.string), folded: false)!.heading])
        try await p.edit(b.path, [Replacement(range: NSRange(location: at("a2", in: b.storage.string), length: 1), text: "Z")])
        #expect(b.hiddenRanges.isEmpty)                            // another feature's edit of hidden text opens it too

        b.foldAll()
        #expect(b.hiddenRanges.count == 2)                         // = A swallows its subsections, = B
        let bHeading = at("= B", in: b.storage.string)
        replace(b, NSRange(location: bHeading, length: 1), with: "x")   // the heading is no heading any more
        #expect(!b.isFolded(bHeading))
        #expect(b.hiddenRanges.count == 1)
        b.unfoldAll()
        #expect(b.hiddenRanges.isEmpty)
    }

    @Test func revealOpensEveryFoldAroundAPosition() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        b.foldAll()
        b.reveal([at("a1 text")])
        #expect(!b.isFolded(0) && !b.isFolded(at("== A1")))
        #expect(b.isFolded(at("== A2")) && b.isFolded(at("= B")))
        #expect(b.visibleLine(of: at("a2")) == at("== A2"))       // a diagnostic there shows on the heading line
        #expect(b.visibleLine(of: at("a1 text") + 3) == at("a1 text"))
    }

    #if canImport(AppKit)
    /// The app's editor setup: a TextKit 2 view whose content storage asks a FoldController.
    private func view(_ b: Buffer, _ folds: FoldController) -> NSTextView {
        let tv = NSTextView(usingTextLayoutManager: true)
        tv.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContentStorage!.delegate = folds
        folds.textLayoutManager = tv.textLayoutManager
        folds.buffer = b
        tv.textContentStorage!.adopt(b.storage)
        return tv
    }

    /// Line numbers as the ruler computes them: newlines counted up to each laid-out paragraph.
    private func shownLines(_ tv: NSTextView) -> [Int] {
        let tlm = tv.textLayoutManager!, tcs = tv.textContentStorage!
        let text = tv.string as NSString
        var out: [Int] = []
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { f in
            let start = tcs.offset(from: tcs.documentRange.location, to: f.rangeInElement.location)
            out.append(1 + (0..<start).filter { text.character(at: $0) == 10 }.count)
            return true
        }
        return out
    }

    @Test func theViewHidesFoldedLinesAndNumbersSkipThem() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        let folds = FoldController()
        let tv = view(b, folds)
        #expect(shownLines(tv) == [1, 2, 3, 4, 5, 6, 7, 8])
        var changes = 0
        folds.onChange = { changes += 1 }

        b.fold([at("== A1")])
        folds.update()
        #expect(shownLines(tv) == [1, 2, 3, 5, 6, 7, 8])
        b.fold([0])
        folds.update()
        #expect(shownLines(tv) == [1, 7, 8])
        #expect(changes == 2)

        // The keyboard moving right off a heading line lands in hidden text; the editor steps over the fold.
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.moveRight(nil)
        let landed = tv.selectedRange()
        #expect(b.hidden(at: landed.location) != nil)
        let resolved = Folding.resolve(landed, from: NSRange(location: 3, length: 0), keyboard: true, hidden: b.hiddenRanges, length: b.storage.length)
        #expect(resolved.selection.location == at("= B"))
        tv.setSelectedRange(NSRange(location: 1, length: 0))
        tv.moveDown(nil)
        #expect(b.hidden(at: tv.selectedRange().location) == nil)

        // Typing at the end of the heading line opens the fold; the layout follows once the edit is processed.
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.insertText("!", replacementRange: tv.selectedRange())
        for _ in 0..<20 where shownLines(tv).count < 8 { await Task.yield() }
        #expect(shownLines(tv) == [1, 2, 3, 5, 6, 7, 8])         // = A opened; == A1 inside it stays folded
        #expect(b.isFolded(at("== A1", in: b.storage.string)))

        b.unfoldAll()
        folds.update()
        #expect(shownLines(tv) == [1, 2, 3, 4, 5, 6, 7, 8])

        // A file switch: another buffer's folds apply; coming back finds this one's folds again.
        b.fold([at("= B", in: b.storage.string)])
        let o = NSTextStorage(string: "x\n")
        folds.buffer = nil
        tv.textContentStorage!.adopt(o)
        #expect(shownLines(tv) == [1])
        folds.buffer = b
        tv.textContentStorage!.adopt(b.storage)
        folds.update()
        #expect(shownLines(tv) == [1, 2, 3, 4, 5, 6, 7])
    }

    /// The fold animation's sequence: the placeholder under the heading takes the hidden lines' place, so the text after
    /// the region does not jump when they hide (fold) or appear (unfold), and it follows the placeholder's height.
    @Test func thePlaceholderStandsInForTheFoldingLines() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        let folds = FoldController()
        let tv = view(b, folds)
        let tlm = tv.textLayoutManager!, tcs = tv.textContentStorage!
        func top(_ s: String) -> CGFloat {
            tlm.ensureLayout(for: tlm.documentRange)
            return tlm.textLayoutFragment(for: tcs.location(tcs.documentRange.location, offsetBy: at(s))!)!.layoutFragmentFrame.minY
        }
        let a1 = at("== A1"), region = NSRange(location: a1, length: at("== A2") - a1)
        let open = top("== A2"), block = open - top("a1 text")
        #expect(block > 0)

        #expect(folds.setPad(a1, block))
        b.fold([a1])
        folds.update(region)
        #expect(shownLines(tv) == [1, 2, 3, 5, 6, 7, 8])
        #expect(top("== A2") == open)                         // hidden, and nothing moved
        folds.setPad(a1, block / 2)
        #expect(top("== A2") == open - block / 2)
        folds.setPad(nil, 0)
        #expect(top("== A2") == open - block)

        b.unfold([a1])
        folds.update(region)
        #expect(shownLines(tv) == [1, 2, 3, 4, 5, 6, 7, 8])  // laid out for the snapshot
        folds.held = b.foldRegions.first { $0.heading == a1 }?.hidden
        folds.relayout(region)
        #expect(shownLines(tv) == [1, 2, 3, 5, 6, 7, 8])     // hidden again until the motion ends
        #expect(top("== A2") == open - block)
        folds.setPad(a1, block)
        #expect(top("== A2") == open)
        folds.held = nil
        folds.setPad(nil, 0)
        folds.relayout(region)
        #expect(shownLines(tv) == [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(top("== A2") == open)
    }

    /// Every laid-out paragraph is exactly a line the buffer does not hide.
    private func expectLayoutMatchesFolds(_ tv: NSTextView, _ b: Buffer, sourceLocation: SourceLocation = #_sourceLocation) {
        let tlm = tv.textLayoutManager!, tcs = tv.textContentStorage!
        var laid: [Int] = []
        tlm.enumerateTextLayoutFragments(from: tlm.documentRange.location, options: [.ensuresLayout]) { f in
            laid.append(tcs.offset(from: tcs.documentRange.location, to: f.rangeInElement.location))
            return true
        }
        var visible: [Int] = []
        (b.storage.string as NSString).enumerateSubstrings(in: NSRange(location: 0, length: b.storage.length), options: [.byLines, .substringNotRequired]) { _, r, _, _ in
            if !b.hiddenRanges.contains(where: { NSLocationInRange(r.location, $0.range) }) { visible.append(r.location) }
        }
        #expect(laid == visible, sourceLocation: sourceLocation)
    }

    /// A heading level edited while a fold is closed changes the fold's extent: the layout follows, and the line
    /// being typed never disappears into it.
    @Test func headingLevelEditsReshapeFoldsAndRelayout() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        let folds = FoldController()
        let tv = view(b, folds)
        b.fold([at("== A1")])
        folds.update()
        #expect(shownLines(tv) == [1, 2, 3, 5, 6, 7, 8])

        // `== A2` becomes `=== A2`: A1's section would now reach `= B`, over the line being typed, so it opens.
        let rev = b.foldRevision
        tv.insertText("=", replacementRange: NSRange(location: at("== A2"), length: 0))
        for _ in 0..<20 where shownLines(tv).count < 8 { await Task.yield() }
        #expect(!b.isFolded(at("== A1")))
        #expect(b.foldRevision > rev)
        #expect(shownLines(tv) == [1, 2, 3, 4, 5, 6, 7, 8])
        expectLayoutMatchesFolds(tv, b)

        // `== A1` becomes `= A1` (its second `=` deleted): the fold stays and now reaches `= B`.
        replace(b, NSRange(location: at("=== A2", in: b.storage.string), length: 1), with: "")
        b.fold([at("== A1", in: b.storage.string)])
        folds.update()
        #expect(shownLines(tv) == [1, 2, 3, 5, 6, 7, 8])
        tv.insertText("", replacementRange: NSRange(location: at("== A1", in: b.storage.string) + 1, length: 1))
        for _ in 0..<20 where shownLines(tv).count > 5 { await Task.yield() }
        #expect(b.isFolded(at("= A1", in: b.storage.string)))
        #expect(b.hiddenRanges.map { (b.storage.string as NSString).substring(with: $0.range) } == ["a1 text\n== A2\na2\n"])
        #expect(shownLines(tv) == [1, 2, 3, 7, 8])
        expectLayoutMatchesFolds(tv, b)
    }

    /// A file switch with the editor's selection delegate in place keeps the incoming file's folds closed, even when
    /// the outgoing caret's offset lies inside one (the app ignores selection changes while it swaps).
    @Test func aFileSwitchKeepsTheIncomingFolds() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text, "other.typ": String(repeating: "x", count: 40)])
        let b = try await p.open(RelPath("main.typ")!)
        let o = try await p.open(RelPath("other.typ")!)
        let folds = FoldController()
        let tv = view(o, folds)
        let delegate = SelectionDelegate(folds)
        tv.delegate = delegate
        b.fold([0])
        tv.setSelectedRange(NSRange(location: at("a1 text"), length: 0))
        delegate.swapping = true
        folds.buffer = b
        tv.textContentStorage!.adopt(b.storage)
        tv.setSelectedRange(b.restoredSelection)
        delegate.swapping = false
        #expect(b.isFolded(0))
        #expect(shownLines(tv) == [1, 7, 8])
    }

    /// The app's selection delegate, minus the event check: `keyboard` says what the app would read from the event.
    final class SelectionDelegate: NSObject, NSTextViewDelegate {
        let folds: FoldController
        var keyboard = false, swapping = false
        init(_ folds: FoldController) { self.folds = folds }
        func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
            MainActor.assumeIsolated { swapping ? new : folds.selection(new, from: old, keyboard: keyboard) }
        }
    }

    @Test func caretMovesFindAndJumpsThroughTheTextView() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.text])
        let b = try await p.open(RelPath("main.typ")!)
        let folds = FoldController()
        let tv = view(b, folds)
        let delegate = SelectionDelegate(folds)
        tv.delegate = delegate
        folds.onChange = { tv.textLayoutManager?.textViewportLayoutController.layoutViewport() }   // as the app does, inside the change
        b.fold([0])
        folds.update()
        #expect(shownLines(tv) == [1, 7, 8])

        // Arrow keys step over the fold in both directions.
        delegate.keyboard = true
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.moveRight(nil)
        #expect(tv.selectedRange() == NSRange(location: at("= B"), length: 0))
        tv.moveLeft(nil)
        #expect(tv.selectedRange() == NSRange(location: 3, length: 0))
        tv.moveDown(nil)
        #expect(b.hidden(at: tv.selectedRange().location) == nil)
        #expect(b.isFolded(0))

        // Find selects a match through the text finder client; the fold opens and the match is laid out.
        let match = (b.storage.string as NSString).range(of: "a1 text")
        tv.selectedRanges = [NSValue(range: match)]
        #expect(tv.selectedRange() == match)
        #expect(!b.isFolded(0))
        #expect(shownLines(tv) == [1, 2, 3, 4, 5, 6, 7, 8])

        // A jump (programmatic, not the keyboard) into a folded section opens it, nested folds included.
        b.foldAll()
        folds.update()
        delegate.keyboard = false
        tv.setSelectedRange(NSRange(location: at("a2"), length: 0))
        #expect(tv.selectedRange() == NSRange(location: at("a2"), length: 0))
        #expect(!b.isFolded(0) && !b.isFolded(at("== A2")))
        #expect(b.isFolded(at("== A1")) && b.isFolded(at("= B")))
        #expect(shownLines(tv) == [1, 2, 3, 5, 6, 7])
        #expect(tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil).height > 0)
    }
    #endif
}

@Suite(.serialized) @MainActor struct BracketFoldTests {
    private func blocks(_ text: String) -> [FoldRegion] {
        Folding.brackets(in: text as NSString, mode: { _ in .code })
    }

    @Test func nestedCallsGiveTwoRegionsAndAOneLineCallNone() {
        let text = "#figure(\n  table(\n    [a], [b],\n  ),\n  caption: [x],\n)\nafter\n"
        let r = blocks(text).sorted { $0.heading < $1.heading }
        let ns = text as NSString
        #expect(r.count == 2)
        #expect(r.map(\.kind) == [.bracket, .bracket])
        #expect(r.map { ns.substring(with: $0.hidden) } == ["  table(\n    [a], [b],\n  ),\n  caption: [x],\n)\n", "    [a], [b],\n  ),\n"])
        #expect(r.compactMap { $0.tail.map(ns.substring(with:)) } == [")", "),"])         // shown after the badge: `( ··· )`
        #expect(r.map(\.lines) == [4, 1])
        #expect(ns.substring(with: NSRange(location: r[0].end - 2, length: 2)) == ")\n")
        #expect(blocks("#figure(table([a], [b]))\n").isEmpty)
        #expect(blocks("#f(\n)\n").isEmpty)                      // nothing between the lines
    }

    @Test func oneRegionPerOpeningLineTheOutermost() {
        let r = blocks("#a(b(\n  x\n), c)\n")
        #expect(r.count == 1)
        #expect(r[0].lines == 1)
    }

    @Test func bracketsInStringsCommentsAndRawAreIgnored() async throws {
        let text = "#let s = \"(\n\"\n// (\n#f(\n  1,\n)\n```\n{\nx\n```\nend\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let ns = text as NSString
        #expect(b.foldRegions.map(\.heading) == [ns.range(of: "#f(").location, ns.range(of: "```").location])   // the raw block folds, its `{` doesn't
    }

    @Test func headingsStillFoldAndNestWithBlocks() async throws {
        let text = "= A\n#f(\n  1,\n)\n= B\nx\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        #expect(b.foldRegions.map(\.kind) == [.heading, .bracket, .heading])
        #expect(b.headingRegions.map(\.heading) == [0, (text as NSString).range(of: "= B").location])
    }
}

@Suite(.serialized) @MainActor struct BlockFoldTests {
    /// The regions of `text` as (hidden text, tail text), by start line.
    private func folds(_ text: String) async throws -> [(start: String, hidden: String, tail: String?)] {
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let ns = text as NSString
        return b.foldRegions.map { r in
            (ns.substring(with: ns.lineRange(for: NSRange(location: r.heading, length: 0))).trimmingCharacters(in: .newlines),
             ns.substring(with: r.hidden), r.tail.map(ns.substring(with:)))
        }
    }

    @Test func displayMathFoldsAndInlineMathDoesNot() async throws {
        let f = try await folds("$\nx + y\n$\n$x$ and $y\nz$\n$ a $\n")
        #expect(f.map(\.start) == ["$"])
        #expect(f.map(\.hidden) == ["x + y\n$\n"])
        #expect(f.map(\.tail) == ["$"])
        #expect(try await folds("$\nx +\n").isEmpty)                 // unclosed
    }

    @Test func rawBlocksFoldWithAnyFenceLength() async throws {
        let f = try await folds("```typ\n#f(\n```\n````\n```\nz\n```\n````\n`inline`\n```\nx\n")
        #expect(f.map(\.start) == ["```typ", "````"])
        #expect(f.map(\.tail) == ["```", "````"])
        #expect(f[1].hidden == "```\nz\n```\n````\n")
        #expect(try await folds("```\ntwo\n```\n").map(\.tail) == ["```"])
        #expect(try await folds("```\n```\n").isEmpty)               // nothing between
    }

    @Test func blockCommentsAndCommentRuns() async throws {
        let f = try await folds("/* a\nb\nc */\n// 1\n// 2\n// 3\n// 4\ntext\n// 1\n// 2\n#f() // x\n/* a\nb */\n")
        #expect(f.map(\.start) == ["/* a", "// 1"])
        #expect(f[0].tail == "c */")
        #expect(f[1].hidden == "// 2\n// 3\n// 4\n")
        #expect(f[1].tail == "")
    }

    @Test func listItemsFoldTheirChildren() async throws {
        let text = "- one\n  a\n  b\n- two\n  a\n+ three\n  x\n\n  y\n  - nested\n    n1\n    n2\n/ Term: d\n  m1\n  m2\ntail\n"
        let f = try await folds(text)
        #expect(f.map(\.start) == ["- one", "+ three", "  - nested", "/ Term: d"])
        #expect(f[0].hidden == "  a\n  b\n")
        #expect(f[1].hidden == "  x\n\n  y\n  - nested\n    n1\n    n2\n")
        #expect(f[2].hidden == "    n1\n    n2\n")
        #expect(f[3].hidden == "  m1\n  m2\n")
        #expect(f.map(\.tail) == [nil, nil, nil, nil])
    }

    @Test func contentBlocksOfRulesAndLetFold() async throws {
        let f = try await folds("#show heading: it => [\n  a\n  b\n]\n#set text(\n  size: 1pt,\n)\n#let f(x) = {\n  x\n}\n")
        #expect(f.map(\.start) == ["#show heading: it => [", "#set text(", "#let f(x) = {"])
        #expect(f.map(\.tail) == ["]", ")", "}"])
    }

    @Test func nestingAndPrecedence() async throws {
        // a raw block inside a content block, math inside a list item, a heading beating a block on its line
        let text = "#box[\n  ```\n  x\n  ```\n]\n- item\n  $\n  x\n  $\n  y\n= H #f(\n  1,\n)\nz\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": text])
        let b = try await p.open(RelPath("main.typ")!)
        let ns = text as NSString
        #expect(b.foldRegions.map(\.heading) == ["#box[", "  ```", "- item", "  $", "= H"].map { ns.range(of: $0).location })
        #expect(b.foldRegions.map(\.kind) == [.bracket, .bracket, .bracket, .bracket, .heading])
        #expect(b.headingRegions.count == 1)
        b.foldAll()
        #expect(b.hiddenRanges.count == 1)                           // Fold All stays headings only
    }
}
