import Foundation
import Synchronization
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypoAssistant
@testable import TypstEngine

private func body(_ r: URLRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: Any]) ?? [:] }
private func collect(_ s: AsyncThrowingStream<AssistantEvent, Error>) async throws -> [AssistantEvent] {
    var out: [AssistantEvent] = []
    for try await e in s { out.append(e) }
    return out
}
private func provider(_ id: String) -> AssistantProvider {
    var p = AssistantProvider(preset: AssistantPreset.named(id)!, baseURL: nil, keyHeader: "Authorization")
    p.model = "m"
    return p
}
private let call = ToolCall(id: "c1", name: "read_file", arguments: "{\"path\":\"a.typ\"}")
private func toolRequest() -> AssistantRequest {
    var r = AssistantRequest(model: "claude-x", system: "S", files: nil, messages: [
        .init(role: .user, text: "look"),
        .init(role: .assistant, text: "", calls: [call]),
        .init(role: .user, text: "", results: [ToolResult(callID: "c1", content: "TEXT")]),
    ])
    r.clientTools = [.readFile]
    return r
}

@Suite struct ToolWireTests {
    @Test func anthropicStreamsAToolUseBlock() async throws {
        let stub = StubTransport(chunks: [
            "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":3}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Reading\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"read_file\",\"input\":{}}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"pa\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"th\\\":\\\"a.typ\\\"}\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":1}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":9}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n",
        ])
        let events = try await collect(AssistantClients.make(provider("anthropic"), key: "k", transport: stub.transport).stream(toolRequest()))
        #expect(events.contains(.toolCall(ToolCall(id: "toolu_1", name: "read_file", arguments: "{\"path\":\"a.typ\"}"))))
        #expect(events.last == .done(.toolUse, AssistantUsage(input: 3, output: 9)))
    }

    @Test func anthropicRequestCarriesToolsCallsAndResults() throws {
        let req = try AnthropicClient(provider: provider("anthropic"), key: "k", transport: StubTransport(chunks: []).transport).urlRequest(toolRequest())
        let b = body(req)
        let tools = b["tools"] as? [[String: Any]]
        #expect(tools?.first?["name"] as? String == "read_file")
        #expect((tools?.first?["input_schema"] as? [String: Any])?["required"] as? [String] == ["path"])
        let messages = b["messages"] as? [[String: Any]] ?? []
        let use = (messages[1]["content"] as? [[String: Any]])?.first
        #expect(use?["type"] as? String == "tool_use" && use?["id"] as? String == "c1" && (use?["input"] as? [String: Any])?["path"] as? String == "a.typ")
        let result = (messages[2]["content"] as? [[String: Any]])?.first
        #expect(result?["type"] as? String == "tool_result" && result?["tool_use_id"] as? String == "c1" && result?["content"] as? String == "TEXT")
        #expect((messages[1]["content"] as? [[String: Any]])?.count == 1, "no empty text block next to the call")
    }

    @Test func chatCompletionsAssemblesToolCallDeltas() async throws {
        let stub = StubTransport(chunks: [
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_9\",\"function\":{\"name\":\"search_project\",\"arguments\":\"\"}}]}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"query\\\":\"}}]}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"fig\\\"}\"}}]}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
            "data: [DONE]\n\n",
        ])
        let events = try await collect(AssistantClients.make(provider("openai"), key: "k", transport: stub.transport).stream(toolRequest()))
        #expect(events.filter { if case .toolCall = $0 { true } else { false } } == [.toolCall(ToolCall(id: "call_9", name: "search_project", arguments: "{\"query\":\"fig\"}"))])
        #expect(events.last == .done(.toolUse, nil))
        let b = body(stub.requests[0])
        let messages = b["messages"] as? [[String: Any]] ?? []
        #expect(messages[2]["tool_calls"] != nil)
        #expect(messages[3]["role"] as? String == "tool" && messages[3]["tool_call_id"] as? String == "c1")
        #expect(((b["tools"] as? [[String: Any]])?.first?["function"] as? [String: Any])?["name"] as? String == "read_file")
    }

    @Test func responsesReadsFunctionCallItemsAndSendsOutputs() async throws {
        let stub = StubTransport(chunks: [
            "data: {\"type\":\"response.output_item.done\",\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_7\",\"name\":\"list_files\",\"arguments\":\"{}\"}}\n\n",
            "data: {\"type\":\"response.completed\",\"response\":{}}\n\n",
        ])
        let url = URL(string: "https://x.test/responses")!
        let events = try await collect(OpenCodeClient(provider: provider("opencode-zen"), key: "k", transport: stub.transport)
            .run(ResponsesWire.request(toolRequest(), url: url, key: "k", maxOutput: nil), model: "m", key: "k", transport: stub.transport, handle: ResponsesWire.decode))
        #expect(events.first == .toolCall(ToolCall(id: "call_7", name: "list_files", arguments: "{}")))
        let input = body(ResponsesWire.request(toolRequest(), url: url, key: "k", maxOutput: nil))["input"] as? [[String: Any]] ?? []
        #expect(input.map { $0["type"] as? String ?? $0["role"] as? String } == ["user", "function_call", "function_call_output"])
        #expect(input[1]["call_id"] as? String == "c1" && input[2]["output"] as? String == "TEXT")
    }
}

