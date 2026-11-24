import Foundation
import Synchronization
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import ACPProtocol
@testable import JSONRPC
@testable import TypoACP
@testable import TypoAssistant
@testable import TypstEngine

final class Collected<T: Sendable>: Sendable {
    let items = Mutex<[T]>([])
    func add(_ x: T) { items.withLock { $0.append(x) } }
    var all: [T] { items.withLock { $0 } }
}

/// Waits until `condition` holds, for up to five seconds.
func eventually(isolation: isolated (any Actor)? = #isolation, _ condition: () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

/// An agent on the other ends of two pipes: an `ACPConnection` whose handler answers like an agent.
final class FakeAgent: @unchecked Sendable {
    let toAgent = Pipe(), toClient = Pipe()
    let peer: ACPConnection
    let peerOutput: ACPPipeWriter
    let clientConnection: ACPConnection
    let notes = Collected<String>()
    /// The `mcpServers` of each session/new, as JSON.
    let mcpServers = Collected<String>()
    /// The `_meta` of each session/new, as JSON ("null" without one).
    let metas = Collected<String>()
    let promptHandler: @Sendable (ACPConnection, JSONValue) async -> JSONValue

    /// A prompt result with "errorCode" answers with that error instead.
    init(modes: [String] = [], prompt: @escaping @Sendable (ACPConnection, JSONValue) async -> JSONValue = { _, _ in ["stopReason": "end_turn"] }) {
        promptHandler = prompt
        peerOutput = ACPPipeWriter(toClient.fileHandleForWriting)
        peer = ACPConnection(input: toAgent.fileHandleForReading, output: peerOutput)
        clientConnection = ACPConnection(input: toClient.fileHandleForReading, output: ACPPipeWriter(toAgent.fileHandleForWriting))
        peer.start(handler: { [self] method, params in
            switch method {
            case "initialize": return .success(["protocolVersion": 1, "agentInfo": ["name": "fake", "version": "1.0"]])
            case "session/new":
                mcpServers.add(String(decoding: (params["mcpServers"] ?? nil).json, as: UTF8.self))
                metas.add(String(decoding: (params["_meta"] ?? nil).json, as: UTF8.self))
                return .success(["sessionId": "s1", "modes": ["currentModeId": "default", "availableModes": .array(modes.map { ["id": .string($0), "name": .string($0)] })]])
            case "session/set_mode":
                notes.add("set_mode:" + (params["modeId"]?.string ?? ""))
                return .success([:])
            case "session/prompt":
                let r = await promptHandler(peer, params)
                if let code = r["errorCode"]?.int { return .failure(ACPError(code, "Log in again.")) }
                return .success(r)
            case let m where m.hasPrefix("echo/"): return .success(["n": params["n"] ?? nil])
            default: return .failure(ACPError(ACPError.methodNotFound, method))
            }
        }, onNotification: { [self] method, _ in notes.add(method) })
    }

    func agent(host: (any ACPHost)?) async throws -> ACPAgent {
        let a = ACPAgent(connection: clientConnection, process: nil, host: host)
        _ = try await a.connect(cwd: URL(fileURLWithPath: "/p"))
        return a
    }

    func hangUp() { peerOutput.close() }
}

@MainActor private final class FakeHost: ACPHost {
    var files: [String: String] = [:]
    var writes: [String] = []
    var asked: [ACPToolCall] = []
    /// nil: the user never answers.
    var answer: (([ACPOption]) -> String?)?

    func permission(for call: ACPToolCall, options: [ACPOption]) async -> String? {
        asked.append(call)
        if let answer { return answer(options) }
        try? await Task.sleep(for: .seconds(30))
        return "late"
    }

    func readTextFile(_ path: String) async throws -> String {
        guard let t = files[path] else { throw ACPError(ACPError.notFound, "No file \(path).") }
        return t
    }

    func writeTextFile(_ path: String, content: String) async throws { writes.append("\(path)=\(content)") }

    var edits: [String] = []
    func editStarted(_ call: ACPToolCall) async {
        try? await Task.sleep(for: .milliseconds(20))    // a slow snapshot must still come before the call's end
        edits.append("start \(call.id) \(call.paths.joined(separator: ","))")
    }
    func editEnded(_ call: ACPToolCall, completed: Bool) async { edits.append("end \(call.id) \(completed)") }

    var commands: [ACPCommand] = []
    func commandsChanged(_ commands: [ACPCommand]) { self.commands = commands }
}

private func update(_ u: JSONValue) -> JSONValue { ["sessionId": "s1", "update": u] }

@Suite(.timeLimit(.minutes(1))) struct ACPAgentTests {
    @Test func sessionGetsTypoMCPServerOnlyWhenBundled() async throws {
        let fake = FakeAgent()
        let a = ACPAgent(connection: fake.clientConnection, process: nil, host: nil)
        _ = try await a.connect(cwd: URL(fileURLWithPath: "/p"), mcp: "/A.app/Contents/MacOS/typo-mcp")
        #expect(fake.mcpServers.all == [#"[{"args":["--project","/p"],"command":"/A.app/Contents/MacOS/typo-mcp","env":[],"name":"typo"}]"#])
        let bare = FakeAgent()
        _ = try await bare.agent(host: nil)
        #expect(bare.mcpServers.all == ["[]"])
    }

    @Test func sessionCarriesClaudeCodePluginsOnlyWhenGiven() async throws {
        let fake = FakeAgent()
        let a = ACPAgent(connection: fake.clientConnection, process: nil, host: nil)
        let meta = ACPAgent.claudeCodeMeta(plugins: [URL(fileURLWithPath: "/c/typo"), URL(fileURLWithPath: "/c/typo-user")])
        _ = try await a.connect(cwd: URL(fileURLWithPath: "/p"), meta: meta)
        #expect(fake.metas.all == [#"{"claudeCode":{"options":{"plugins":[{"path":"/c/typo","type":"local"},{"path":"/c/typo-user","type":"local"}]}}}"#])
        #expect(ACPAgent.claudeCodeMeta(plugins: []) == nil)
        let bare = FakeAgent()
        _ = try await bare.agent(host: nil)
        #expect(bare.metas.all == ["null"])
    }

    @MainActor @Test func aTurnStreamsTextToolsAndFileAccess() async throws {
        let host = FakeHost()
        host.files["/p/a.typ"] = "one\ntwo\nthree"
        host.answer = { options in options.first { $0.kind == "allow_once" }?.id }
        let reads = Collected<String>(), outcomes = Collected<String>()
        let fake = FakeAgent { peer, params in
            peer.notify("session/update", update(["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "Hel"]]))
            peer.notify("session/update", update(["sessionUpdate": "agent_thought_chunk", "content": ["type": "text", "text": "hmm"]]))
            peer.notify("session/update", update(["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "lo"]]))
            peer.notify("session/update", update(["sessionUpdate": "tool_call", "toolCallId": "t1", "title": "Read a.typ", "kind": "read", "status": "pending"]))
            let r = try? await peer.request("fs/read_text_file", ["sessionId": "s1", "path": "/p/a.typ", "line": 2, "limit": 1])
            reads.add(r?["content"]?.string ?? "error")
            peer.notify("session/update", update(["sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed",
                                                  "content": [["type": "content", "content": ["type": "text", "text": "two"]]]]))
            peer.notify("session/update", update(["sessionUpdate": "tool_call", "toolCallId": "t2", "title": "Edit a.typ", "kind": "edit", "status": "pending",
                                                  "content": [["type": "diff", "path": "/p/a.typ", "oldText": "two", "newText": "2"]]]))
            let p = try? await peer.request("session/request_permission", ["sessionId": "s1", "toolCall": ["toolCallId": "t2"], "options": [
                ["optionId": "yes", "name": "Allow", "kind": "allow_once"], ["optionId": "no", "name": "Reject", "kind": "reject_once"]]])
            outcomes.add(p?["outcome"]?["optionId"]?.string ?? "none")
            _ = try? await peer.request("fs/write_text_file", ["sessionId": "s1", "path": "/p/a.typ", "content": "one\n2\nthree"])
            let missing = try? await peer.request("fs/read_text_file", ["sessionId": "s1", "path": "/p/none.typ"])
            reads.add(missing == nil ? "missing" : "found")
            #expect(params["prompt"]?.array?.first?["text"]?.string == "hi")
            return ["stopReason": "end_turn"]
        }
        let agent = try await fake.agent(host: host)
        let events = Collected<AssistantEvent>()
        let reason = try await agent.prompt([["type": "text", "text": "hi"]]) { $0.forEach(events.add) }
        #expect(reason == .endTurn)
        #expect(reads.all == ["two", "missing"])
        #expect(outcomes.all == ["yes"])
        #expect(host.writes == ["/p/a.typ=one\n2\nthree"])
        #expect(host.asked.first?.title == "Edit a.typ")
        #expect(host.asked.first?.diffs == [ProposedEdit(path: "/p/a.typ", search: "two", replace: "2")])
        let all = events.all
        #expect(Array(all.prefix(3)) == [.text("Hel"), .reasoning("hmm"), .text("lo")])
        #expect(!all.contains { if case .toolCall = $0 { true } else { false } })
        let ran = all.compactMap { e -> (ToolCall, ToolResult)? in if case .toolRan(let c, let r) = e { (c, r) } else { nil } }
        #expect(ran.map(\.0.id) == ["t1", "t2"])
        #expect(ToolExchange(call: ran[0].0).title == "Read a.typ")
        #expect(ran[0].1.content == "two")
        #expect(ran[1].1.content == "Changed /p/a.typ")
    }

    @MainActor @Test func cancelSendsCancelAndAnswersThePendingPermission() async throws {
        let host = FakeHost()
        let outcomes = Collected<String>()
        let fake = FakeAgent { peer, _ in
            peer.notify("session/update", update(["sessionUpdate": "tool_call", "toolCallId": "t1", "title": "Run tests", "kind": "execute"]))
            let p = try? await peer.request("session/request_permission", ["sessionId": "s1", "toolCall": ["toolCallId": "t1"],
                                                                           "options": [["optionId": "yes", "name": "Allow", "kind": "allow_once"]]])
            outcomes.add(p?["outcome"]?["outcome"]?.string ?? "none")
            return ["stopReason": "cancelled"]
        }
        let agent = try await fake.agent(host: host)
        let turn = Task { try await agent.prompt([["type": "text", "text": "go"]]) { _ in } }
        #expect(await eventually { host.asked.count == 1 })
        turn.cancel()
        #expect(try await turn.value == .other("cancelled"))
        #expect(outcomes.all == ["cancelled"])
        #expect(await eventually { fake.notes.all.contains("session/cancel") })
    }

    @Test func turnMergesToolCallUpdates() {
        var t = ACPTurn()
        #expect(t.apply(["sessionUpdate": "tool_call", "toolCallId": "a", "title": "Search", "kind": "search", "status": "in_progress",
                         "content": [["type": "content", "content": ["type": "text", "text": "old"]]]]) == [])
        #expect(t.apply(["sessionUpdate": "available_commands_update", "availableCommands": []]) == [])
        let done = t.apply(["sessionUpdate": "tool_call_update", "toolCallId": "a", "status": "failed",
                            "content": [["type": "content", "content": ["type": "text", "text": "new"]]]])
        guard case .toolRan(let call, let result)? = done.first else { Issue.record("no event"); return }
        #expect(call.name == "search")
        #expect(call.string("title") == "Search")
        #expect(result == ToolResult(callID: "a", content: "new", isError: true))
        #expect(t.apply(["sessionUpdate": "tool_call_update", "toolCallId": "a", "status": "failed"]) == [])
        #expect(t.finish() == [])
    }

    @Test func sliceTakesLinesFromALine() {
        #expect(ACPAgent.slice("a\nb\nc\nd", line: 2, limit: 2) == "b\nc")
        #expect(ACPAgent.slice("a\nb", line: nil, limit: nil) == "a\nb")
        #expect(ACPAgent.slice("a\nb\nc", line: 3, limit: nil) == "c")
    }

    @Test func sessionsRestartADeadAgentWithARecap() async throws {
        let fakes = Collected<FakeAgent>()
        let sessions = ACPSessions()
        let start: @Sendable () async throws -> ACPAgent = {
            let f = FakeAgent()
            fakes.add(f)
            return try await f.agent(host: nil)
        }
        let first = try await sessions.agent(for: "c", command: "x", start: start)
        let again = try await sessions.agent(for: "c", command: "x", start: start)
        #expect(first.fresh && !again.fresh && first.agent === again.agent)
        fakes.all[0].hangUp()
        #expect(await eventually { !first.agent.isAlive })
        let restarted = try await sessions.agent(for: "c", command: "x", start: start)
        #expect(restarted.fresh && restarted.agent !== first.agent)
        let changed = try await sessions.agent(for: "c", command: "y", start: start)
        #expect(changed.fresh && fakes.all.count == 3)

        let r = AssistantRequest(model: "", system: "S", files: nil, messages: [.init(role: .user, text: "one"), .init(role: .assistant, text: "two"), .init(role: .user, text: "three")])
        let blocks = ACPClient.prompt(r, fresh: true, attachments: [URL(fileURLWithPath: "/p/a.typ")])
        #expect(blocks[0]["text"]?.string == "Earlier in this conversation:\n\nUser: one\n\nAssistant: two\n\nNow:\nthree")
        #expect(blocks[1] == ["type": "resource_link", "uri": "file:///p/a.typ", "name": "a.typ"])
        #expect(ACPClient.prompt(r, fresh: false, attachments: [])[0]["text"]?.string == "three")
        let command = AssistantRequest(model: "", system: "S", files: nil, messages: [.init(role: .user, text: "one"), .init(role: .user, text: "/compact")])
        #expect(ACPClient.prompt(command, fresh: true, attachments: [])[0]["text"]?.string == "/compact")
    }

    @MainActor @Test func commandsReachTheHostOutsideATurn() async throws {
        let host = FakeHost()
        let fake = FakeAgent()
        let agent = try await fake.agent(host: host)
        fake.peer.notify("session/update", update(["sessionUpdate": "available_commands_update", "availableCommands": [
            ["name": "compact", "description": "Summarize"], ["name": "translate", "description": "Translate", "input": ["hint": "language"]]]]))
        #expect(await eventually { host.commands.map(\.name) == ["compact", "translate"] })
        #expect(host.commands.last?.hint == "language")
        withExtendedLifetime(agent) {}
    }

    @Test func clientStreamsTheTurnAndMapsErrors() async throws {
        var p = AssistantProvider(preset: AssistantPreset.named("acp-claude")!)
        p.command = "npx agent"
        let client = ACPClient(provider: p, sessions: ACPSessions(), attachments: []) {
            try await FakeAgent { peer, _ in
                peer.notify("session/update", update(["sessionUpdate": "agent_message_chunk", "content": ["type": "text", "text": "Hi"]]))
                return ["stopReason": "max_turn_requests"]
            }.agent(host: nil)
        }
        var r = AssistantRequest(model: "", system: "", files: nil, messages: [.init(role: .user, text: "q")])
        r.session = "c1"
        var events: [AssistantEvent] = []
        for try await e in client.stream(r) { events.append(e) }
        #expect(events == [.text("Hi"), .done(.maxTokens, nil)])
        #expect(ACPClient.failure(ACPError(ACPError.authRequired, "auth"), preset: p.preset) as? AssistantError == .agent(p.preset.loginHint!))
    }
}

@Suite(.timeLimit(.minutes(1))) struct ACPProcessTests {
    @Test func runReportsExitStatusOutputAndTimeout() {
        let r = ACPProcess.run("/bin/sh", arguments: ["-c", "echo out; echo err >&2; exit 3"], environment: [:], timeout: 5)
        #expect(r?.status == 3 && r?.output == "out\n")
        #expect(ACPProcess.run("/bin/sleep", arguments: ["5"], environment: [:], timeout: 0.2)?.status == nil)
    }

    @Test func shutdownEndsTheWholeProcessGroup() async throws {
        let p = try ACPProcess(executable: "/bin/sh", arguments: ["-c", "sleep 100 & sleep 100"], environment: ["PATH": "/bin:/usr/bin"],
                               cwd: FileManager.default.temporaryDirectory)
        #expect(await eventually { kill(-p.pid, 0) == 0 })
        try await Task.sleep(for: .milliseconds(100))    // both sleeps started
        p.shutdown()
        #expect(await eventually { kill(-p.pid, 0) == -1 && errno == ESRCH })
    }

    @Test func quitEndsAGroupAnotherThreadIsStopping() async throws {
        let p = try ACPProcess(executable: "/bin/sh", arguments: ["-c", "sleep 100 & sleep 100"], environment: ["PATH": "/bin:/usr/bin"],
                               cwd: FileManager.default.temporaryDirectory)
        try await Task.sleep(for: .milliseconds(100))
        Thread { p.shutdown() }.start()
        try await Task.sleep(for: .milliseconds(50))
        ACPProcess.shutdownAll()
        #expect(kill(-p.pid, 0) == -1 && errno == ESRCH)
    }

    @Test func pathComesFromTheMarkedLineOfANoisyShell() {
        let script = "echo 'Welcome!'; echo PATH=/wrong; (sleep 30) & printf '\\n\(ACPProcess.marker)%s\\n' /a/bin:/b/bin; echo bye; echo err >&2"
        let start = Date()
        #expect(ACPProcess.loginPATH(shell: "/bin/sh", arguments: ["-c", script]) == "/a/bin:/b/bin")
        #expect(Date().timeIntervalSince(start) < 4)
        #expect(ACPProcess.loginPATH(shell: "/bin/sh", arguments: ["-c", "echo nothing"]) == nil)
    }

    @Test func commandLineWordsAndLookup() {
        #expect(ACPProcess.words("npx -y @agentclientprotocol/claude-agent-acp") == ["npx", "-y", "@agentclientprotocol/claude-agent-acp"])
        #expect(ACPProcess.words("\"/Applications/My Agent/agent\" --acp 'a b' ''") == ["/Applications/My Agent/agent", "--acp", "a b", ""])
        #expect(ACPProcess.locate("sh", path: "/nonexistent:/bin") == "/bin/sh")
        #expect(ACPProcess.locate("no-such-agent", path: "/bin:/usr/bin") == nil)
        #expect(ACPProcess.locate("/bin/sh", path: "") == "/bin/sh")
    }
}

@Suite struct ACPCommandLineTests {
    func call(_ kind: String, title: String = "", input: JSONValue? = nil) -> ACPToolCall {
        var c = ACPToolCall(id: "t"); c.kind = kind; c.title = title; c.rawInput = input; return c
    }

    @Test func commandComesFromRawInputThenTitle() {
        #expect(call("execute", title: "`ls`", input: ["command": "cat main.typ", "description": "Show it"]).commandLine == "cat main.typ")
        #expect(AgentAccess(commands: ["cat"]).rules(for: call("execute", input: ["command": ["bash", "-lc", "cat 'a b'"]]).commandLine) == ["cat"])
        #expect(AgentAccess.split(call("execute", input: ["command": ["rm", "-rf", "x; y"]]).commandLine!) == [["rm", "-rf", "x; y"]])
        #expect(call("execute", title: "`cat main.typ`").commandLine == "cat main.typ")
        #expect(call("execute", title: "cat main.typ").commandLine == "cat main.typ")
        #expect(call("execute").commandLine == nil)
        #expect(call("execute", input: ["command": [1]]).commandLine == nil)
        #expect(call("read", title: "`cat x`").commandLine == nil)
    }
}

@Suite struct ACPFilesTests {
    @Test func replacementKeepsTheCommonStartAndEnd() {
        let r = ACPFiles.replacement(old: "one\ntwo\nthree", new: "one\n2\nthree")
        #expect(r == Replacement(range: NSRange(location: 4, length: 3), text: "2"))
        #expect(ACPFiles.replacement(old: "same", new: "same") == nil)
        // Lines inserted before a line sharing their first character: the change covers just the new lines.
        #expect(ACPFiles.replacement(old: "#a\n#b\n", new: "#a\n#x\n#y\n#b\n") == Replacement(range: NSRange(location: 3, length: 0), text: "#x\n#y\n"))
        #expect(ACPFiles.replacement(old: "b\n", new: "a\nb\n") == Replacement(range: NSRange(location: 0, length: 0), text: "a\n"))
        #expect(ACPFiles.replacement(old: "", new: "new") == Replacement(range: NSRange(location: 0, length: 0), text: "new"))
        #expect(ACPFiles.replacement(old: "aaa", new: "aa") == Replacement(range: NSRange(location: 2, length: 1), text: ""))
        // 😀 and 😃 share their lead surrogate: the pair is replaced whole.
        #expect(ACPFiles.replacement(old: "x😀y", new: "x😃y") == Replacement(range: NSRange(location: 1, length: 2), text: "😃"))
    }

    @Test func editShowsWholeLinesAndParsesBack() {
        let old = "= Title\nSome text here.\nEnd\n"
        let r = ACPFiles.replacement(old: old, new: "= Title\nSome better text here.\nEnd\n")!
        let e = ACPFiles.edit(path: "a.typ", old: old, r)
        #expect(e == ProposedEdit(path: "a.typ", search: "Some text here.", replace: "Some better text here."))
        #expect(AssistantEdits.parse("Done.\n\n" + ACPFiles.block(e) + "\n\nMore.") == [e])
        let created = ProposedEdit(path: "new.typ", search: "", replace: "Hello")
        #expect(AssistantEdits.parse(ACPFiles.block(created)) == [created])
    }

    @Test func projectPathStaysInsideTheRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/acp-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ACPFiles.projectPath("/private" + root.path + "/ch/new.typ", root: root)?.raw == "ch/new.typ")
        #expect(ACPFiles.projectPath(root.path + "/a.typ", root: URL(fileURLWithPath: "/private" + root.path))?.raw == "a.typ")
        #expect(ACPFiles.projectPath(root.path + "/../x.typ", root: root) == nil)
        #expect(ACPFiles.projectPath(root.path + "-other/a.typ", root: root) == nil)
        #expect(ACPFiles.projectPath(root.path, root: root) == nil)
    }
}


@Suite(.timeLimit(.minutes(1))) struct ACPAgentEditTests {
    @MainActor @Test func editCallsStartWhenTheyNameFilesAndEndWithTheirStatusOrTheTurn() async throws {
        let host = FakeHost()
        let fake = FakeAgent { peer, _ in
            func send(_ u: JSONValue) { peer.notify("session/update", update(u)) }
            send(["sessionUpdate": "tool_call", "toolCallId": "w", "title": "Preparing file…", "kind": "edit", "status": "pending", "locations": []])
            send(["sessionUpdate": "tool_call_update", "toolCallId": "w", "locations": [["path": "/p/new.typ"]]])
            send(["sessionUpdate": "tool_call_update", "toolCallId": "w", "locations": [["path": "/p/new.typ"]]])
            send(["sessionUpdate": "tool_call_update", "toolCallId": "w", "status": "completed"])
            send(["sessionUpdate": "tool_call", "toolCallId": "r", "title": "Read a.typ", "kind": "read", "status": "pending", "locations": [["path": "/p/a.typ"]]])
            send(["sessionUpdate": "tool_call", "toolCallId": "f", "kind": "edit", "status": "in_progress", "locations": [["path": "/p/b.typ"]]])
            send(["sessionUpdate": "tool_call_update", "toolCallId": "f", "status": "failed"])
            send(["sessionUpdate": "tool_call", "toolCallId": "e", "kind": "other", "status": "pending",
                  "content": [["type": "diff", "path": "/p/a.typ", "oldText": "two", "newText": "2"]], "locations": [["path": "/p/a.typ"]]])
            _ = try? await peer.request("session/request_permission", ["sessionId": "s1", "options": [["optionId": "yes", "name": "Allow", "kind": "allow_once"]],
                                                                       "toolCall": ["toolCallId": "q", "kind": "edit", "locations": [["path": "/p/c.typ"]]]])
            send(["sessionUpdate": "tool_call_update", "toolCallId": "q", "status": "completed"])
            return ["stopReason": "end_turn"]
        }
        host.answer = { $0.first?.id }
        let agent = try await fake.agent(host: host)
        _ = try await agent.prompt([["type": "text", "text": "go"]]) { _ in }
        // Settled before the turn returns; "e" never finished, so the turn's end completes it.
        #expect(host.edits == ["start w /p/new.typ", "end w true", "start f /p/b.typ", "end f false", "start e /p/a.typ",
                              "start q /p/c.typ", "end q true", "end e true"])
    }

    @Test func permissionMapsOntoTheAgentsOfferedModes() async throws {
        #expect([PermissionPolicy.ask, .allow, .never].map(ACPAgent.mode(for:)) == ["default", "acceptEdits", "plan"])
        let offering = FakeAgent(modes: ["default", "acceptEdits", "plan", "bypassPermissions"])
        let a = try await offering.agent(host: nil)
        await a.apply(.allow)
        await a.apply(.never)
        #expect(offering.notes.all == ["set_mode:acceptEdits", "set_mode:plan"])
        let other = FakeAgent(modes: ["code", "architect"])
        await (try await other.agent(host: nil)).apply(.ask)
        #expect(other.notes.all.isEmpty)
    }

    @Test func clientSetsTheModeEachTurnAndRestartsAfterALoginError() async throws {
        var p = AssistantProvider(preset: AssistantPreset.named("acp-claude")!)
        p.command = "npx agent"
        let fakes = Collected<FakeAgent>()
        let client = ACPClient(provider: p, sessions: ACPSessions(), attachments: [], changeFiles: .allow) {
            let first = fakes.all.isEmpty
            let f = FakeAgent(modes: ["default", "acceptEdits"]) { _, _ in first ? ["errorCode": .int(ACPError.authRequired)] : ["stopReason": "end_turn"] }
            fakes.add(f)
            return try await f.agent(host: nil)
        }
        var r = AssistantRequest(model: "", system: "", files: nil, messages: [.init(role: .user, text: "q")])
        r.session = "c1"
        await #expect(throws: AssistantError.agent(p.preset.loginHint!)) { for try await _ in client.stream(r) {} }
        var events: [AssistantEvent] = []
        for try await e in client.stream(r) { events.append(e) }
        #expect(events == [.done(.endTurn, nil)])
        #expect(fakes.all.count == 2)
        #expect(fakes.all.map(\.notes.all) == [["set_mode:acceptEdits"], ["set_mode:acceptEdits"]])
    }
}

