import Foundation
import Synchronization
import Testing
@testable import ACPProtocol
@testable import JSONRPC
@testable import TypoACP
@testable import TypoAssistant

/// An agent that can reattach sessions: `caps` is its `agentCapabilities`; `known` the sessions it can reattach.
/// It logs each request's method and the params of session/new, load and resume.
private final class ResumingAgent: @unchecked Sendable {
    let toAgent = Pipe(), toClient = Pipe()
    let peer: ACPConnection
    let client: ACPConnection
    let log = Mutex<[String]>([])
    let params = Mutex<[String: JSONValue]>([:])
    let prompts = Mutex<[String]>([])

    init(caps: JSONValue, known: Set<String> = ["old"], replay: [JSONValue] = []) {
        peer = ACPConnection(input: toAgent.fileHandleForReading, output: ACPPipeWriter(toClient.fileHandleForWriting))
        client = ACPConnection(input: toClient.fileHandleForReading, output: ACPPipeWriter(toAgent.fileHandleForWriting))
        let modes: JSONValue = ["currentModeId": "plan", "availableModes": [["id": "plan", "name": "Plan"], ["id": "default", "name": "Ask"]]]
        peer.start(handler: { [self] method, p in
            log.withLock { $0.append(method) }
            switch method {
            case "initialize": return .success(["protocolVersion": 1, "agentCapabilities": caps])
            case "session/new":
                params.withLock { $0[method] = p }
                return .success(["sessionId": "new1", "modes": modes])
            case "session/load", "session/resume":
                params.withLock { $0[method] = p }
                guard let id = p["sessionId"]?.string, known.contains(id) else { return .failure(ACPError(-32002, "Session not found")) }
                for u in replay { peer.notify("session/update", ["sessionId": .string(id), "update": u]) }
                return .success(["modes": modes])
            case "session/prompt":
                prompts.withLock { $0.append(p["prompt"]?.array?.first?["text"]?.string ?? "") }
                peer.notify("session/update", ["sessionId": p["sessionId"] ?? nil, "update": ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "new"]]])
                return .success(["stopReason": "end_turn"])
            default: return .success([:])
            }
        }, onNotification: { _, _ in })
    }

    func agent(host: (any ACPHost)? = nil, resume: String?) async throws -> ACPAgent {
        let a = ACPAgent(connection: client, process: nil, host: host)
        _ = try await a.connect(cwd: URL(fileURLWithPath: "/p"), mcp: "/typo-mcp", meta: ["claudeCode": ["options": [:]]], resume: resume)
        return a
    }

    /// The client's turn for a conversation with an earlier exchange, as `ACPClient.stream` sends it.
    func turn(_ a: ACPAgent) async throws -> [AssistantEvent] {
        let client = ACPClient(provider: AssistantProvider(preset: AssistantPreset.named("acp-claude")!), sessions: ACPSessions(), attachments: []) { a }
        var r = AssistantRequest(model: "", system: "", files: nil, messages: [.init(role: .user, text: "one"), .init(role: .assistant, text: "two"), .init(role: .user, text: "three")])
        r.session = "c"
        var events: [AssistantEvent] = []
        for try await e in client.stream(r) { events.append(e) }
        return events
    }
}

@MainActor private final class Host: ACPHost {
    var commands: [String] = []
    var options: [ACPSessionOptions] = []
    var tools: [String] = []
    func permission(for call: ACPToolCall, options: [ACPOption]) async -> String? { nil }
    func readTextFile(_ path: String) async throws -> String { "" }
    func writeTextFile(_ path: String, content: String) async throws {}
    func editStarted(_ call: ACPToolCall) async {}
    func editEnded(_ call: ACPToolCall, completed: Bool) async {}
    func commandsChanged(_ commands: [ACPCommand]) { self.commands = commands.map(\.name) }
    func optionsChanged(_ options: ACPSessionOptions) { self.options.append(options) }
    func toolCallChanged(_ call: ACPToolCall) { tools.append(call.id) }
}