@Suite struct ToolPermissionTests {
    @Test func defaultsAskForFilesAndAllowSearch() {
        let p = AssistantPermissions()
        #expect(p.decide(call) == .ask("May the assistant read a.typ?"))
        #expect(p.decide(ToolCall(id: "s", name: "search_project", arguments: "{\"query\":\"x\"}")) == .run)
        #expect(p.decide(ToolCall(id: "d", name: "get_diagnostics", arguments: "{}")) == .run)
        #expect(p.decide(ToolCall(id: "?", name: "rm", arguments: "{}")) != .run)
    }

    @Test func attachedFilesAndOverrides() {
        var p = AssistantPermissions()
        #expect(p.decide(call, attached: ["a.typ"]) == .run)
        p.set(.projectFiles, .allow)
        #expect(p.decide(call) == .run)
        p.set(.projectFiles, .never)
        if case .deny = p.decide(call) {} else { Issue.record("expected deny") }
        #expect(!p.offeredTools.contains(.readFile) && !p.offeredTools.contains(.getOutline) && p.offeredTools.contains(.searchProject))
    }

    @Test func shieldToggleOnMeansAllow() {
        #expect(AssistantPermission.projectFiles.onPolicy == .allow && AssistantPermission.searchProject.onPolicy == .allow)
    }
}

private final class ScriptedClient: AssistantClient, Sendable {
    let rounds: Mutex<[[AssistantEvent]]>
    let seen = Mutex<[AssistantRequest]>([])
    init(rounds: [[AssistantEvent]]) { self.rounds = Mutex(rounds) }
    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        seen.withLock { $0.append(request) }
        let events = rounds.withLock { $0.isEmpty ? [.done(.endTurn, nil)] : $0.removeFirst() }
        return AsyncThrowingStream { c in for e in events { c.yield(e) }; c.finish() }
    }
    func models() async throws -> [String] { [] }
}

@MainActor @Suite struct AgentLoopTests {
    @Test func runsToolsAndContinuesUntilNoMoreCalls() async throws {
        let client = ScriptedClient(rounds: [
            [.text("Let me look. "), .toolCall(call), .done(.toolUse, nil)],
            [.text("Done."), .done(.endTurn, nil)],
        ])
        var steps: [AssistantAgent.Step] = []
        var r = AssistantRequest(model: "m", system: "S", files: nil, messages: [.init(role: .user, text: "q")])
        r.clientTools = ClientTool.allCases
        try await AssistantAgent.run(client: client, request: r, execute: { ToolResult(callID: $0.id, content: "file text") }, emit: { steps.append($0) })
        #expect(steps.contains(.nextRound) && steps.contains(.result(ToolResult(callID: "c1", content: "file text"))))
        let second = client.seen.withLock { $0 }[1].messages
        #expect(second.map(\.role) == [.user, .assistant, .user])
        #expect(second[1].text == "Let me look. " && second[1].calls == [call] && second[2].results.first?.content == "file text")
    }

    @Test func stopsAfterTheRoundLimit() async throws {
        let forever = Array(repeating: [AssistantEvent.toolCall(call), .done(.toolUse, nil)], count: 10)
        let client = ScriptedClient(rounds: forever)
        var steps: [AssistantAgent.Step] = []
        try await AssistantAgent.run(client: client, request: AssistantRequest(model: "m", system: "S", files: nil, messages: [.init(role: .user, text: "q")]),
                                     maxRounds: 3, execute: { ToolResult(callID: $0.id, content: "x") }, emit: { steps.append($0) })
        #expect(client.seen.withLock { $0.count } == 3)
        #expect(steps.last == .stream(.text("\n\n*Stopped after 3 rounds of tool use.*")))
    }

