import Foundation
import Testing
@testable import TypoAssistant
import TypstEngine

struct ConversationLayoutTests {
    let a = UUID(), b = UUID(), c = UUID()

    @Test func reconcilePutsNewOnTopAndDropsGone() {
        var l = AssistantConversationLayout()
        l.reconcile([a, b])
        #expect(l.order == [a, b])
        l.unread = [b]
        l.reconcile([c, a])
        #expect(l.order == [c, a])
        #expect(l.unread.isEmpty)
    }

    @Test func groupsTakeTheirItemsAndGiveThemBack() {
        var l = AssistantConversationLayout()
        l.reconcile([a, b, c])
        let g = l.newGroup(named: "Chapter 2", with: [b, c])
        #expect(l.order == [a])
        #expect(l.groups.first?.items == [b, c])
        #expect(l.group(of: c) == g)
        l.move(a, to: g, before: c)
        #expect(l.groups.first?.items == [b, a, c])
        #expect(l.order.isEmpty)
        l.move(b, to: nil)
        #expect(l.order == [b])
        l.renameGroup(g, to: "  ")
        #expect(l.groups.first?.name == "Chapter 2")
        l.deleteGroup(g)
        #expect(l.groups.isEmpty)
        #expect(l.order == [a, c, b])
    }

    @Test func addMovesToTheTop() {
        var l = AssistantConversationLayout()
        l.reconcile([a, b])
        let g = l.newGroup(named: "G", with: [b])
        l.add(b)
        #expect(l.order == [b, a])
        #expect(l.groups.first { $0.id == g }?.items == [])
    }

    @Test func storeRoundTrips() throws {
        let d = try #require(UserDefaults(suiteName: "ConversationLayoutTests"))
        defer { d.removePersistentDomain(forName: "ConversationLayoutTests") }
        let store = AssistantConversationLayoutStore(ProjectID(), defaults: d)
        var l = AssistantConversationLayout()
        l.reconcile([a])
        l.unread = [a]
        store.save(l)
        #expect(store.load() == l)
    }

    @Test func statusPrefersBlockedThenAnswering() {
        #expect(AssistantConversationStatus.of(running: true, blocked: true, answering: true, failed: false, stopped: false) == .blocked)
        #expect(AssistantConversationStatus.of(running: true, blocked: false, answering: true, failed: false, stopped: false) == .responding)
        #expect(AssistantConversationStatus.of(running: true, blocked: false, answering: false, failed: true, stopped: false) == .working)
        #expect(AssistantConversationStatus.of(running: false, blocked: false, answering: false, failed: true, stopped: true) == .failed)
        #expect(AssistantConversationStatus.of(running: false, blocked: false, answering: false, failed: false, stopped: false) == .idle)
    }
}

struct AssistantTurnsTests {
    @Test func countsLinesPerFileOfAppliedEdits() {
        var m = AssistantMessage(role: .assistant, text: "")
        m.text = [ACPLikeBlock.block("a.typ", "x\ny", "x\nz\nw"), ACPLikeBlock.block("b.typ", "", "new"), ACPLikeBlock.block("a.typ", "q", "")].joined(separator: "\n\n")
        m.edits = [0: .accepted, 1: .accepted, 2: .rejected]
        let c = AssistantTurns.changes(in: [m])
        #expect(c.map(\.path) == ["a.typ", "b.typ"])
        #expect(c[0].added == 2 && c[0].removed == 1 && !c[0].isNew)
        #expect(c[1].added == 1 && c[1].removed == 0 && c[1].isNew)
    }

    @Test func splitsTurnsAtUserMessages() {
        let msgs = [AssistantMessage(role: .user, text: "q1"), AssistantMessage(role: .assistant, text: "a"), AssistantMessage(role: .assistant, text: "b"),
                    AssistantMessage(role: .user, text: "q2")]
        let t = AssistantTurn.split(msgs)
        #expect(t.count == 2)
        #expect(t[0].answers.count == 2)
        #expect(t[1].answers.isEmpty)
    }

    @Test func formatsDurationsAndToolStates() {
        #expect(AssistantTurns.duration(11.4) == "11s")
        #expect(AssistantTurns.duration(65) == "1m 5s")
        #expect(AssistantToolStatus(acp: "in_progress") == .inProgress)
        #expect(AssistantToolStatus(acp: nil).isRunning)
        #expect(AssistantToolStatus.symbol(kind: "execute") == "terminal")
        #expect(AssistantToolStatus.symbol(kind: "unknown") == "wrench.and.screwdriver")
    }
}

/// Edit blocks in the answer format, as ACPFiles.block writes them.
enum ACPLikeBlock {
    static func block(_ path: String, _ search: String, _ replace: String) -> String {
        ([AssistantEdits.start + path] + (search.isEmpty ? [] : [search]) + [AssistantEdits.divider, replace, AssistantEdits.end]).joined(separator: "\n")
    }
}