@Suite(.timeLimit(.minutes(1))) struct ACPResumeTests {
    @Test func resumeWinsOverLoadAndNeedsTheCapability() {
        #expect(ACPAgent.reattachMethod(["agentCapabilities": ["loadSession": true, "sessionCapabilities": ["resume": [:]]]]) == "session/resume")
        #expect(ACPAgent.reattachMethod(["agentCapabilities": ["loadSession": true, "sessionCapabilities": ["resume": .null]]]) == "session/load")
        #expect(ACPAgent.reattachMethod(["agentCapabilities": ["loadSession": true]]) == "session/load")
        #expect(ACPAgent.reattachMethod(["agentCapabilities": ["loadSession": false, "sessionCapabilities": [:]]]) == nil)
        #expect(ACPAgent.reattachMethod([:]) == nil)
    }

    @Test func resumeReattachesWithTheNewSessionParamsAndSendsNoRecap() async throws {
        let fake = ResumingAgent(caps: ["loadSession": true, "sessionCapabilities": ["resume": [:]]])
        let a = try await fake.agent(resume: "old")
        #expect(fake.log.withLock { $0 } == ["initialize", "session/resume"])
        #expect(a.sessionID == "old" && a.resumed)
        let p = try #require(fake.params.withLock { $0["session/resume"] })
        #expect(p["sessionId"] == "old" && p["cwd"] == "/p" && p["_meta"] == ["claudeCode": ["options": [:]]])
        #expect(p["mcpServers"]?.array?.first?["command"] == "/typo-mcp")
        #expect(try await fake.turn(a) == [.text("new"), .done(.endTurn, nil)])
        #expect(fake.prompts.withLock { $0 } == ["three"])
    }

    @MainActor @Test func loadDropsTheReplayButKeepsCommandsAndModes() async throws {
        let replay: [JSONValue] = [
            ["sessionUpdate": "user_message_chunk", "content": ["type": "text", "text": "one"]],
            ["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "two"]],
            ["sessionUpdate": "tool_call", "toolCallId": "t1", "title": "Read", "status": "completed"],
            ["sessionUpdate": "available_commands_update", "availableCommands": [["name": "compact", "description": "Summarize"]]],
            ["sessionUpdate": "current_mode_update", "currentModeId": "default"],
        ]
        let host = Host()
        let fake = ResumingAgent(caps: ["loadSession": true], replay: replay)
        let a = try await fake.agent(host: host, resume: "old")
        #expect(fake.log.withLock { $0 } == ["initialize", "session/load"])
        #expect(try await fake.turn(a) == [.text("new"), .done(.endTurn, nil)])
        #expect(fake.prompts.withLock { $0 } == ["three"])
        for _ in 0..<100 where host.commands.isEmpty || host.options.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(host.commands == ["compact"])
        #expect(host.options.last?.modes?.current == "plan")    // the load's answer has the session's options
        #expect(host.tools.isEmpty)
    }

    @Test func aGoneSessionFallsBackToANewOneWithARecap() async throws {
        let fake = ResumingAgent(caps: ["loadSession": true, "sessionCapabilities": ["resume": [:]]])
        let a = try await fake.agent(resume: "gone")
        #expect(fake.log.withLock { $0 } == ["initialize", "session/resume", "session/new"])
        #expect(a.sessionID == "new1" && !a.resumed)
        _ = try await fake.turn(a)
        #expect(fake.prompts.withLock { $0 }.first?.hasPrefix("Earlier in this conversation:") == true)
    }

    @Test func withoutTheCapabilityOrAStoredIdASessionOpensAsBefore() async throws {
        let plain = ResumingAgent(caps: [:])
        #expect(try await plain.agent(resume: "old").sessionID == "new1")
        #expect(plain.log.withLock { $0 } == ["initialize", "session/new"])
        let fresh = ResumingAgent(caps: ["loadSession": true])
        _ = try await fresh.agent(resume: nil)
        #expect(fresh.log.withLock { $0 } == ["initialize", "session/new"])
    }
}
