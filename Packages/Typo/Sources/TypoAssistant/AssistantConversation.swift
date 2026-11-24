import CryptoKit
import Foundation
import TypoKit

public struct AssistantMessage: Codable, Identifiable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public enum EditState: String, Codable, Sendable { case accepted, rejected
        /// Applied, then taken back by Revert.
        case reverted
        /// Not applied: its search text was not found or ambiguous; `editFailures` says why.
        case failed
    }

    public var id = UUID()
    public var role: Role
    /// What the user typed, or the answer as it streamed.
    public var text: String
    /// User turns: the selection or diagnostics block sent before `text`, not shown in the transcript.
    public var context: String?
    public var reasoning: String?
    /// Shown inline instead of (or after) the text; such a turn is not sent back to the model.
    public var error: String?
    /// The answer stopped at the output limit.
    public var truncated = false
    /// Tools this answer called, with their results; nil in files saved before tools existed. A round of tool use
    /// ends an answer, and the next round is the next message.
    public var toolCalls: [ToolExchange]?
    /// Decisions on this answer's proposed edits, by their index in `AssistantEdits.parse(text)`.
    /// `.accepted` covers changes applied right away and changes accepted from a card.
    public var edits: [Int: EditState] = [:]
    /// Why an edit has the state `.failed`; nil in files saved before edits were applied automatically.
    public var editFailures: [Int: String]?
    /// Seconds from the question to the end of this answer; set on a turn's last answer.
    public var duration: TimeInterval?
    /// The user's thumbs up (true) or down on the answer; kept on this Mac only.
    public var feedback: Bool?
    /// When the user sent it; nil in files saved before.
    public var created: Date?
    /// User turns: the project paths "@"-mentioned in `text` by file name; nil in files saved before mentions.
    public var mentions: [String]?

    public init(role: Role, text: String, context: String? = nil) {
        self.role = role; self.text = text; self.context = context
    }
}

public struct AssistantConversation: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var title: String
    public var created: Date
    public var updated: Date
    public var messages: [AssistantMessage] = []
    public var providerID: UUID?
    public var model: String
    public var archived = false
    /// What this conversation changes about the global permissions; nil in files saved before permissions existed.
    public var permissions: AssistantPermissions?
    /// The agent mode picked in the prompt's mode menu; nil follows the "Change files" permission.
    public var agentMode: String?
    /// The agent's session id, which the next start of the agent reattaches; nil in files saved before.
    public var agentSession: String?

    public init(providerID: UUID?, model: String, now: Date = .now) {
        title = "New Conversation"
        created = now; updated = now
        self.providerID = providerID; self.model = model
    }

    /// First line of the first message, trimmed to about 50 characters at a word boundary.
    public static func title(from text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        guard !line.isEmpty else { return "New Conversation" }
        guard line.count > 50 else { return line }
        let cut = line.prefix(50)
        let word = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return word.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The turns to send: failed and refused answers dropped, consecutive user turns merged, so roles alternate.
    /// Without `context` the user turns carry only what was typed (the on-device window has no room for old passages).
    /// With `tools`, an answer's tool calls and their results are part of the turns; a call that never got its result
    /// (the user stopped it) is answered as cancelled, which the providers insist on.
    public func wireMessages(context: Bool = true, tools: Bool = false) -> [AssistantRequest.Message] {
        var out: [AssistantRequest.Message] = []
        func add(_ m: AssistantRequest.Message) {
            guard let last = out.last, last.role == m.role else { return out.append(m) }
            out[out.count - 1].text += last.text.isEmpty || m.text.isEmpty ? m.text : "\n\n" + m.text
            out[out.count - 1].calls += m.calls
            out[out.count - 1].results += m.results
        }
        for m in messages {
            let text = m.role == .user ? [context ? m.context : nil, m.text].compactMap { $0 }.joined(separator: "\n\n") : m.text
            let exchanges = tools && m.role == .assistant ? m.toolCalls ?? [] : []
            guard m.error == nil, !text.isEmpty || !exchanges.isEmpty else { continue }
            let role: AssistantRequest.Message.Role = m.role == .user ? .user : .assistant
            add(.init(role: role, text: text, calls: exchanges.map(\.call)))
            if !exchanges.isEmpty {
                add(.init(role: .user, text: "", results: exchanges.map { ToolResult(callID: $0.call.id, content: $0.result ?? "Cancelled before it ran.", isError: $0.result == nil || $0.isError) }))
            }
        }
        while out.first?.role == .assistant { out.removeFirst() }
        return out
    }
}

/// One JSON file per conversation in `Application Support/Tympan/Conversations/<project hash>/`.
public struct AssistantConversationStore: Sendable {
    /// nil keeps nothing (tests that do not test storage).
    public var folder: URL?
    public init(folder: URL?) { self.folder = folder }

    public static func folder(for root: URL) -> URL {
        let key = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return URL.applicationSupportDirectory.appending(path: "Tympan/Conversations/\(key)")
    }

    static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }()
    static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    /// Newest first; unreadable files are skipped.
    public func loadAll() -> [AssistantConversation] {
        guard let folder, let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(AssistantConversation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updated > $1.updated }
    }

    public func save(_ c: AssistantConversation) throws {
        guard let folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(c).write(to: url(c.id, folder), options: .atomic)
    }

    public func delete(_ id: UUID) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: url(id, folder))
    }

    private func url(_ id: UUID, _ folder: URL) -> URL { folder.appending(path: id.uuidString + ".json") }
}
