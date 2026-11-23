import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite @MainActor struct SectionMoveTests {
    static let doc = "#set page(\"a4\")\n\n= A\na\n\n== A1\na1\n\n= B\nb\n\n= C\nc\n"

    private func at(_ s: String, in text: String) -> Int { (text as NSString).range(of: s).location }

    /// The text after `move`, or nil when it refuses.
    private func moved(_ text: String, _ heading: String, to boundary: String?, level: Int? = nil) -> String? {
        let heads = Sections.headings(in: text)
        let to = boundary.map { at($0, in: text) } ?? (text as NSString).length
        guard let m = Sections.move(at(heading, in: text), to: to, level: level, in: text, headings: heads) else { return nil }
        var out = text as NSString
        for e in m.edits.reversed() { out = out.replacingCharacters(in: e.range, with: e.text) as NSString }
        #expect(out.substring(from: m.heading).hasPrefix("="))
        return out as String
    }

    @Test func sectionsRunToTheNextHeadingOfTheSameOrHigherLevel() {
        let heads = Sections.headings(in: Self.doc)
        let ns = Self.doc as NSString
        #expect(heads.map(\.level) == [1, 2, 1, 1])
        #expect(ns.substring(with: Sections.range(of: at("= A", in: Self.doc), in: heads, length: ns.length)!) == "= A\na\n\n== A1\na1\n\n")
        #expect(ns.substring(with: Sections.range(of: at("= C", in: Self.doc), in: heads, length: ns.length)!) == "= C\nc\n")
        // A heading with no body still has a section.
        let bare = "= A\n= B\n"
        #expect(Sections.range(of: 0, in: Sections.headings(in: bare), length: 8) == NSRange(location: 0, length: 4))
    }

    @Test func movesTheFirstSectionWithItsSubsectionsToTheEnd() {
        #expect(moved(Self.doc, "= A", to: nil) == "#set page(\"a4\")\n\n= B\nb\n\n= C\nc\n\n= A\na\n\n== A1\na1\n")
    }

    @Test func movesTheLastSectionToTheFront() {
        #expect(moved(Self.doc, "= C", to: "= A") == "#set page(\"a4\")\n\n= C\nc\n\n= A\na\n\n== A1\na1\n\n= B\nb\n")
    }

    @Test func movesAMiddleSectionAndLeavesTheOthersUntouched() {
        #expect(moved(Self.doc, "= B", to: "= A") == "#set page(\"a4\")\n\n= B\nb\n\n= A\na\n\n== A1\na1\n\n= C\nc\n")
        let heads = Sections.headings(in: Self.doc)
        let m = Sections.move(at("= B", in: Self.doc), to: at("= A", in: Self.doc), in: Self.doc, headings: heads)!
        // Neither edit reaches into section A, so its folds and bookmarks only shift.
        let a = Sections.range(of: at("= A", in: Self.doc), in: heads, length: (Self.doc as NSString).length)!
        #expect(m.edits.count == 2 && m.edits.allSatisfy { NSIntersectionRange($0.range, NSRange(location: a.location + 1, length: a.length - 2)).length == 0 })
    }

    @Test func refusesABoundaryInsideOrAtTheEdgesOfTheSection() {
        #expect(moved(Self.doc, "= A", to: "== A1") == nil)
        #expect(moved(Self.doc, "= A", to: "= A") == nil)
        #expect(moved(Self.doc, "= A", to: "= B") == nil)
        #expect(moved(Self.doc, "= C", to: nil) == nil)
        #expect(moved(Self.doc, "= A", to: "b\n") == nil)          // not a heading line
    }

    @Test func normalisesBlankLinesToExactlyOne() {
        let text = "= A\na\n\n\n\n= B\nb\n= C\nc\n\n\n"
        // Only the gaps next to the moved section change; the file's own trailing blank lines stay.
        #expect(moved(text, "= B", to: "= A") == "= B\nb\n\n= A\na\n\n= C\nc\n\n\n")
        #expect(moved(text, "= A", to: nil) == "= B\nb\n= C\nc\n\n= A\na\n")
    }

    @Test func aLastSectionWithoutTrailingNewlineKeepsTheFileWithoutOne() {
        let text = "= A\na\n\n= B\nb"
        #expect(moved(text, "= B", to: "= A") == "= B\nb\n\n= A\na")
        #expect(moved(text, "= A", to: nil) == "= B\nb\n\n= A\na")
    }

    @Test func labelsAfterHeadingsMoveWithThem() {
        let text = "= A <a>\na\n\n= B\n<b>\nb\n"
        #expect(moved(text, "= B", to: "= A") == "= B\n<b>\nb\n\n= A <a>\na\n")
    }

    @Test func equalsSignsInRawBlocksAreNotHeadings() {
        let text = "= A\n```\n= not a heading\n```\n\n= B\nb\n"
        #expect(Sections.headings(in: text).count == 2)
        #expect(moved(text, "= B", to: "= A") == "= B\nb\n\n= A\n```\n= not a heading\n```\n")
    }

    @Test func adoptingALevelShiftsEveryMovedHeading() {
        #expect(moved(Self.doc, "= A", to: nil, level: 2) == "#set page(\"a4\")\n\n= B\nb\n\n= C\nc\n\n== A\na\n\n=== A1\na1\n")
        #expect(moved("= B\nb\n\n=== A\n", "=== A", to: "= B", level: 1) == "= A\n\n= B\nb\n")
    }

    @Test func upAndDownSwapWithSiblingsOnly() {
        let heads = Sections.headings(in: Self.doc), n = (Self.doc as NSString).length
        #expect(Sections.neighbour(of: at("= B", in: Self.doc), up: true, in: heads, length: n) == at("= A", in: Self.doc))
        #expect(Sections.neighbour(of: at("= B", in: Self.doc), up: false, in: heads, length: n) == n)
        #expect(Sections.neighbour(of: at("= A", in: Self.doc), up: true, in: heads, length: n) == nil)
        #expect(Sections.neighbour(of: at("== A1", in: Self.doc), up: false, in: heads, length: n) == nil)
    }

    @Test func bufferMoveIsOneUndoStep() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.doc])
        let b = try await p.open(RelPath("main.typ")!)
        let caret = at("b\n", in: Self.doc)
        let new = b.moveSection(at: caret, up: true)
        #expect(b.storage.string == "#set page(\"a4\")\n\n= B\nb\n\n= A\na\n\n== A1\na1\n\n= C\nc\n")
        #expect(new.map { (b.storage.string as NSString).substring(from: $0).hasPrefix("b\n") } == true)
        b.undoManager.undo()
        #expect(b.storage.string == Self.doc)
    }

    @Test(arguments: [nil, 2]) func bookmarksFoldsAndAssistantMarksMoveWithTheSection(level: Int?) async throws {
        let doc = "= A\na\n\n== A1\na1\nmore\n\n= B\nb\n"
        let (p, _) = try await TestEnv.project(files: ["main.typ": doc])
        let main = RelPath("main.typ")!
        let b = try await p.open(main)
        func line(_ s: String) -> Int { CodeBookmark.line(at: at(s, in: b.storage.string), in: b.storage.string as NSString) }
        b.applyAssistant([Replacement(range: NSRange(location: at("a1", in: doc), length: 2), text: "x1")])
        p.toggleBookmark(main, line: line("more"))
        b.fold([at("== A1", in: doc)])
        b.undoManager.removeAllActions()            // undo below takes back the move only
        func check(_ moved: Bool) {
            let text = b.storage.string as NSString
            #expect(p.bookmarks.map(\.line) == [line("more")])
            #expect(b.isFolded(at(moved && level == 2 ? "=== A1" : "== A1", in: text as String)))
            #expect(b.aiMarks.ranges.map(text.substring) == ["x1"] && b.aiChanges.map { text.substring(with: $0.range) } == ["x1"])
        }
        b.moveSection(0, to: (b.storage.string as NSString).length, level: level)
        #expect(b.storage.string.hasPrefix("= B\nb\n\n="))
        check(true)
        b.undoManager.undo()
        #expect(b.storage.string.hasPrefix("= A\na\n"))
        check(false)
        b.undoManager.redo()
        check(true)
    }
}
