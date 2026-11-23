import ACPProtocol
import TypoAssistant

extension ACPPlan {
    /// The entries as an answer keeps them; both sides share the wire's names.
    public var assistantEntries: [AssistantPlan.Entry] {
        entries.map { AssistantPlan.Entry(content: $0.content, priority: AssistantPlan.Priority(rawValue: $0.priority.rawValue) ?? .medium,
                                          status: AssistantPlan.Status(rawValue: $0.status.rawValue) ?? .pending) }
    }
}
