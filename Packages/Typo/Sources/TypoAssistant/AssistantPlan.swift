import Foundation

/// An agent's plan as an answer shows and keeps it: its to-do list, with where in the answer it first appeared.
public struct AssistantPlan: Codable, Hashable, Sendable {
    public enum Priority: String, Codable, Sendable { case high, medium, low }
    public enum Status: String, Codable, Sendable { case pending, inProgress = "in_progress", completed }

    public struct Entry: Codable, Hashable, Sendable {
        public var content: String
        public var priority: Priority
        public var status: Status
        public init(content: String, priority: Priority = .medium, status: Status = .pending) {
            self.content = content; self.priority = priority; self.status = status
        }
    }

    public var entries: [Entry]
    /// How many of the answer's tool calls come before the plan.
    public var after: Int

    public init(entries: [Entry], after: Int = 0) { self.entries = entries; self.after = after }

    public var completed: Int { entries.count { $0.status == .completed } }

    /// The plan an update brings to `answer`: it replaces the one before and keeps its place; no entries clear it.
    public static func updated(_ answer: AssistantMessage, with entries: [Entry]) -> AssistantPlan? {
        entries.isEmpty ? nil : AssistantPlan(entries: entries, after: answer.plan?.after ?? answer.toolCalls?.count ?? 0)
    }

    /// Whether the running turn is planning: the agent is in its plan mode, or its latest update was a plan with
    /// nothing done yet.
    public static func isPlanning(planMode: Bool, latestUpdateIsPlan: Bool, plan: AssistantPlan?) -> Bool {
        planMode || (latestUpdateIsPlan && plan.map { $0.completed == 0 } == true)
    }
}
