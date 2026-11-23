import Foundation
import TypoKit

/// One file a turn changed, as its capsule and the diff panel show it.
public struct AssistantFileChange: Equatable, Sendable, Identifiable {
    public var path: String
    public var added: Int
    public var removed: Int
    /// The turn created the file ("A"); otherwise it modified it ("M").
    public var isNew: Bool
    /// The applied edits on this file, in order, as (message id, edit index, edit).
    public var edits: [Edit]
    public var id: String { path }

    public struct Edit: Equatable, Sendable {
        public var message: UUID
        public var index: Int
        public var edit: ProposedEdit
    }
}

/// A user message and the answers to it.
public struct AssistantTurn: Identifiable, Sendable {
    public var user: AssistantMessage?
    public var answers: [AssistantMessage]
    public var id: UUID { user?.id ?? answers.first?.id ?? UUID() }

    /// How long the turn took, saved on its last answer.
    public var duration: TimeInterval? { answers.last?.duration }
    public var changes: [AssistantFileChange] { AssistantTurns.changes(in: answers) }

    /// The conversation's turns; answers before any user message form a turn of their own.
    public static func split(_ messages: [AssistantMessage]) -> [AssistantTurn] {
        var out: [AssistantTurn] = []
        for m in messages {
            if m.role == .user || out.isEmpty { out.append(AssistantTurn(user: m.role == .user ? m : nil, answers: m.role == .user ? [] : [m])) } else { out[out.count - 1].answers.append(m) }
        }
        return out
    }
}

public enum AssistantTurns {
    /// Lines added and removed between two texts, by a line diff.
    public static func lineDelta(old: String, new: String) -> (added: Int, removed: Int) {
        GitGutterMarks.compute(base: old, current: new).hunks.reduce((0, 0)) { ($0.0 + $1.newLines.count, $0.1 + $1.oldLines.count) }
    }

    /// The applied edits of `answers` by file, in the order the files were first changed.
    public static func changes(in answers: [AssistantMessage]) -> [AssistantFileChange] {
        var out: [AssistantFileChange] = []
        for m in answers {
            for (i, e) in AssistantEdits.parse(m.text).enumerated() where m.edits[i] == .accepted {
                let d = lineDelta(old: e.search, new: e.replace)
                let edit = AssistantFileChange.Edit(message: m.id, index: i, edit: e)
                if let k = out.firstIndex(where: { $0.path == e.path }) {
                    out[k].added += d.added; out[k].removed += d.removed; out[k].edits.append(edit)
                } else {
                    out.append(AssistantFileChange(path: e.path, added: d.added, removed: d.removed, isNew: e.search.isEmpty, edits: [edit]))
                }
            }
        }
        return out
    }

    /// "11s", "1m 5s".
    public static func duration(_ t: TimeInterval) -> String {
        let s = max(Int(t.rounded()), 0)
        return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
    }
}

/// A tool call's state as its row shows it.
public enum AssistantToolStatus: Equatable, Sendable {
    case pending, inProgress, completed, failed

    /// ACP's status strings; a missing one is pending.
    public init(acp: String?) {
        switch acp {
        case "in_progress": self = .inProgress
        case "completed": self = .completed
        case "failed": self = .failed
        default: self = .pending
        }
    }

    public var isRunning: Bool { self == .pending || self == .inProgress }

    /// The SF Symbol for a tool call of ACP kind `kind`.
    public static func symbol(kind: String?) -> String {
        switch kind {
        case "read": "doc.text"
        case "edit", "delete", "move": "pencil"
        case "search": "magnifyingglass"
        case "execute": "terminal"
        case "fetch": "globe"
        case "think": "bubble.left"
        default: "wrench.and.screwdriver"
        }
    }
}
