import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit

@MainActor struct SpeakerNotesTests {
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
        let notes = SpeakerNotes.extract(text)
        #expect(notes.map(\.text) == ["Say *hello*\nto everyone", "Line one\nSay \"two\"", "- raw note"])
        #expect(notes.first?.offset == (text as NSString).range(of: "#speaker-note[Say").location)
    }

    @Test func markersPointIntoTheirMarker() {
        let text = "a #speaker-note[x] b #speaker-note[y]"
        let notes = SpeakerNotes.extract(text)
        let (marked, cursors) = SpeakerNotes.marked(text, notes)
        let ns = marked as NSString
        #expect(cursors.map { ns.substring(with: NSRange(location: $0 - 1, length: 2)) } == ["x]", "x]"])
        #expect(marked.components(separatedBy: SpeakerNotes.marker).joined() == text)
    }

    @Test func notesGoToEveryPageTheyLandOn() {
        let notes = [SpeakerNote(offset: 0, text: "a"), SpeakerNote(offset: 5, text: "b"), SpeakerNote(offset: 9, text: "lost")]
        #expect(SpeakerNotes.byPage(notes, pages: [[0, 1, 1], [1], []]) == [0: "a", 1: "a\n\nb"])
    }

    @Test func mapsNotesToCompiledPages() async throws {
        let text = """
        #let speaker-note(body) = metadata(body)
        #import "pdfpc.typ"
        = First
        #speaker-note[Open with the question.]
        #pagebreak()
        = Second
        No note here.
        #pagebreak()
        = Third
        Body text.
        #pdfpc.speaker-note("Thank them.")
        """
        let (p, _) = try await TestEnv.project(files: ["main.typ": text, "pdfpc.typ": "#let speaker-note(x) = metadata(x)\n"])
        _ = await p.settle()
        #expect(p.preview.pages.count == 3)
        #expect(await p.speakerNotes() == [0: "Open with the question.", 2: "Thank them."])
    }
}
