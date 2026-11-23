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
