import Foundation
import JSONRPC

/// The agent's plan, such as Claude Code's to-do list: each `plan` update replaces it whole; no entries clears it.
public struct ACPPlan: Sendable, Equatable {
    public enum Priority: String, Sendable { case high, medium, low }
    public enum Status: String, Sendable { case pending, inProgress = "in_progress", completed }

    public struct Entry: Sendable, Equatable {
        public var content: String
        public var priority: Priority
        public var status: Status
        public init(content: String, priority: Priority = .medium, status: Status = .pending) {
            self.content = content; self.priority = priority; self.status = status
        }
    }

    public var entries: [Entry]
    public init(entries: [Entry]) { self.entries = entries }

    /// The plan of a `plan` session update, nil for other updates. Entries without content are skipped; an unknown
    /// priority reads as medium, an unknown status as pending.
    public static func parse(_ update: JSONValue) -> ACPPlan? {
        guard update["sessionUpdate"]?.string == "plan" else { return nil }
        return ACPPlan(entries: (update["entries"]?.array ?? []).compactMap { e in
            guard let content = e["content"]?.string else { return nil }
            return Entry(content: content, priority: e["priority"]?.string.flatMap(Priority.init) ?? .medium,
                         status: e["status"]?.string.flatMap(Status.init) ?? .pending)
        })
    }
}