    @Test func aServerWithoutFunctionCallingGetsTheRequestAgainWithoutTools() async throws {
        final class Refusing: AssistantClient, Sendable {
            let seen = Mutex<[Bool]>([])
            func stream(_ r: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
                seen.withLock { $0.append(r.clientTools.isEmpty) }
                let fail = !r.clientTools.isEmpty
                return AsyncThrowingStream { c in
                    if fail { c.finish(throwing: AssistantError.badRequest("tools unsupported")) } else { c.yield(.text("plain")); c.yield(.done(.endTurn, nil)); c.finish() }
                }
            }
            func models() async throws -> [String] { [] }
        }
        let client = Refusing()
        var r = AssistantRequest(model: "m", system: "S", files: nil, messages: [.init(role: .user, text: "q")])
        r.clientTools = [.readFile]
        var steps: [AssistantAgent.Step] = []
        try await AssistantAgent.run(client: client, request: r, execute: { ToolResult(callID: $0.id, content: "") }, emit: { steps.append($0) })
        #expect(client.seen.withLock { $0 } == [false, true] && steps.contains(.stream(.text("plain"))))
    }
}

@Suite struct ToolConversationTests {
    @Test func wireMessagesCarryExchangesAndAnswerCancelledCalls() {
        var c = AssistantConversation(providerID: nil, model: "m")
        c.messages = [AssistantMessage(role: .user, text: "q")]
        var round = AssistantMessage(role: .assistant, text: "")
        round.toolCalls = [ToolExchange(call: call, result: "TEXT"), ToolExchange(call: ToolCall(id: "c2", name: "list_files", arguments: "{}"))]
        c.messages.append(round)
        c.messages.append(AssistantMessage(role: .assistant, text: "Answer"))
        let wire = c.wireMessages(tools: true)
        #expect(wire.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(wire[2].results.map(\.content) == ["TEXT", "Cancelled before it ran."] && wire[2].results[1].isError)
        // Without tools the answer's text stays and the exchange goes.
        #expect(c.wireMessages().map(\.text) == ["q", "Answer"])
    }

    @Test func oldFilesWithoutToolCallsStillDecode() throws {
        let m = AssistantMessage(role: .assistant, text: "hi")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(m)) as! [String: Any]
        json.removeValue(forKey: "toolCalls")
        let back = try JSONDecoder().decode(AssistantMessage.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(back.toolCalls == nil)
        var withTools = m
        withTools.toolCalls = [ToolExchange(call: call, result: "r")]
        #expect(try JSONDecoder().decode(AssistantMessage.self, from: JSONEncoder().encode(withTools)).toolCalls == withTools.toolCalls)
    }

    @Test func rowTitlesAndOutputs() {
        #expect(ToolExchange(call: call).title == "Read a.typ")
        #expect(ToolExchange(call: ToolCall(id: "s", name: "search_project", arguments: "{\"query\":\"figure\"}")).title == "Searched for 'figure'")
        #expect(ToolOutput.outline("= One\ntext\n== Two\n#let x = 1\n=NoSpace") == "One (line 1)\n  Two (line 3)")
        #expect(ToolOutput.file(String(repeating: "a", count: ToolOutput.fileLimit + 5)).hasSuffix("characters shown.]"))
        #expect(ToolOutput.diagnostics([]) == "No compiler errors or warnings.")
    }
}

@Suite struct AIMarksTests {
    private func marks(_ rs: NSRange...) -> AIMarks { var m = AIMarks(); rs.forEach { m.add($0) }; return m }

    @Test func shiftsWithEditsBeforeAndKeepsOnesAfter() {
        var m = marks(NSRange(location: 10, length: 5))
        m.edited(NSRange(location: 0, length: 2), newLength: 6)     // typed before: +4
        #expect(m.ranges == [NSRange(location: 14, length: 5)])
        m.edited(NSRange(location: 19, length: 0), newLength: 3)    // typed right after the mark
        #expect(m.ranges == [NSRange(location: 14, length: 5)])
        m.edited(NSRange(location: 14, length: 0), newLength: 1)    // typed at its start: the text moves
        #expect(m.ranges == [NSRange(location: 15, length: 5)])
    }

