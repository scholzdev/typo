import Foundation
import TypoKit
import TypoAssistant

extension Project {
    /// Ends the hold and takes what the agent wrote into the buffer as one undo step with AI marks, which leaves it
    /// clean: snapshot→disk for an existing file, the whole text marked for a new one. Returns the change for the
    /// transcript and the id Revert uses; nil when nothing changed or the buffer no longer has the snapshot's text.
    public func adoptAgentWrite(_ s: AgentSnapshot, actionName: String) async -> (edit: ProposedEdit, changeID: UUID?)? {
        guard let w = await adoptHeldWrite(s, actionName: actionName, diff: ACPFiles.replacement) else { return nil }
        let edit = w.old.map { ACPFiles.edit(path: s.path.raw, old: $0, w.change) }
            ?? ProposedEdit(path: s.path.raw, search: "", replace: w.change.text)
        return (edit, w.changeID)
    }
}
