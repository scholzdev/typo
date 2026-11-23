import Foundation
import Testing
@testable import TypoAssistant

struct AssistantMentionsTests {
    @Test func queryNeedsAnAtAfterWhitespaceOrAtTheStart() {
        #expect(AssistantMentions.query(in: "@ma", caret: 3)?.query == "ma")
        #expect(AssistantMentions.query(in: "@ma", caret: 3)?.range == NSRange(location: 0, length: 3))
        let t = "Dokumentiere @InF"
        #expect(AssistantMentions.query(in: t, caret: (t as NSString).length)?.range == NSRange(location: 13, length: 4))
        #expect(AssistantMentions.query(in: "a @", caret: 3)?.query == "")
        #expect(AssistantMentions.query(in: "mail@host", caret: 9) == nil)
        #expect(AssistantMentions.query(in: "@ma x", caret: 5) == nil)
        #expect(AssistantMentions.query(in: "@main more", caret: 3)?.query == "ma")
        #expect(AssistantMentions.query(in: "", caret: 0) == nil)
    }

    @Test func matchesRankPrefixThenContainsThenPathThenLetters() {
        let paths = ["chapters/intro.typ", "main.typ", "refs/domain.bib", "Mappe/notes.typ", "template/my-main.typ"]
        #expect(AssistantMentions.matches("main", in: paths) == ["main.typ", "refs/domain.bib", "template/my-main.typ"])
        #expect(AssistantMentions.matches("mappe", in: paths) == ["Mappe/notes.typ"])
        #expect(AssistantMentions.matches("itr", in: paths) == ["chapters/intro.typ"])
        #expect(AssistantMentions.matches("", in: paths, limit: 2) == ["main.typ", "Mappe/notes.typ"])
        #expect(AssistantMentions.matches("zzz", in: paths).isEmpty)
    }

    @Test func rangesFindWholeFileNames() {
        let text = "Dokumentiere mal InFormApp.swift und MyInFormApp.swift, dann main.typ."
        let r = AssistantMentions.ranges(of: ["App/InFormApp.swift", "main.typ"], in: text)
        #expect(r.map { String(text[$0]) } == ["InFormApp.swift", "main.typ"])
        #expect(AssistantMentions.ranges(of: [], in: text).isEmpty)
    }

    @Test func oldMessagesWithoutMentionsStillDecode() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","role":"user","text":"Hi","truncated":false,"edits":{}}"#
        let m = try JSONDecoder().decode(AssistantMessage.self, from: Data(json.utf8))
        #expect(m.mentions == nil)
        var n = m
        n.mentions = ["main.typ"]
        let back = try JSONDecoder().decode(AssistantMessage.self, from: JSONEncoder().encode(n))
        #expect(back.mentions == ["main.typ"])
    }

    private func kind(_ d: String) -> String {
        let c = AssistantCommandKind.classify(d)
        return "\(c.kind): \(c.description)"
    }

    @Test func skillsNameTheirSourceInParentheses() {
        #expect(kind("Compact the conversation") == "command: Compact the conversation")
        #expect(kind("Review a diff (user)") == "skill: Review a diff")
        #expect(kind("Run it (dynamic workflow)") == "skill: Run it")
        #expect(kind("(pstack (Claude Code port)) Sketch types first") == "skill: Sketch types first")
        #expect(kind("Tidy (a) things (project)") == "skill: Tidy (a) things")
        #expect(kind("") == "command: ")
    }
}