    @Test func removeDropsOnlyOverlappingMarks() {
        var m = marks(NSRange(location: 0, length: 3), NSRange(location: 10, length: 3))
        m.remove(overlapping: NSRange(location: 11, length: 0))
        #expect(m.ranges == [NSRange(location: 0, length: 3)])
    }

    @MainActor @Test func dismissKeepsTheTextAndOlderChangesArePrevious() async throws {
        let (project, _) = try await TestEnv.project(files: ["main.typ": "one\ntwo\nthree\n"])
        let b = try await project.open(RelPath("main.typ")!)
        b.applyAssistant([Replacement(range: NSRange(location: 0, length: 3), text: "ONE")])
        let mark = b.aiMarks.ranges[0]
        #expect(!b.isPreviousAIBlock(mark))
        b.previousAIChanges = Set(b.aiChanges.map(\.id))
        #expect(b.isPreviousAIBlock(mark))
        b.dismissAIMark(mark)
        #expect(b.aiMarks.isEmpty)
        #expect(b.storage.string.hasPrefix("ONE"))
    }

    @Test func anEditInsideOrOverlappingDropsTheMark() {
        for edit in [NSRange(location: 12, length: 0), NSRange(location: 12, length: 1), NSRange(location: 8, length: 4), NSRange(location: 0, length: 40)] {
            var m = marks(NSRange(location: 10, length: 5), NSRange(location: 30, length: 2))
            m.edited(edit, newLength: 1)
            #expect(!m.ranges.contains { $0.length == 5 }, "\(edit)")
        }
    }

    @Test func mergesTouchingMarksAndFindsFragments() {
        var m = marks(NSRange(location: 0, length: 5))
        m.add(NSRange(location: 5, length: 3))
        #expect(m.ranges == [NSRange(location: 0, length: 8)])
        #expect(m.touches(7, 12) && !m.touches(8, 12))
        #expect(!m.touches(20, 20))
    }
}

@MainActor @Suite struct AssistantEditMarkTests {
    @Test func acceptedEditsMarkTheTextTheyWroteAndHandEditsDropIt() async throws {
        let (project, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "one\ntwo\nthree\n"])
        let path = RelPath("a.typ")!
        try await project.assistantEdit(path, [Replacement(range: NSRange(location: 4, length: 3), text: "TWO!")])
        let buffer = try await project.open(path)
        #expect(buffer.storage.string == "one\nTWO!\nthree\n" && buffer.aiMarks.ranges == [NSRange(location: 4, length: 4)])
        buffer.apply([Replacement(range: NSRange(location: 0, length: 0), text: "zero\n")])
        #expect(buffer.aiMarks.ranges == [NSRange(location: 9, length: 4)])
        buffer.apply([Replacement(range: NSRange(location: 10, length: 1), text: "x")])
        #expect(buffer.aiMarks.isEmpty)
    }
}

@MainActor @Suite struct AssistantRevertTests {
    @Test func changeTrackingShiftsAndFlagsHandEdits() {
        var c = AIChange(range: NSRange(location: 10, length: 4), original: "o", written: "xxxx")
        c.edited(NSRange(location: 0, length: 0), newLength: 3)
        #expect(c.range == NSRange(location: 13, length: 4) && !c.edited)
        c.edited(NSRange(location: 17, length: 0), newLength: 2)     // right after: stays
        #expect(c.range == NSRange(location: 13, length: 4) && !c.edited)
        c.edited(NSRange(location: 15, length: 1), newLength: 1)
        #expect(c.edited)
    }

    @Test func revertRestoresExactlyEvenAfterEditsElsewhere() async throws {
        let (project, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "one\ntwo\nthree\nfour\n"])
        let path = RelPath("a.typ")!
        let first = try await project.assistantEdit(path, [Replacement(range: NSRange(location: 4, length: 3), text: "TWO!")])
        let second = try await project.assistantEdit(path, [Replacement(range: NSRange(location: 15, length: 4), text: "4")])
        let b = try await project.open(path)
        #expect(b.storage.string == "one\nTWO!\nthree\n4\n")
        b.apply([Replacement(range: NSRange(location: 0, length: 0), text: "zero\n")])    // typed above both
        #expect(b.canRevert(first[0]) && b.canRevert(second[0]))
        #expect(b.revertAssistant(first[0]))
        #expect(b.storage.string == "zero\none\ntwo\nthree\n4\n")
        #expect(b.canRevert(second[0]) && b.revertAssistant(second[0]))
        #expect(b.storage.string == "zero\none\ntwo\nthree\nfour\n")
        #expect(b.aiChanges.isEmpty && !b.revertAssistant(first[0]))
    }

    @Test func aHandEditInsideTheChangeDisablesRevert() async throws {
        let (project, _) = try await TestEnv.project(files: ["main.typ": "= Hi\n", "a.typ": "one\ntwo\nthree\n"])
        let path = RelPath("a.typ")!
        let ids = try await project.assistantEdit(path, [Replacement(range: NSRange(location: 4, length: 3), text: "TWO!")])
        let b = try await project.open(path)
        b.apply([Replacement(range: NSRange(location: 5, length: 1), text: "w")])
        #expect(!b.canRevert(ids[0]) && !b.revertAssistant(ids[0]))
        #expect(b.storage.string == "one\nTwO!\nthree\n")
    }
}

