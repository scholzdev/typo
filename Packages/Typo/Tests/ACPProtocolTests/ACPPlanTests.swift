import Testing
import JSONRPC
@testable import ACPProtocol

struct ACPPlanTests {
    @Test func readsThePlanOfAPlanUpdate() {
        let p = ACPPlan.parse(["sessionUpdate": "plan", "entries": [
            ["content": "Read main.typ", "priority": "high", "status": "completed"],
            ["content": "Add the title", "priority": "low", "status": "in_progress"],
            ["content": "Compile", "priority": "urgent", "status": "blocked"],
            ["priority": "high", "status": "pending"],
        ]])
        #expect(p?.entries == [
            ACPPlan.Entry(content: "Read main.typ", priority: .high, status: .completed),
            ACPPlan.Entry(content: "Add the title", priority: .low, status: .inProgress),
            ACPPlan.Entry(content: "Compile", priority: .medium, status: .pending),
        ])
    }

    @Test func noEntriesIsAnEmptyPlanAndOtherUpdatesAreNone() {
        #expect(ACPPlan.parse(["sessionUpdate": "plan", "entries": []]) == ACPPlan(entries: []))
        #expect(ACPPlan.parse(["sessionUpdate": "plan"]) == ACPPlan(entries: []))
        #expect(ACPPlan.parse(["sessionUpdate": "plan_update", "plan": ["type": "items"]]) == nil)
        #expect(ACPPlan.parse(["sessionUpdate": "agent_message_chunk"]) == nil)
    }
}