@Suite(.timeLimit(.minutes(1))) @MainActor struct AgentWriteTests {
    let a = RelPath("a.typ")!

    @Test func aHeldWriteLandsAsOneCleanRevertableAgentEdit() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "x", "a.typ": "one\ntwo\nthree\n"])
        let s = try #require(await p.holdForAgent(a))
        #expect(s.text == "one\ntwo\nthree\n")
        try "one\n2\nthree\n".write(to: root.appending(path: "a.typ"), atomically: true, encoding: .utf8)
        await p.reloadChangedFiles()
        let b = try #require(p.buffer(for: a))
        #expect(b.storage.string == "one\ntwo\nthree\n")    // held: no reload
        let adopted = try #require(await p.adoptAgentWrite(s, actionName: "Agent Edit"))
        #expect(adopted.edit == ProposedEdit(path: "a.typ", search: "two", replace: "2"))
        #expect(b.storage.string == "one\n2\nthree\n" && !b.isDirty && p.changedOnDisk.isEmpty && !p.hasUnsavedChanges)
        #expect(b.undoManager.undoActionName == "Agent Edit")
        let id = try #require(adopted.changeID)
        #expect(b.canRevert(id))
        await p.reloadChangedFiles()
        #expect(b.storage.string == "one\n2\nthree\n" && !b.isDirty && p.changedOnDisk.isEmpty)
        #expect(p.reloadHolds.isEmpty)
    }

    @Test func unsavedTextIsNotHeldAndBecomesAConflict() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "x", "a.typ": "one\n"])
        let b = try await p.open(a)
        b.apply([Replacement(range: NSRange(location: 0, length: 0), text: "mine ")])
        #expect(await p.holdForAgent(a) == nil)
        #expect(p.reloadHolds.isEmpty)
        try "agent\n".write(to: root.appending(path: "a.typ"), atomically: true, encoding: .utf8)
        await p.reloadChangedFiles()
        #expect(p.changedOnDisk == [a] && b.storage.string == "mine one\n")
    }

    @Test func typingDuringTheCallKeepsBothTexts() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "x", "a.typ": "one\n"])
        let s = try #require(await p.holdForAgent(a))
        let b = try #require(p.buffer(for: a))
        b.apply([Replacement(range: NSRange(location: 0, length: 0), text: "mine ")])
        try "agent\n".write(to: root.appending(path: "a.typ"), atomically: true, encoding: .utf8)
        try await p.saveAll()
        #expect(try String(contentsOf: root.appending(path: "a.typ"), encoding: .utf8) == "agent\n")    // the held save waits
        #expect(await p.adoptAgentWrite(s, actionName: "Agent Edit") == nil)
        #expect(p.changedOnDisk == [a] && b.storage.string == "mine one\n" && p.reloadHolds.isEmpty)
    }

    @Test func aNewFileIsMarkedWholeAndHoldsAreCounted() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "x", "a.typ": "one\n"])
        let n = RelPath("ch/new.typ")!
        let created = try #require(await p.holdForAgent(n))
        #expect(created.text == nil)
        try FileManager.default.createDirectory(at: root.appending(path: "ch"), withIntermediateDirectories: true)
        try "= New\n".write(to: root.appending(path: "ch/new.typ"), atomically: true, encoding: .utf8)
        let adopted = try #require(await p.adoptAgentWrite(created, actionName: "Agent Edit"))
        #expect(adopted.edit == ProposedEdit(path: "ch/new.typ", search: "", replace: "= New\n"))
        let nb = try #require(p.buffer(for: n))
        let id = try #require(adopted.changeID)
        #expect(nb.storage.string == "= New\n" && !nb.isDirty && nb.canRevert(id))
        #expect(p.allFiles.contains(n))

        let first = try #require(await p.holdForAgent(a)), second = try #require(await p.holdForAgent(a))
        try "two\n".write(to: root.appending(path: "a.typ"), atomically: true, encoding: .utf8)
        await p.releaseAgentHold(first)
        #expect(p.buffer(for: a)?.storage.string == "one\n")    // the other call still holds it
        await p.releaseAgentHold(second)
        #expect(p.buffer(for: a)?.storage.string == "two\n" && p.reloadHolds.isEmpty)
    }
}