/// Answers each request with the next list of chunks.
private final class QueuedTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [[String]]
    private var _requests: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { _requests } }
    init(_ rounds: [[String]]) { queue = rounds }
    var transport: AssistantTransport {
        { req in
            let chunks = self.lock.withLock { () -> [String] in self._requests.append(req); return self.queue.isEmpty ? [] : self.queue.removeFirst() }
            return AssistantHTTPResponse(status: 200, headers: [:], body: AsyncThrowingStream { c in
                for d in chunks { c.yield(Data(d.utf8)) }
                c.finish()
            })
        }
    }
}

@MainActor @Suite struct AgentOverTheWireTests {
    @Test func anthropicToolUseThenAnswer() async throws {
        let q = QueuedTransport([
            [
                "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
                "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Looking.\"}}\n\n",
                "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"read_file\",\"input\":{}}}\n\n",
                "data: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"path\\\":\\\"a.typ\\\"}\"}}\n\n",
                "data: {\"type\":\"content_block_stop\",\"index\":1}\n\n",
                "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":5}}\n\n",
                "data: {\"type\":\"message_stop\"}\n\n",
            ],
            [
                "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"It says FILE.\"}}\n\n",
                "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":4}}\n\n",
                "data: {\"type\":\"message_stop\"}\n\n",
            ],
        ])
        var r = AssistantRequest(model: "claude-x", system: "S", files: nil, messages: [.init(role: .user, text: "what is in a.typ?")])
        r.clientTools = [.readFile]
        var text = "", executed: [ToolCall] = []
        try await AssistantAgent.run(client: AssistantClients.make(provider("anthropic"), key: "k", transport: q.transport), request: r,
                                     execute: { executed.append($0); return ToolResult(callID: $0.id, content: "FILE") },
                                     emit: { if case .stream(.text(let t)) = $0 { text += t } })
        #expect(executed == [ToolCall(id: "toolu_1", name: "read_file", arguments: "{\"path\":\"a.typ\"}")])
        #expect(text == "Looking.It says FILE." && q.requests.count == 2)
        let messages = body(q.requests[1])["messages"] as? [[String: Any]] ?? []
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        let assistant = messages[1]["content"] as? [[String: Any]] ?? []
        #expect(assistant.map { $0["type"] as? String } == ["text", "tool_use"] && assistant[1]["id"] as? String == "toolu_1")
        let result = (messages[2]["content"] as? [[String: Any]])?.first
        #expect(result?["type"] as? String == "tool_result" && result?["tool_use_id"] as? String == "toolu_1" && result?["content"] as? String == "FILE")
    }
}

// MARK: - typst_docs, Gemini tools, images, on-device tools

private let png = Data([0x89, 0x50, 0x4E, 0x47])
private func previewRequest() -> AssistantRequest {
    let c = ToolCall(id: "p1", name: "view_preview", arguments: "{\"page\":2}")
    var r = AssistantRequest(model: "m", system: "S", files: nil, messages: [
        .init(role: .user, text: "look"),
        .init(role: .assistant, text: "", calls: [c]),
        .init(role: .user, text: "", results: [ToolResult(callID: "p1", content: "Page 2", image: png)]),
    ])
    r.clientTools = [.viewPreview]
    return r
}

@Suite struct TypstDocsTests {
    @Test func rankingPutsTheNamedEntryFirst() {
        #expect(TypstDocs.search("table cell merge").first?.name == "table.cell")
        #expect(TypstDocs.search("show rule").first?.name == "show rule")
        #expect(TypstDocs.search("#figure(").first?.name == "figure")
        #expect(TypstDocs.search("how do I make text bold").map(\.name).contains("strong"))
        #expect(TypstDocs.search("zzqqx").isEmpty && TypstDocs.search("   ").isEmpty)
        #expect(TypstDocs.search("table").count <= 5)
    }

