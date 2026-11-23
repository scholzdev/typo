import Foundation
import Testing
import TypoKit
@testable import TypoAssistant

struct AssistantPlanTests {
    private let three: [AssistantPlan.Entry] = [
        .init(content: "Read main.typ", status: .completed),
        .init(content: "Add the title", priority: .high, status: .inProgress),
        .init(content: "Compile", priority: .low),
    ]

    @Test func anUpdateReplacesThePlanAndKeepsItsPlace() {
        var m = AssistantMessage(role: .assistant, text: "")
        m.toolCalls = [ToolExchange(call: ToolCall(id: "a", name: "read", arguments: "{}"))]
        m.plan = AssistantPlan.updated(m, with: three)
        #expect(m.plan?.after == 1 && m.plan?.completed == 1)
        m.toolCalls! += [ToolExchange(call: ToolCall(id: "b", name: "edit", arguments: "{}"))]
        m.plan = AssistantPlan.updated(m, with: three.map { var e = $0; e.status = .completed; return e })
        #expect(m.plan?.after == 1 && m.plan?.completed == 3)
        #expect(AssistantPlan.updated(m, with: []) == nil)
    }

    @Test func planningWhileInPlanModeOrRightAfterAFreshPlan() {
        let fresh = AssistantPlan(entries: [.init(content: "a", status: .inProgress), .init(content: "b")])
        let started = AssistantPlan(entries: three)
        #expect(AssistantPlan.isPlanning(planMode: true, latestUpdateIsPlan: false, plan: nil))
        #expect(AssistantPlan.isPlanning(planMode: false, latestUpdateIsPlan: true, plan: fresh))
        #expect(!AssistantPlan.isPlanning(planMode: false, latestUpdateIsPlan: false, plan: fresh))    // a tool call followed
        #expect(!AssistantPlan.isPlanning(planMode: false, latestUpdateIsPlan: true, plan: started))
        #expect(!AssistantPlan.isPlanning(planMode: false, latestUpdateIsPlan: true, plan: nil))
    }

    @Test func statusShowsPlanningAfterBlockedAndBeforeResponding() {
        #expect(AssistantConversationStatus.of(running: true, blocked: true, planning: true, answering: false, failed: false, stopped: false) == .blocked)
        #expect(AssistantConversationStatus.of(running: true, blocked: false, planning: true, answering: true, failed: false, stopped: false) == .planning)
        #expect(AssistantConversationStatus.of(running: false, blocked: false, planning: true, answering: false, failed: false, stopped: false) == .idle)
    }

    @Test func thePlanIsSavedWithTheAnswerAndOldFilesHaveNone() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "plan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AssistantConversationStore(folder: folder)
        var c = AssistantConversation(providerID: nil, model: "m")
        var m = AssistantMessage(role: .assistant, text: "Done.")
        m.plan = AssistantPlan(entries: three, after: 2)
        c.messages = [m]
        try store.save(c)
        #expect(store.loadAll().first?.messages.first?.plan == m.plan)

        let saved = try String(contentsOf: folder.appending(path: c.id.uuidString + ".json"), encoding: .utf8)
        #expect(saved.contains(#""status":"in_progress""#))
        var old = try JSONSerialization.jsonObject(with: Data(saved.utf8)) as! [String: Any]
        var messages = old["messages"] as! [[String: Any]]
        messages[0]["plan"] = nil
        old["messages"] = messages
        let data = try JSONSerialization.data(withJSONObject: old)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(AssistantConversation.self, from: data).messages.first?.plan == nil)
    }
}
