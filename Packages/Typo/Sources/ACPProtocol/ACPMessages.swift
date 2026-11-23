import Foundation
import JSONRPC

/// What an agent asks of the app; the window's assistant answers.
@MainActor public protocol ACPHost: AnyObject, Sendable {
    /// The id of the option the user picked, or nil when the turn was stopped.
    func permission(for call: ACPToolCall, options: [ACPOption]) async -> String?
    /// The file's whole current text: the open buffer's when the file is open.
    func readTextFile(_ path: String) async throws -> String
    func writeTextFile(_ path: String, content: String) async throws
    /// An editing tool call named its files: the host notes their text before the agent's own tools rewrite them.
    func editStarted(_ call: ACPToolCall) async
    /// That call ended; `completed` is false when it failed. A call still running when the turn ends ends completed.
    func editEnded(_ call: ACPToolCall, completed: Bool) async
    /// The agent's slash commands, sent when the session starts and again whenever they change.
    func commandsChanged(_ commands: [ACPCommand])
    /// The session's modes and models, when it starts and whenever they change.
    func optionsChanged(_ options: ACPSessionOptions)
    /// A tool call of the running turn started or changed, for its live row.
    func toolCallChanged(_ call: ACPToolCall)
}

extension ACPHost {
    public func commandsChanged(_ commands: [ACPCommand]) {}
    public func optionsChanged(_ options: ACPSessionOptions) {}
    public func toolCallChanged(_ call: ACPToolCall) {}
}

public struct ACPOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// allow_once, allow_always, reject_once or reject_always.
    public let kind: String
    public init(id: String, name: String, kind: String) { self.id = id; self.name = name; self.kind = kind }
}

/// A tool call of the agent as far as the turn has seen it; updates replace the fields they carry.
public struct ACPToolCall: Sendable, Equatable {
    public var id: String
    public var title = ""
    public var kind: String?
    public var status: String?
    public var content: [JSONValue] = []
    public var rawInput: JSONValue?
    public var locations: [String] = []
    public init(id: String) { self.id = id }

    public var changesFiles: Bool { ["edit", "delete", "move"].contains(kind ?? "") }

    public mutating func merge(_ u: JSONValue) {
        if let t = u["title"]?.string { title = t }
        if let k = u["kind"]?.string { kind = k }
        if let s = u["status"]?.string { status = s }
        if let c = u["content"]?.array { content = c }
        if let r = u["rawInput"], r != .null { rawInput = r }
        if let l = u["locations"]?.array { locations = l.compactMap { $0["path"]?.string } }
    }
}

public struct ACPCommand: Sendable, Equatable, Identifiable {
    public var name: String
    public var description: String
    public var hint: String?
    public var id: String { name }

    public init(name: String, description: String, hint: String? = nil) {
        self.name = name
        self.description = description
        self.hint = hint
    }

    /// The commands of an `availableCommands` array; entries without a name are skipped.
    public static func list(_ v: JSONValue?) -> [ACPCommand] {
        (v?.array ?? []).compactMap { c in
            guard let name = c["name"]?.string else { return nil }
            return ACPCommand(name: name, description: c["description"]?.string ?? "", hint: c["input"]?["hint"]?.string)
        }
    }
}