    @Test func outputIsCappedAndSaysWhenNothingMatches() {
        let out = ToolOutput.docs("table")
        #expect(out.count <= ToolOutput.docsLimit && out.contains("```typst") && out.contains("table"))
        #expect(ToolOutput.docs("table", limit: 300).count <= 300)
        #expect(ToolOutput.docs("zzqqx").contains("Nothing"))
        #expect(ToolOutput.capped(String(repeating: "x", count: 50), limit: 10).hasPrefix("xxxxxxxxxx\n[Cut"))
        #expect(ToolOutput.capped("short", limit: 10) == "short")
    }

    @Test func everyEntryIsComplete() {
        for e in TypstDocs.all { #expect(!e.name.isEmpty && !e.signature.isEmpty && !e.about.isEmpty && !e.example.isEmpty, "\(e.name)") }
    }
}

@Suite struct GeminiToolTests {
    private func gemini(_ r: AssistantRequest) -> [String: Any] {
        body(GeminiWire.request(r, url: URL(string: "https://g/m")!, key: "k", maxOutput: nil))
    }

    @Test func declarationsSitNextToGoogleSearch() throws {
        var r = toolRequest()
        r.clientTools = [.readFile, .listFiles, .typstDocs]
        r.tools = [.webSearch]
        let tools = try #require(gemini(r)["tools"] as? [[String: Any]])
        #expect(tools.count == 2 && tools[0]["google_search"] != nil)
        let decls = try #require(tools[1]["functionDeclarations"] as? [[String: Any]])
        #expect(decls.map { $0["name"] as? String } == ["read_file", "list_files", "typst_docs"])
        #expect(decls[0]["parameters"] != nil && decls[1]["parameters"] == nil, "a tool without arguments has no parameters")
    }

    @Test func historyKeepsCallsAndAnswersWithFunctionResponses() throws {
        var r = previewRequest()
        r.messages[1].calls[0].signature = "sig"
        let contents = try #require(gemini(r)["contents"] as? [[String: Any]])
        #expect(contents.map { $0["role"] as? String } == ["user", "model", "user"])
        let call = try #require((contents[1]["parts"] as? [[String: Any]])?.first)
        #expect((call["functionCall"] as? [String: Any])?["name"] as? String == "view_preview" && call["thoughtSignature"] as? String == "sig")
        #expect(((call["functionCall"] as? [String: Any])?["args"] as? [String: Any])?["page"] as? Int == 2)
        let parts = try #require(contents[2]["parts"] as? [[String: Any]])
        let response = parts[0]["functionResponse"] as? [String: Any]
        #expect(response?["name"] as? String == "view_preview" && (response?["response"] as? [String: Any])?["result"] as? String == "Page 2")
        #expect((parts[1]["inlineData"] as? [String: Any])?["mimeType"] as? String == "image/png")
    }

    @Test func streamedFunctionCallsBecomeToolCalls() throws {
        var s = DecodeState()
        let out = try GeminiWire.decode(&s, SSEEvent(event: nil, data: "{\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"search_project\",\"args\":{\"query\":\"fig\"}},\"thoughtSignature\":\"abc\"}]},\"finishReason\":\"STOP\"}]}"))
        guard case .toolCall(let c)? = out.first else { Issue.record("no call"); return }
        #expect(c.name == "search_project" && c.arguments == "{\"query\":\"fig\"}" && c.signature == "abc" && !c.id.isEmpty)
    }

    @Test func aRejectedSearchPlusFunctionsRequestIsSentAgainWithoutSearch() async throws {
        let seen = Mutex<[Bool]>([])
        let transport: AssistantTransport = { req in
            if req.url?.path.hasSuffix("/v1/models") == true { return AssistantHTTPResponse(status: 404, headers: [:], body: AsyncThrowingStream { $0.finish() }) }
            let hasSearch = (body(req)["tools"] as? [[String: Any]])?.contains { $0["google_search"] != nil } ?? false
            seen.withLock { $0.append(hasSearch) }
            let status = hasSearch ? 400 : 200
            let text = hasSearch ? "{\"error\":{\"message\":\"Tool use with function calling is unsupported\"}}"
                : "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ok\"}]},\"finishReason\":\"STOP\"}]}\n\n"
            return AssistantHTTPResponse(status: status, headers: [:], body: AsyncThrowingStream { $0.yield(Data(text.utf8)); $0.finish() })
        }
        var r = toolRequest()
        r.model = "gemini-4-argon"
        r.tools = [.webSearch]
        let events = try await collect(OpenCodeClient(provider: provider("opencode-zen"), key: "k", transport: transport).stream(r))
        #expect(seen.withLock { $0 } == [true, false])
        #expect(events.contains(.text("ok")) && events.contains { if case .reasoning(let n) = $0 { n.contains("web search is off") } else { false } })
    }

