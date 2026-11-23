import Foundation
import TypoKit

extension ClientTool {
    /// The permission that gates the tool; nil for a tool that sends nothing off the Mac (the bundled Typst reference).
    public var permission: AssistantPermission? {
        switch self {
        case .readFile, .getOutline: .projectFiles
        case .listFiles, .searchProject: .searchProject
        case .getDiagnostics, .compile: .diagnostics
        case .viewPreview: .viewPreview
        case .typstDocs: nil
        }
    }

    /// The tools the small on-device model gets: its window leaves no room for more.
    public static let onDeviceTools: [ClientTool] = [.typstDocs, .getDiagnostics, .getOutline]
}

/// A call with its result, as the conversation keeps it (and the transcript shows it).
public struct ToolExchange: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var call: ToolCall
    /// Nil while the call has not been answered.
    public var result: String?
    public var isError = false
    public var id: String { call.id }
    public init(call: ToolCall, result: String? = nil, isError: Bool = false) { self.call = call; self.result = result; self.isError = isError }

    /// The compact transcript row: "Read kapitel.typ", "Searched for 'figure'".
    public var title: String {
        func name(_ p: String?) -> String { p.map { ($0 as NSString).lastPathComponent } ?? "a file" }
        switch call.tool {
        case .readFile?: return "Read \(name(call.string("path")))"
        case .getOutline?: return "Read the outline of \(name(call.string("path")))"
        case .searchProject?: return "Searched for '\(call.string("query") ?? "")'"
        case .listFiles?: return "Listed the project files"
        case .getDiagnostics?: return "Checked the compiler errors"
        case .typstDocs?: return "Looked up '\(call.string("query") ?? "")' in the Typst reference"
        case .viewPreview?: return call.page.map { "Viewed preview page \($0)" } ?? "Viewed the preview"
        case .compile?: return "Compiled the document"
        case nil: return call.string("title").flatMap { $0.isEmpty ? nil : $0 } ?? call.name    // an agent's call carries its title
        }
    }
}

public enum ToolDecision: Equatable, Sendable {
    case run
    /// The question for the user.
    case ask(String)
    case deny(String)
}

extension AssistantPermissions {
    /// What to do with `call`: files the user attached need no question, they went to the provider anyway.
    public func decide(_ call: ToolCall, attached: Set<String> = []) -> ToolDecision {
        guard let tool = call.tool else { return .deny("Unknown tool “\(call.name)”.") }
        guard let permission = tool.permission else { return .run }
        switch policy(permission) {
        case .allow: return .run
        case .never: return .deny("The user does not allow this: \(permission.title).")
        case .ask:
            let path = call.string("path")
            if let path, attached.contains(path) { return .run }
            switch tool {
            case .readFile: return .ask("May the assistant read \(path ?? "a file")?")
            case .getOutline: return .ask("May the assistant read the outline of \(path ?? "a file")?")
            case .searchProject: return .ask("May the assistant search the project for “\(call.string("query") ?? "")”?")
            case .listFiles: return .ask("May the assistant list the project files?")
            case .getDiagnostics: return .ask("May the assistant read the compiler errors?")
            case .compile: return .ask("May the assistant compile the document and read the compiler errors?")
            case .viewPreview: return .ask("May the assistant look at \(call.page.map { "page \($0)" } ?? "the page") of the preview? The image goes to the provider.")
            case .typstDocs: return .run
            }
        }
    }

    /// The tools to offer: those the user has not turned off.
    public var offeredTools: [ClientTool] { ClientTool.allCases.filter { $0.permission.map { policy($0) != .never } ?? true } }

    /// The tools this provider and model get: what they can call (function calling, vision for the preview) minus what is turned off.
    public func offered(provider: AssistantProvider, model: String) -> [ClientTool] {
        guard Self.supportsTools(provider: provider, model: model) else { return [] }
        let seesImages = Self.supportsVision(provider: provider, model: model)
        return offeredTools.filter { provider.isOnDevice ? ClientTool.onDeviceTools.contains($0) : ($0 != .viewPreview || seesImages) }
    }
}

/// The agent loop: stream an answer, run the tool calls it makes, send the results, continue.
@MainActor public enum AssistantAgent {
    public static let maxRounds = 8

    public enum Step: Equatable, Sendable {
        case stream(AssistantEvent)
        /// A new answer starts after tool results.
        case nextRound
        case result(ToolResult)
    }

    public static func run(client: any AssistantClient, request: AssistantRequest, maxRounds: Int = maxRounds,
                           execute: @escaping ToolRunner, emit: (Step) -> Void) async throws {
        var req = request
        func pass() async throws -> (text: String, calls: [ToolCall]) {
            var text = "", calls: [ToolCall] = []
            for try await e in client.stream(req, run: execute) {
                if case .text(let t) = e { text += t }
                if case .toolCall(let c) = e { calls.append(c) }
                if case .toolRan(let c, let r) = e {
                    emit(.stream(.toolCall(c)))
                    emit(.result(r))
                    continue
                }
                emit(.stream(e))
            }
            try Task.checkCancellation()
            return (text, calls)
        }
        for round in 0..<maxRounds {
            try Task.checkCancellation()
            if round > 0 { emit(.nextRound) }
            let (text, calls): (String, [ToolCall])
            do { (text, calls) = try await pass() } catch AssistantError.badRequest(_) where round == 0 && !req.clientTools.isEmpty {
                req.clientTools = []    // a server without function calling answers as it did before tools existed
                (text, calls) = try await pass()
            }
            guard !calls.isEmpty else { return }
            var results: [ToolResult] = []
            for c in calls {
                try Task.checkCancellation()
                let r = await execute(c)
                results.append(r)
                emit(.result(r))
            }
            req.messages.append(.init(role: .assistant, text: text, calls: calls))
            req.messages.append(.init(role: .user, text: "", results: results))
        }
        emit(.stream(.text("\n\n*Stopped after \(maxRounds) rounds of tool use.*")))
    }
}
