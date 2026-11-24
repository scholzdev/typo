import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@MainActor struct PresenterNotesTests {
    @Test func extractsTouyingAndPolyluxNotes() {
        let text = """
        = One
        #speaker-note[Say *hello*
          to everyone]
        // #speaker-note[commented out]
        #pdfpc.speaker-note("Line one\\nSay \\"two\\"")
        #toolbox.pdfpc.speaker-note(```md
        - raw note
        ```)
        #my-speaker-note[not a note]
        #raw("#speaker-note[in a string]")
        """
        let notes = PresenterNotes.extract(text)
        #expect(notes.map(\.text) == ["Say *hello*\nto everyone", "Line one\nSay \"two\"", "- raw note"])
        #expect(notes.map(\.kind) == [.touying, .polylux, .polylux])
        #expect(notes.first?.range.location == (text as NSString).range(of: "#speaker-note[Say").location)
    }

    @Test func extractsMetadataOnlyWithTheNoteLabel() {
        let text = """
        #metadata("string form") <note>
        #metadata[content *form*] <note>
        #metadata("no label")
        #metadata("other label") <other>
        #metadata("label after a blank line")

        <note>
        // #metadata("commented out") <note>
        #raw("#metadata(\\"in raw\\") <note>")
        """
        let notes = PresenterNotes.extract(text)
        #expect(notes.map(\.text) == ["string form", "content *form*"])
        #expect(notes.allSatisfy { $0.kind == .typo })
        let ns = text as NSString
        #expect(ns.substring(with: notes[0].range) == "#metadata(\"string form\") <note>")
        #expect(ns.substring(with: notes[1].range) == "#metadata[content *form*] <note>")
    }

    @Test func writtenFormRoundTrips() {
        for text in ["He said \"hi\" \\ $5 #1 [x]", "two\nlines", "trailing backslash \\", "#metadata(\"x\") <note>", ""] {
            let written = PresenterNotes.written(text)
            #expect(!written.contains("\n"))
            let found = PresenterNotes.extract("= S\n" + written + "\nafter")
            #expect(found.map(\.text) == [text])
            #expect(("= S\n" + written + "\nafter" as NSString).substring(with: found[0].range) == written)
        }
    }

    @Test func cardLinesRoundTripTheirText() {
        for text in ["", "He said \"hi\" \\ $5", "two\nlines", "  leading and trailing  ", "back\\nslash n"] {
            let source = "= S\n  " + PresenterNotes.written(text) + " \t\nafter"
            let cards = PresenterNotes.cardLines(in: source)
            #expect(cards.map(\.text) == [text])
            let ns = source as NSString
            #expect(ns.substring(with: cards[0].call) == PresenterNotes.written(text))
            #expect(ns.substring(with: cards[0].line) == "  " + PresenterNotes.written(text) + " \t\n")
        }
    }

    @Test func onlyLinesHoldingJustAStringNoteAreCards() {
        let text = """
        #metadata("card") <note>
        // #metadata("commented") <note>
        #raw("#metadata(\\"raw\\") <note>")
        #metadata[content form] <note>
        Text #metadata("not alone") <note>
        #metadata("tab \\t escape") <note>
        #metadata("split")
        <note>
        #speaker-note[touying]
        #metadata("last") <note>
        """
        #expect(PresenterNotes.cardLines(in: text).map(\.text) == ["card", "content form", "last"])
        #expect(PresenterNotes.cardLines(in: "#metadata(\"x\") <note>").first?.line == NSRange(location: 0, length: 21))
    }

    @Test func markersPointIntoTheirMarker() {
        let text = "a #speaker-note[x] b #speaker-note[y]"
        let notes = PresenterNotes.extract(text)
        let (marked, cursors) = PresenterNotes.marked(text, notes)
        let ns = marked as NSString
        #expect(cursors.map { ns.substring(with: NSRange(location: $0 - 1, length: 2)) } == ["x]", "x]"])
        #expect(marked.components(separatedBy: PresenterNotes.marker).joined() == text)
    }

    @Test func notesGoToEveryPageTheyLandOn() {
        func note(_ t: String, _ pages: [Int]) -> PresenterNote {
            PresenterNote(path: RelPath("main.typ")!, callRange: NSRange(location: 0, length: 1), text: t, kind: .typo, pages: pages)
        }
        let notes = [note("a", [0, 1]), note("b", [1]), note("", [2])]
        #expect(PresenterNotes.byPage(notes).mapValues { $0.map(\.text) } == [0: ["a"], 1: ["a", "b"], 2: [""]])
        #expect(PresenterNotes.texts(notes) == [0: "a", 1: "a\n\nb"])
    }

    @Test func replacementWritesOrRemovesTheCall() {
        let text = "Body\n#metadata(\"old\") <note>\nNext\n"
        let range = (text as NSString).range(of: "#metadata(\"old\") <note>")
        #expect(PresenterNotes.replacement(for: range, in: text, writing: "new").text == PresenterNotes.written("new"))
        let gone = PresenterNotes.replacement(for: range, in: text, writing: "")
        #expect((text as NSString).replacingCharacters(in: gone.range, with: gone.text) == "Body\nNext\n")
        let last = "Body\n#metadata(\"old\") <note>"
        let lastRange = (last as NSString).range(of: "#metadata(\"old\") <note>")
        let r = PresenterNotes.replacement(for: lastRange, in: last, writing: "")
        #expect((last as NSString).replacingCharacters(in: r.range, with: r.text) == "Body")
        let shared = "Say it #metadata(\"old\") <note> now\n"
        let s = PresenterNotes.replacement(for: (shared as NSString).range(of: "#metadata(\"old\") <note>"), in: shared, writing: "")
        #expect((shared as NSString).replacingCharacters(in: s.range, with: s.text) == "Say it now\n")
    }

    @Test func removingASharedNoteTakesOneSpaceWithIt() {
        let call = "#metadata(\"x\") <note>"
        for (text, expected) in [("Say \(call) now", "Say now"), ("\(call) first", "first"), ("Last \(call)\nnext", "Last\nnext"), ("tight\(call)end", "tightend")] {
            let r = PresenterNotes.replacement(for: (text as NSString).range(of: call), in: text, writing: "")
            #expect((text as NSString).replacingCharacters(in: r.range, with: r.text) == expected)
        }
    }

    @Test func notesSharingTheirLineAreInline() {
        let text = """
        #metadata("card") <note>
        Text #metadata("explain this") <note> more
        Two #metadata[say hi] <note> and #metadata("bye") <note>
        // Text #metadata("commented") <note>
        Text #raw("#metadata(\\"raw\\") <note>")
        #let s = "#metadata(\\"string\\") <note>"
        Text #metadata("split")
        <note>
        Text #metadata("tab \\t escape") <note>
        Text #speaker-note[touying]
        """
        let ns = text as NSString
        let inline = PresenterNotes.inlineNotes(in: text)
        #expect(inline.map(\.text) == ["explain this", "say hi", "bye"])
        #expect(inline.map { ns.substring(with: $0.call) } == ["#metadata(\"explain this\") <note>", "#metadata[say hi] <note>", "#metadata(\"bye\") <note>"])
        let second = ns.range(of: "Text #metadata(\"explain").location, third = ns.range(of: "Two ").location
        #expect(inline.map(\.lineStart) == [second, third, third])
        #expect(PresenterNotes.cardLines(in: text).map(\.text) == ["card"])
    }

    @Test func insertionKeepsTheLineBreakAfterTheNote() {
        let text = "Body line\nNext line\n"
        let r = PresenterNotes.insertion(of: PresenterNotes.written("x"), afterLineAt: 3, in: text)
        #expect((text as NSString).replacingCharacters(in: r.range, with: r.text) == "Body line\n#metadata(\"x\") <note>\nNext line\n")
        let eof = "Only line"
        let e = PresenterNotes.insertion(of: PresenterNotes.written("x"), afterLineAt: 2, in: eof)
        #expect((eof as NSString).replacingCharacters(in: e.range, with: e.text) == "Only line\n#metadata(\"x\") <note>")
    }

    static let deck = """
    #set page(width: 200pt, height: 160pt, margin: 12pt, numbering: "1")
    = First slide
    Alpha text on the first page.
    #pagebreak()
    = Second slide
    Beta text on the second page.
    #pagebreak()
    = Third slide
    Gamma text on the third page.
    """

    @Test func collectsNotesOfEveryFileAndDropsOnesNeverIncluded() async throws {
        let main = """
        #set page(width: 200pt, height: 160pt)
        = First
        #metadata("Open with the question.") <note>
        #pagebreak()
        #include "chapter.typ"
        #pagebreak()
        = Third
        Body text.
        #pdfpc.speaker-note("Thank them.")
        """
        let chapter = "= Second\nChapter text.\n#metadata(\"Mention the chapter.\") <note>\n"
        let (p, _) = try await TestEnv.project(files: [
            "main.typ": "#import \"pdfpc.typ\"\n" + main, "chapter.typ": chapter, "pdfpc.typ": "#let speaker-note(x) = metadata(x)\n",
            "orphan.typ": "#metadata(\"Nobody sees this.\") <note>\n",
        ])
        _ = await p.settle()
        #expect(p.preview.pages.count == 3)
        let notes = await p.presenterNotes()
        #expect(Dictionary(uniqueKeysWithValues: notes.map { ($0.text, ($0.path.raw, $0.pages, $0.kind)) }).mapValues { "\($0.0) \($0.1) \($0.2)" } == [
            "Open with the question.": "main.typ [0] typo", "Mention the chapter.": "chapter.typ [1] typo", "Thank them.": "main.typ [2] polylux",
        ])
        #expect(PresenterNotes.texts(notes) == [0: "Open with the question.", 1: "Mention the chapter.", 2: "Thank them."])
    }

    @Test func openBuffersWinOverDisk() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "= One\nbody\n#pagebreak()\n= Two\n"])
        let b = try await p.open(RelPath("main.typ")!)
        replace(b, NSRange(location: b.storage.length, length: 0), with: "#metadata(\"typed, not saved\") <note>\n")
        _ = await p.settle()
        #expect(await p.presenterNotes().map(\.text) == ["typed, not saved"])
    }

    /// The position a new note gets, per page, on a three-page document: inside that page's own text.
    @Test func newNotePositionIsOnItsPage() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.deck])
        _ = await p.settle()
        #expect(p.preview.pages.count == 3)
        for (page, marker) in [(0, "Alpha"), (1, "Beta"), (2, "Gamma")] {
            let pos = try #require(await p.presenterNotePosition(page: page))
            #expect(pos.path.raw == "main.typ")
            let r = PresenterNotes.insertion(of: PresenterNotes.written("n"), afterLineAt: pos.offset, in: pos.text)
            let after = (pos.text as NSString).replacingCharacters(in: r.range, with: r.text)
            let lines = after.components(separatedBy: "\n")
            let at = try #require(lines.firstIndex { $0.hasPrefix("#metadata") })
            #expect(lines[at - 1].contains(marker), "page \(page): note placed after \(lines[at - 1])")
        }
    }

    @Test func settingANoteIsOneUndoStep() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.deck])
        _ = await p.settle()
        let b = try await p.open(RelPath("main.typ")!)
        #expect(await p.setPresenterNote("He said \"hi\"", replacing: nil, onPage: 1, actionName: "Edit Presenter Note"))
        _ = await p.settle()
        let note = try #require(await p.presenterNotes().first)
        #expect(note.text == "He said \"hi\"" && note.pages == [1])
        #expect(await p.setPresenterNote("Changed", replacing: note, onPage: 1, actionName: "Edit Presenter Note"))
        #expect(b.storage.string.contains(PresenterNotes.written("Changed")))
        b.undoManager.undo()
        #expect(b.storage.string.contains(PresenterNotes.written("He said \"hi\"")))
        #expect(await p.setPresenterNote("", replacing: note, onPage: 1, actionName: "Edit Presenter Note"))
        #expect(b.storage.string == Self.deck)
    }

    @Test func draftMessageHasTheSlideAndItsNeighbours() {
        let m = PresenterNotes.draftMessage(slide: "= Results\nRevenue grew.", number: 2, total: 3, previous: "= Intro", next: "= Outlook", existing: "Old note")
        #expect(m.contains("Revenue grew.") && m.contains("slide 2 of 3") && m.contains("= Intro") && m.contains("= Outlook") && m.contains("Old note"))
        #expect(!PresenterNotes.draftMessage(slide: "x", number: 1, total: 1, previous: nil, next: nil, existing: "").contains("previous"))
        #expect(PresenterNotes.draftText(fromReply: "```\n\"Say it.\"\n```") == "Say it.")
    }

    @Test func draftsFromTheSlideSourceWithAStubModel() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": Self.deck])
        _ = await p.settle()
        let seen = Seen()
        let reply = try await p.draftPresenterNote(page: 1) { system, message in
            await seen.set(message)
            return "A drafted note."
        }
        #expect(reply == "A drafted note.")
        let message = await seen.value
        #expect(message.contains("Beta text on the second page.") && message.contains("Alpha text") && message.contains("Gamma text"))
        #expect(message.range(of: "Beta text")!.lowerBound < message.range(of: "Alpha text")!.lowerBound)
    }
}

private actor Seen {
    var value = ""
    func set(_ s: String) { value = s }
}