    @Test func geminiRoutesGetTools() {
        #expect(AssistantPermissions.supportsTools(provider: provider("opencode-zen"), model: "gemini-4-argon"))
    }
}

@Suite struct ImageResultTests {
    @Test func anthropicSendsAnImageBlockInsideTheToolResult() throws {
        let req = try AnthropicClient(provider: provider("anthropic"), key: "k", transport: StubTransport(chunks: []).transport).urlRequest(previewRequest())
        let result = ((body(req)["messages"] as? [[String: Any]])?[2]["content"] as? [[String: Any]])?.first
        let content = result?["content"] as? [[String: Any]]
        #expect(content?[0]["type"] as? String == "text" && content?[1]["type"] as? String == "image")
        #expect((content?[1]["source"] as? [String: Any])?["data"] as? String == png.base64EncodedString())
    }

    @Test func chatCompletionsSendsTheImageInAFollowUpUserMessage() throws {
        let req = try OpenAICompatibleClient(provider: provider("openai"), key: "k", transport: StubTransport(chunks: []).transport).urlRequest(previewRequest())
        let messages = body(req)["messages"] as? [[String: Any]] ?? []
        #expect(messages.map { $0["role"] as? String } == ["system", "user", "assistant", "tool", "user"])
        let part = (messages[4]["content"] as? [[String: Any]])?[1]
        #expect(part?["type"] as? String == "image_url" && ((part?["image_url"] as? [String: Any])?["url"] as? String)?.hasPrefix("data:image/png;base64,") == true)
        #expect(messages[3]["content"] as? String == "Page 2")
    }

    @Test func responsesSendsAnInputImage() {
        let input = body(ResponsesWire.request(previewRequest(), url: URL(string: "https://x/r")!, key: "k", maxOutput: nil))["input"] as? [[String: Any]] ?? []
        let image = input.last?["content"] as? [[String: Any]]
        #expect(input.last?["role"] as? String == "user" && image?[1]["type"] as? String == "input_image")
    }

    @Test func previewScalesToTheLimit() {
        #expect(Project.previewPPI(pageSize: CGSize(width: 595, height: 842), limit: 1600) == 136)    // 842 pt * 136/72 = 1590 px
        #expect(Project.previewPPI(pageSize: CGSize(width: 100, height: 100), limit: 1600) == 144, "never above 144 ppi")
        #expect(Project.previewPPI(pageSize: CGSize(width: 20_000, height: 100), limit: 1600) >= 1)
    }
}

@Suite struct NewToolPermissionTests {
    @Test func visionAndOfferedTools() {
        let claude = provider("anthropic"), zen = provider("opencode-zen"), device = AssistantProvider.onDevice
        #expect(AssistantPermissions.supportsVision(provider: claude, model: "claude-opus-5-5"))
        #expect(AssistantPermissions.supportsVision(provider: zen, model: "gpt-5.2") && AssistantPermissions.supportsVision(provider: zen, model: "gemini-4-argon"))
        #expect(!AssistantPermissions.supportsVision(provider: zen, model: "kimi-k3") && !AssistantPermissions.supportsVision(provider: device, model: "x"))
        let p = AssistantPermissions()
        #expect(p.offered(provider: claude, model: "claude-opus-5-5").contains(.viewPreview))
        #expect(!p.offered(provider: zen, model: "kimi-k3").contains(.viewPreview) && p.offered(provider: zen, model: "kimi-k3").contains(.typstDocs))
        #expect(Set(p.offered(provider: device, model: "x")) == Set(ClientTool.onDeviceTools))
        var never = p
        never.set(.viewPreview, .never)
        #expect(!never.offered(provider: claude, model: "claude-opus-5-5").contains(.viewPreview))
        never.set(.diagnostics, .never)
        #expect(!never.offered(provider: claude, model: "claude-opus-5-5").contains(.compile))
    }

    @Test func previewAsksByDefaultDocsNeverDo() {
        let p = AssistantPermissions()
        #expect(AssistantPermission.viewPreview.defaultPolicy == .ask)
        if case .ask = p.decide(ToolCall(id: "v", name: "view_preview", arguments: "{\"page\":3}")) {} else { Issue.record("expected ask") }
        #expect(p.decide(ToolCall(id: "d", name: "typst_docs", arguments: "{\"query\":\"x\"}")) == .run)
        #expect(p.decide(ToolCall(id: "c", name: "compile", arguments: "{}")) == .run)
        var n = p
        n.set(.diagnostics, .never)
        if case .deny = n.decide(ToolCall(id: "c", name: "compile", arguments: "{}")) {} else { Issue.record("expected deny") }
        #expect(ToolExchange(call: ToolCall(id: "v", name: "view_preview", arguments: "{\"page\":3}")).title == "Viewed preview page 3")
    }

    @Test func systemPromptTellsToUseTheDocs() {
        #expect(AssistantContext.systemPrompt(proposeEdits: true, tools: [.typstDocs]).contains("typst_docs instead of guessing"))
        #expect(!AssistantContext.systemPrompt(proposeEdits: true, tools: [.readFile]).contains("typst_docs"))
    }
}

@MainActor @Suite struct OnDeviceToolTests {
    @Test func toolsRunThroughTheAppCapAndCountAndAreReported() async throws {
        let long = String(repeating: "y", count: 3_000)
        let ran = Mutex<[String]>([])
        let answers = Mutex<[String]>([])
        let client = OnDeviceClient(generate: { _, _ in AsyncThrowingStream { $0.finish() } }, generateWithTools: { _, _, kit in
            AsyncThrowingStream { c in
                Task {
                    for _ in 0..<4 { answers.withLock { $0.append("") }; let a = await kit.invoke(.typstDocs, ["query": "table"]); answers.withLock { $0[$0.count - 1] = a } }
                    c.yield("Done")
                    c.finish()
                }
            }
        })
        var r = AssistantRequest(model: "m", system: "S", files: nil, messages: [.init(role: .user, text: "q")])
        r.clientTools = [.typstDocs, .getDiagnostics, .getOutline, .readFile]
        var steps: [AssistantAgent.Step] = []
        try await AssistantAgent.run(client: client, request: r, execute: { c in ran.withLock { $0.append(c.name) }; return ToolResult(callID: c.id, content: long) }, emit: { steps.append($0) })
        #expect(ran.withLock { $0 } == ["typst_docs", "typst_docs", "typst_docs"], "the fourth call is refused")
        let a = answers.withLock { $0 }
        #expect(a[0].count < 1_600 && a[0].contains("Cut at 1500") && a[3].contains("No more tool calls"))
        let called = steps.filter { if case .stream(.toolCall) = $0 { true } else { false } }
        #expect(called.count == 3 && steps.filter { if case .result = $0 { true } else { false } }.count == 3 && steps.contains(.stream(.text("Done"))))
    }

    @Test func aWindowTooSmallForTheToolResultsAnswersWithoutTools() async throws {
        let client = OnDeviceClient(generate: { _, _ in AsyncThrowingStream { $0.yield("plain"); $0.finish() } },
                                    generateWithTools: { _, _, _ in AsyncThrowingStream { $0.finish(throwing: AssistantError.passageTooLarge) } })
        var r = AssistantRequest(model: "m", system: "S", files: nil, messages: [.init(role: .user, text: "q")])
        r.clientTools = [.typstDocs]
        let events = try await collect(client.stream(r, run: { ToolResult(callID: $0.id, content: "") }))
        #expect(events.contains(.text("plain")))
    }

    @Test func noRunnerOrNoToolsUsesThePlainPath() async throws {
        let client = OnDeviceClient(generate: { _, _ in AsyncThrowingStream { $0.yield("plain"); $0.finish() } },
                                    generateWithTools: { _, _, _ in AsyncThrowingStream { $0.finish(throwing: AssistantError.onDevice("no")) } })
        let r = AssistantRequest(model: "m", system: "S", files: nil, messages: [.init(role: .user, text: "q")])
        #expect(try await collect(client.stream(r)).contains(.text("plain")))
        #expect(OnDeviceContext.toolNote([.readFile]) == "" && OnDeviceContext.toolNote([.typstDocs, .getOutline]).contains("typst_docs, get_outline"))
    }
}
