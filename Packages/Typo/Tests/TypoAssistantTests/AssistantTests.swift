import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypoAssistant
@testable import TypstEngine

/// A transport that records requests and answers with canned chunks; nothing reaches the network.
final class StubTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { _requests } }
    let status: Int, headers: [String: String], chunks: [Data]

    init(status: Int = 200, headers: [String: String] = [:], chunks: [String]) {
        self.status = status; self.headers = headers; self.chunks = chunks.map { Data($0.utf8) }
    }

    var transport: AssistantTransport {
        { req in
            self.lock.withLock { self._requests.append(req) }
            let chunks = self.chunks
            return AssistantHTTPResponse(status: self.status, headers: self.headers, body: AsyncThrowingStream { c in
                for d in chunks { c.yield(d) }
                c.finish()
            })
        }
    }
}

private func body(_ r: URLRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: Any]) ?? [:] }

private func collect(_ s: AsyncThrowingStream<AssistantEvent, Error>) async throws -> [AssistantEvent] {
    var out: [AssistantEvent] = []
    for try await e in s { out.append(e) }
    return out
}

private let request = AssistantRequest(model: "m", system: "SYS", files: "FILES", messages: [.init(role: .user, text: "hi")])
private func provider(_ id: String, baseURL: String? = nil, keyHeader: String = "Authorization") -> AssistantProvider {
    var p = AssistantProvider(preset: AssistantPreset.named(id)!, baseURL: baseURL, keyHeader: keyHeader)
    p.model = "m"
    return p
}

@Suite struct AssistantSSETests {
    @Test func splitsChunksAnywhereIncludingInsideUTF8() {
        let text = "event: a\ndata: {\"t\":\"Grüße\"}\n\ndata: x\r\ndata: y\r\n\r\n: comment\n\n"
        let bytes = Array(text.utf8)
        for size in [1, 2, 3, 7, bytes.count] {
            var p = SSEParser(), out: [SSEEvent] = []
            for start in stride(from: 0, to: bytes.count, by: size) { out += p.feed(Data(bytes[start..<min(start + size, bytes.count)])) }
            out += p.finish()
            #expect(out == [SSEEvent(event: "a", data: "{\"t\":\"Grüße\"}"), SSEEvent(event: nil, data: "x\ny")], "chunk size \(size)")
        }
    }

    @Test func flushesALastEventWithoutBlankLine() {
        var p = SSEParser()
        #expect(p.feed(Data("data: [DONE]".utf8)).isEmpty)
        #expect(p.finish() == [SSEEvent(event: nil, data: "[DONE]")])
    }

    @Test func openAIStreamWithReasoningAndDone() async throws {
        let stub = StubTransport(chunks: [
            "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"Think\"}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\ndata: {\"choi",
            "ces\":[{\"delta\":{\"content\":\"lo\"},\"finish_reason\":\"stop\"}]}\n\n",
            "data: [DONE]\n\n",
        ])
        let client = AssistantClients.make(provider("openai"), key: "k", transport: stub.transport)
        let events = try await collect(client.stream(request))
        #expect(events == [.reasoning("Think"), .text("Hel"), .text("lo"), .done(.endTurn, nil)])
    }

    @Test func openAILengthStopWithoutDoneMarker() async throws {
        let stub = StubTransport(chunks: ["data: {\"choices\":[{\"delta\":{\"content\":\"a\"},\"finish_reason\":\"length\"}]}\n\n"])
        let events = try await collect(AssistantClients.make(provider("ollama"), key: nil, transport: stub.transport).stream(request))
        #expect(events == [.text("a"), .done(.maxTokens, nil)])
    }

    @Test func anthropicEventTypes() async throws {
        let stub = StubTransport(chunks: [
            "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":10}}}\n\n",
            "event: ping\ndata: {\"type\":\"ping\"}\n\n",
            "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n",
            "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hel",
            "lo\"}}\n\nevent: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":12}}\n\n",
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
        ])
        let events = try await collect(AssistantClients.make(provider("anthropic"), key: "k", transport: stub.transport).stream(request))
        #expect(events == [.text("Hello"), .done(.endTurn, AssistantUsage(input: 10, output: 12))])
    }

    @Test func anthropicRefusalAndMaxTokens() async throws {
        for (reason, expected) in [("refusal", AssistantStopReason.refusal), ("max_tokens", .maxTokens)] {
            let stub = StubTransport(chunks: [
                "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"\(reason)\"},\"usage\":{\"output_tokens\":0}}\n\n",
                "data: {\"type\":\"message_stop\"}\n\n",
            ])
            let events = try await collect(AssistantClients.make(provider("anthropic"), key: "k", transport: stub.transport).stream(request))
            #expect(events == [.done(expected, AssistantUsage(input: nil, output: 0))])
        }
    }

    @Test func anthropicErrorEventInStream() async {
        let stub = StubTransport(chunks: ["event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}\n\n"])
        await #expect(throws: AssistantError.server(status: 529, message: "Overloaded")) {
            _ = try await collect(AssistantClients.make(provider("anthropic"), key: "k", transport: stub.transport).stream(request))
        }
    }

    @Test func errorBodyIsMappedAndKeyScrubbed() async {
        let stub = StubTransport(status: 400, chunks: ["{\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"bad key sk-secret here\"}}"])
        await #expect(throws: AssistantError.badRequest("bad key … here")) {
            _ = try await collect(AssistantClients.make(provider("openai"), key: "sk-secret", transport: stub.transport).stream(request))
        }
    }

    @Test func streamErrorMessagesAreScrubbed() async {
        let stub = StubTransport(chunks: ["data: {\"error\":{\"message\":\"key sk-secret is bad\"}}\n\n"])
        await #expect(throws: AssistantError.badRequest("key … is bad")) {
            _ = try await collect(AssistantClients.make(provider("openai"), key: "sk-secret", transport: stub.transport).stream(request))
        }
    }

    @Test func streamEndingEarlyIsAnError() async {
        let stub = StubTransport(chunks: ["data: {\"choices\":[{\"delta\":{\"content\":\"a\"}}]}\n\n"])
        await #expect(throws: AssistantError.self) {
            _ = try await collect(AssistantClients.make(provider("openai"), key: "k", transport: stub.transport).stream(request))
        }
    }
}

@Suite struct OpenCodeGatewayTests {
    static let list = """
    {"object":"list","data":[
     {"id":"kimi-k3","type":"chat","recommended_api":"chat-completions","limit":{"output":32000},"api":{"chat-completions":{"base_url":"https://opencode.ai/inference/go/openai/v1"}}},
     {"id":"qwen3.8-max","type":"chat","recommended_api":"messages","limit":{"output":131072},"api":{"messages":{"base_url":"https://opencode.ai/inference/go/anthropic/v1"}}},
     {"id":"gpt-6-luna","type":"chat","recommended_api":"responses","api":{"responses":{"base_url":"https://opencode.ai/inference/go/openai/v1"}}},
     {"id":"gemini-4-argon","type":"chat","recommended_api":"interactions","api":{"generate-content":{"base_url":"https://opencode.ai/inference/go/google/v1beta"},"interactions":{"base_url":"https://opencode.ai/inference/go/google/v1beta"}}},
     {"id":"gpt-image-2.5","type":"image","recommended_api":"images","api":{"images":{"base_url":"https://x"}}}
    ]}
    """

    func client(_ preset: String = "opencode-go") -> OpenCodeClient {
        var p = AssistantProvider(preset: AssistantPreset.named(preset)!)
        p.model = "m"
        return OpenCodeClient(provider: p, key: "oc-key", transport: StubTransport(chunks: []).transport)
    }

    @Test func catalogRoutesEachChatModelToItsProtocol() {
        let c = OpenCodeClient.parseCatalog(Data(Self.list.utf8))
        #expect(c.keys.sorted() == ["gemini-4-argon", "gpt-6-luna", "kimi-k3", "qwen3.8-max"])     // image models are not chat
        #expect(c["kimi-k3"] == GatewayRoute(api: .chatCompletions, base: "https://opencode.ai/inference/go/openai/v1", maxOutput: 32000))
        #expect(c["qwen3.8-max"]?.api == .messages && c["gpt-6-luna"]?.api == .responses)
        #expect(c["gemini-4-argon"] == GatewayRoute(api: .generateContent, base: "https://opencode.ai/inference/go/google/v1beta", maxOutput: nil))
    }

    @Test func unlistedModelsRouteByFamily() {
        let root = "https://opencode.ai/inference"
        #expect(OpenCodeClient.fallbackRoute("claude-opus-5-5", root: root).url == "https://opencode.ai/inference/anthropic/v1/messages")
        #expect(OpenCodeClient.fallbackRoute("gpt-6-sol", root: root).url == "https://opencode.ai/inference/openai/v1/responses")
        #expect(OpenCodeClient.fallbackRoute("gemini-4-neon", root: root + "/").api == .generateContent)
        #expect(OpenCodeClient.fallbackRoute("kimi-k3", root: root).url == "https://opencode.ai/inference/openai/v1/chat/completions")
    }

    @Test func everyRouteSendsTheClientHeaders() throws {
        var r = request
        r.model = "x"; r.session = "S1"
        let c = OpenCodeClient.parseCatalog(Data(Self.list.utf8))
        for id in c.keys {
            let (req, _) = try client().urlRequest(r, route: c[id]!)
            #expect(req.value(forHTTPHeaderField: "x-opencode-session") == "S1", "\(id)")
            #expect(req.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Typo/") == true, "\(id)")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer oc-key", "\(id)")
        }
    }

    @Test func messagesThroughTheGatewayDropAnthropicFallbacks() throws {
        var r = request
        r.model = "qwen3.8-max"
        let (req, _) = try client().urlRequest(r, route: GatewayRoute(api: .messages, base: "https://opencode.ai/inference/go/anthropic/v1", maxOutput: 8000))
        #expect(req.url?.absoluteString == "https://opencode.ai/inference/go/anthropic/v1/messages")
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let b = body(req)
        #expect(b["fallbacks"] == nil && b["max_tokens"] as? Int == 8000)
    }

    @Test func responsesRequestAndStream() async throws {
        var r = request
        r.model = "gpt-6-luna"
        r.messages = [.init(role: .user, text: "a"), .init(role: .assistant, text: "b"), .init(role: .user, text: "c")]
        let req = ResponsesWire.request(r, url: URL(string: "https://g/openai/v1/responses")!, key: "k", maxOutput: 100)
        let b = body(req)
        #expect(b["instructions"] as? String == "SYS\n\nFILES" && b["stream"] as? Bool == true && b["max_output_tokens"] as? Int == 100)
        #expect((b["input"] as? [[String: String]]) == [["role": "user", "content": "a"], ["role": "assistant", "content": "b"], ["role": "user", "content": "c"]])
        var s = DecodeState()
        let events = try [
            "{\"type\":\"response.reasoning_summary_text.delta\",\"delta\":\"hm\"}",
            "{\"type\":\"response.output_text.delta\",\"delta\":\"Hi\"}",
            "{\"type\":\"response.completed\",\"response\":{\"usage\":{\"input_tokens\":3,\"output_tokens\":1}}}",
        ].flatMap { try ResponsesWire.decode(&s, SSEEvent(event: nil, data: $0)) }
        #expect(events == [.reasoning("hm"), .text("Hi"), .done(.endTurn, AssistantUsage(input: 3, output: 1))])
        var t = DecodeState()
        #expect(try ResponsesWire.decode(&t, SSEEvent(event: nil, data: "{\"type\":\"response.incomplete\",\"response\":{\"incomplete_details\":{\"reason\":\"max_output_tokens\"}}}")) == [.done(.maxTokens, nil)])
        #expect(throws: AssistantError.self) { try ResponsesWire.decode(&t, SSEEvent(event: nil, data: "{\"type\":\"error\",\"message\":\"bad\"}")) }
    }

    @Test func geminiRequestAndStream() throws {
        var r = request
        r.messages = [.init(role: .user, text: "a"), .init(role: .assistant, text: "b"), .init(role: .user, text: "c")]
        let req = GeminiWire.request(r, url: URL(string: "https://g/models/gemini-4-argon:streamGenerateContent?alt=sse")!, key: "k", maxOutput: nil)
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == "k")
        let b = body(req)
        let contents = try #require(b["contents"] as? [[String: Any]])
        #expect(contents.map { $0["role"] as? String } == ["user", "model", "user"])
        #expect(((b["systemInstruction"] as? [String: Any])?["parts"] as? [[String: String]])?.first?["text"] == "SYS\n\nFILES")
        var s = DecodeState()
        let out = try GeminiWire.decode(&s, SSEEvent(event: nil, data: "{\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"why\",\"thought\":true},{\"text\":\"Hi\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":4,\"candidatesTokenCount\":2}}"))
        #expect(out == [.reasoning("why"), .text("Hi")] && s.stopReason == .endTurn && s.usage == AssistantUsage(input: 4, output: 2))
    }

    @Test func geminiStreamEndsOnItsFinishReason() async throws {
        let stub = StubTransport(chunks: ["data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}]},\"finishReason\":\"MAX_TOKENS\"}]}\n\n"])
        let c = OpenCodeClient(provider: client().provider, key: "k", transport: stub.transport)
        let (req, decode) = try c.urlRequest(request, route: GatewayRoute(api: .generateContent, base: "https://g/google/v1beta", maxOutput: nil))
        let events = try await collect(c.run(req, model: "m", key: "k", transport: stub.transport, handle: decode))
        #expect(events == [.text("Hi"), .done(.maxTokens, nil)])
    }
}

@Suite struct AssistantRequestTests {
    @Test func anthropicRequestShape() throws {
        let client = AnthropicClient(provider: provider("anthropic"), key: "sk-ant", transport: StubTransport(chunks: []).transport)
        var r = request
        r.model = "claude-opus-5-5"
        r.messages = [.init(role: .user, text: "a"), .init(role: .assistant, text: "b"), .init(role: .user, text: "c")]
        let req = try client.urlRequest(r)
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(req.value(forHTTPHeaderField: "content-type") == "application/json")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        let b = body(req)
        #expect(b["model"] as? String == "claude-opus-5-5")
        #expect(b["max_tokens"] as? Int == 64_000)
        #expect(b["stream"] as? Bool == true)
        #expect(b["fallbacks"] as? String == "default")
        for absent in ["temperature", "top_p", "top_k", "thinking", "budget_tokens"] { #expect(b[absent] == nil, "\(absent)") }
        let system = try #require(b["system"] as? [[String: Any]])
        #expect(system.map { $0["text"] as? String } == ["SYS", "FILES"])
        #expect(system[0]["cache_control"] == nil && system[1]["cache_control"] != nil)
        let messages = try #require(b["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])    // ends on the user: no prefill
        let last = try #require((messages.last?["content"] as? [[String: Any]])?.first)
        #expect(last["text"] as? String == "c" && last["cache_control"] != nil)
    }

    @Test func anthropicHaikuSendsNoFallback() throws {
        let client = AnthropicClient(provider: provider("anthropic"), key: "k", transport: StubTransport(chunks: []).transport)
        var r = request
        r.model = "claude-haiku-5-5"
        let req = try client.urlRequest(r)
        #expect(req.value(forHTTPHeaderField: "anthropic-beta") == nil)
        #expect(body(req)["fallbacks"] == nil)
    }

    @Test func openAICompatiblePresets() throws {
        let cases: [(String, String?, String)] = [
            ("openai", nil, "https://api.openai.com/v1/chat/completions"),
            ("deepseek", nil, "https://api.deepseek.com/chat/completions"),
            ("openrouter", nil, "https://openrouter.ai/api/v1/chat/completions"),
            ("moonshot", nil, "https://api.moonshot.ai/v1/chat/completions"),
            ("zhipu", nil, "https://api.z.ai/api/paas/v4/chat/completions"),
            ("zhipu-cn", nil, "https://open.bigmodel.cn/api/paas/v4/chat/completions"),
            ("qwen", "https://ws1.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/", "https://ws1.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/chat/completions"),
        ]
        for (id, base, url) in cases {
            let req = try OpenAICompatibleClient(provider: provider(id, baseURL: base), key: "k", transport: StubTransport(chunks: []).transport).urlRequest(request)
            #expect(req.url?.absoluteString == url, "\(id)")
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer k", "\(id)")
            let b = body(req)
            #expect(b["model"] as? String == "m" && b["stream"] as? Bool == true, "\(id)")
            for absent in ["frequency_penalty", "presence_penalty", "temperature", "max_tokens"] { #expect(b[absent] == nil, "\(id) \(absent)") }
            let messages = try #require(b["messages"] as? [[String: String]])
            #expect(messages == [["role": "system", "content": "SYS\n\nFILES"], ["role": "user", "content": "hi"]], "\(id)")
        }
    }

    @Test func localPresetsSendNoKey() throws {
        for (p, url) in [(provider("ollama"), "http://localhost:11434/v1/chat/completions"), (provider("lmstudio"), "http://localhost:1234/v1/chat/completions"),
                         (.local(port: 8080, description: "Mine"), "http://localhost:8080/v1/chat/completions")] {
            let req = try OpenAICompatibleClient(provider: p, key: nil, transport: StubTransport(chunks: []).transport).urlRequest(request)
            #expect(req.url?.absoluteString == url)
            #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
        }
    }

    @Test func customKeyHeaderSendsTheBareKey() throws {
        let p = provider("custom-internet", baseURL: "https://llm.example.com/v1", keyHeader: "x-api-key")
        let req = try OpenAICompatibleClient(provider: p, key: "abc", transport: StubTransport(chunks: []).transport).urlRequest(request)
        #expect(req.value(forHTTPHeaderField: "x-api-key") == "abc")
        #expect(req.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func missingBaseURLIsAnError() {
        #expect(throws: AssistantError.missingBaseURL) { try OpenAICompatibleClient(provider: provider("qwen"), key: "k", transport: StubTransport(chunks: []).transport).urlRequest(request) }
    }

    @Test func modelListsFromBothWires() async throws {
        let stub = StubTransport(chunks: ["{\"data\":[{\"id\":\"a\"},{\"id\":\"b\"}]}"])
        #expect(try await AssistantClients.make(provider("openai"), key: "k", transport: stub.transport).models() == ["a", "b"])
        #expect(try await AssistantClients.make(provider("anthropic"), key: "k", transport: stub.transport).models() == ["a", "b"])
        #expect(stub.requests.map { $0.url?.absoluteString } == ["https://api.openai.com/v1/models", "https://api.anthropic.com/v1/models?limit=100"])
        #expect(stub.requests[1].value(forHTTPHeaderField: "x-api-key") == "k")
    }

    @Test func statusCodesMapToTypedErrors() {
        func map(_ status: Int, _ headers: [String: String] = [:]) -> AssistantError {
            AssistantHTTP.error(status: status, headers: headers, body: Data("{\"error\":{\"message\":\"why\"}}".utf8), model: "m", key: nil)
        }
        #expect(map(401) == .invalidKey)
        #expect(map(404) == .unknownModel("m"))
        #expect(map(429, ["retry-after": "20"]) == .rateLimited(retryAfter: 20))
        #expect(map(429) == .rateLimited(retryAfter: nil))
        #expect(!map(429).isRetryable && map(429, ["retry-after": "1"]).isRetryable)
        #expect(map(400) == .badRequest("why"))
        #expect(map(500) == .server(status: 500, message: "why") && map(500).isRetryable)
        #expect(map(529) == .server(status: 529, message: "why"))
        #expect(map(403) == .http(status: 403, message: "why"))
    }
}

@Suite struct AssistantEditTests {
    @Test func parsesASingleBlockAmidProse() {
        let text = "Here is the fix:\n\n<<<<<<< SEARCH main.typ\n= Intro\n=======\n= Introduction\n>>>>>>> REPLACE\n\nDone."
        #expect(AssistantEdits.segments(text) == [.text("Here is the fix:\n"), .edit(ProposedEdit(path: "main.typ", search: "= Intro", replace: "= Introduction")), .text("\nDone.")])
    }

    @Test func parsesSeveralBlocksInsideCodeFences() {
        let text = """
        Two changes:
        ```typst
        <<<<<<< SEARCH a.typ
        x
        =======
        y
        >>>>>>> REPLACE
        ```
        and
        ```
        <<<<<<< SEARCH b.typ
        1
        2
        =======
        >>>>>>> REPLACE
        <<<<<<< SEARCH c.typ
        p
        =======
        q
        >>>>>>> REPLACE
        ```
        """
        #expect(AssistantEdits.segments(text) == [
            .text("Two changes:"), .edit(ProposedEdit(path: "a.typ", search: "x", replace: "y")), .text("and"),
            .edit(ProposedEdit(path: "b.typ", search: "1\n2", replace: "")), .edit(ProposedEdit(path: "c.typ", search: "p", replace: "q")),
        ])
    }

    @Test func malformedBlocksStayText() {
        for text in ["<<<<<<< SEARCH a.typ\nx\n=======\ny\n", "<<<<<<< SEARCH a.typ\nx\n>>>>>>> REPLACE\n", "<<<<<<< SEARCH \nx\n=======\ny\n>>>>>>> REPLACE"] {
            #expect(AssistantEdits.parse(text).isEmpty, "\(text)")
            #expect(AssistantEdits.segments(text) == [.text(text)])
        }
    }

    @Test func newFileBlock() {
        let e = AssistantEdits.parse("<<<<<<< SEARCH chapters/two.typ\n=======\n= Two\n>>>>>>> REPLACE")
        #expect(e == [ProposedEdit(path: "chapters/two.typ", search: "", replace: "= Two")])
        #expect(AssistantEdits.resolve(e[0], text: nil) == .create(RelPath("chapters/two.typ")!, "= Two"))
        #expect(AssistantEdits.resolve(e[0], text: "old") == .failed("chapters/two.typ already exists, so it cannot be created."))
    }

    @Test func resolvesExactNotFoundAndAmbiguous() {
        let text = "é = A\n= B\n= B\n"
        let exact = AssistantEdits.resolve(ProposedEdit(path: "m.typ", search: "= A", replace: "= Z"), text: text)
        #expect(exact == .replace(RelPath("m.typ")!, Replacement(range: NSRange(location: 2, length: 3), text: "= Z"), before: text, after: "é = Z\n= B\n= B\n"))
        guard case .failed(let missing) = AssistantEdits.resolve(ProposedEdit(path: "m.typ", search: "= C", replace: ""), text: text) else { Issue.record(); return }
        #expect(missing.contains("not found"))
        guard case .failed(let twice) = AssistantEdits.resolve(ProposedEdit(path: "m.typ", search: "= B", replace: ""), text: text) else { Issue.record(); return }
        #expect(twice.contains("2 times"))
        guard case .failed(let overlap) = AssistantEdits.resolve(ProposedEdit(path: "m.typ", search: "aa", replace: ""), text: "aaa") else { Issue.record(); return }
        #expect(overlap.contains("2 times"))
    }

    @Test func rejectsUnsafeOrMissingPaths() {
        for p in ["../x.typ", "/etc/x.typ", "img.png"] {
            guard case .failed = AssistantEdits.resolve(ProposedEdit(path: p, search: "", replace: "x"), text: nil) else { Issue.record("\(p)"); continue }
        }
        guard case .failed(let m) = AssistantEdits.resolve(ProposedEdit(path: "gone.typ", search: "x", replace: ""), text: nil) else { Issue.record(); return }
        #expect(m.contains("does not exist"))
    }
}

@Suite struct AssistantContextTests {
    @Test func filesAreDelimitedWithPaths() throws {
        #expect(try AssistantContext.files([]) == nil)
        let block = try #require(try AssistantContext.files([.init(path: "main.typ", text: "= Hi"), .init(path: "refs.bib", text: "@a{}")]))
        #expect(block.contains("<file path=\"main.typ\">\n= Hi\n</file>") && block.contains("<file path=\"refs.bib\">\n@a{}\n</file>"))
    }

    @Test func sizeGuardRefusesAndNamesTheLargestFiles() {
        let files = [AssistantContext.File(path: "small.typ", text: "x"), .init(path: "big.typ", text: String(repeating: "y", count: AssistantContext.budget))]
        #expect(throws: AssistantError.contextTooLarge(characters: AssistantContext.budget + 1, largest: ["big.typ", "small.typ"])) { try AssistantContext.files(files) }
    }

    @Test func selectionNamesFileAndLines() {
        let text = "one\ntwo\nthree\n"
        #expect(AssistantContext.selection(path: "a.typ", in: text, range: NSRange(location: 4, length: 9)) == "Selected text (a.typ, lines 2–3):\n```\ntwo\nthree\n```")
        #expect(AssistantContext.selection(path: "a.typ", in: text, range: NSRange(location: 4, length: 3)) == "Selected text (a.typ, line 2):\n```\ntwo\n```")
        #expect(AssistantContext.selection(path: "a.typ", in: text, range: NSRange(location: 4, length: 0)) == nil)
    }

    @Test func diagnosticsAndSystemPrompt() {
        #expect(AssistantContext.diagnostics([]) == nil)
        #expect(AssistantContext.diagnostics([.init(path: "a.typ", line: 3, message: "unknown variable: x")]) == "Compiler errors:\n- a.typ, line 3: unknown variable: x")
        for marker in ["<<<<<<< SEARCH", "=======", ">>>>>>> REPLACE", "exactly once", "new file"] { #expect(AssistantContext.systemPrompt.contains(marker)) }
        // A question must not produce an edit: both prompts say so (a small on-device model once turned a question into one).
        for prompt in [AssistantContext.systemPrompt, OnDeviceContext.systemPrompt] { #expect(prompt.contains("question never")) }
    }
}

@Suite struct AssistantConversationTests {
    @Test func titleRule() {
        #expect(AssistantConversation.title(from: "\n  Fix my table  \nmore") == "Fix my table")
        #expect(AssistantConversation.title(from: "   ") == "New Conversation")
        let long = "Please rewrite the introduction so that it reads more naturally and flows"
        let t = AssistantConversation.title(from: long)
        #expect(t == "Please rewrite the introduction so that it reads…" && t.count <= 51)
    }

    @Test func wireMessagesSkipFailuresAndAlternate() {
        var c = AssistantConversation(providerID: nil, model: "m")
        var failed = AssistantMessage(role: .assistant, text: "partial")
        failed.error = "boom"
        c.messages = [.init(role: .user, text: "a", context: "CTX"), failed, .init(role: .user, text: "b"), .init(role: .assistant, text: "c")]
        #expect(c.wireMessages() == [.init(role: .user, text: "CTX\n\na\n\nb"), .init(role: .assistant, text: "c")])
    }

    @Test func saveLoadArchiveDeleteRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "assistant-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AssistantConversationStore(folder: folder)
        var a = AssistantConversation(providerID: UUID(), model: "m", now: Date(timeIntervalSince1970: 1_000))
        var msg = AssistantMessage(role: .assistant, text: "x")
        msg.edits = [0: .accepted, 2: .rejected]
        a.messages = [.init(role: .user, text: "hi"), msg]
        let b = AssistantConversation(providerID: nil, model: "n", now: Date(timeIntervalSince1970: 2_000))
        try store.save(a)
        try store.save(b)
        #expect(store.loadAll() == [b, a])
        a.archived = true
        try store.save(a)
        #expect(store.loadAll().first { $0.id == a.id }?.archived == true)
        store.delete(b.id)
        #expect(store.loadAll().map(\.id) == [a.id])
        #expect(AssistantConversationStore(folder: nil).loadAll().isEmpty)
    }

    @Test func keyStoreDouble() throws {
        let keys: any AssistantKeyStoring = InMemoryAssistantKeys()
        let id = UUID()
        #expect(keys.key(for: id) == nil)
        try keys.setKey("k1", for: id, label: "x")
        try keys.setKey("k2", for: id, label: "x")
        #expect(keys.key(for: id) == "k2")
        keys.removeKey(for: id)
        #expect(keys.key(for: id) == nil)
    }

    @Test func providerConfigHoldsNoKey() throws {
        let data = try JSONEncoder().encode([AssistantProvider(preset: .anthropic)])
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.lowercased().contains("key\":\"sk") && json.contains("claude-opus-5-5"))
        #expect(try JSONDecoder().decode([AssistantProvider].self, from: data).first?.presetID == "anthropic")
    }
}

@Suite struct AssistantOnDeviceTests {
    @Test func availabilityMapsToRowStatus() {
        #expect(OnDeviceAvailability.available.isAvailable && OnDeviceAvailability.available.status == "Runs on this Mac")
        #expect(OnDeviceAvailability.appleIntelligenceNotEnabled.status == "Turn on Apple Intelligence in System Settings")
        for a in [OnDeviceAvailability.deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady] { #expect(!a.isAvailable && !a.status.isEmpty) }
    }

    @Test func sectionAroundTheCaret() {
        let text = "intro\n= One\na\n== Sub\nb\n= Two\nc\n"
        let ns = text as NSString
        #expect(ns.substring(with: OnDeviceContext.section(around: ns.range(of: "a").location, in: text)) == "= One\na\n== Sub\nb\n")
        #expect(ns.substring(with: OnDeviceContext.section(around: ns.range(of: "b").location, in: text)) == "== Sub\nb\n")
        #expect(ns.substring(with: OnDeviceContext.section(around: 0, in: text)) == "intro\n")
        #expect(ns.substring(with: OnDeviceContext.section(around: ns.length, in: text)) == "= Two\nc\n")
    }

    @Test func longSectionIsCutToWholeLinesAroundTheCaretAndSaysSo() {
        let text = "= H\n" + (1...50).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let caret = (text as NSString).range(of: "line 25").location
        let p = OnDeviceContext.passage(path: "a.typ", text: text, selection: NSRange(location: caret, length: 0), limit: 40)
        #expect(!p.isSelection && p.text.count <= 40 && p.text.contains("line 25") && p.text.hasSuffix("\n"))
        #expect(p.label.hasPrefix("Part of the section around the cursor (a.typ, lines"))
        let sel = OnDeviceContext.passage(path: "a.typ", text: text, selection: NSRange(location: caret, length: 7), limit: 40)
        #expect(sel == .init(label: "Selected text (a.typ, line 26)", text: "line 25", isSelection: true))
    }

    @Test func requestFitsTheBudgetOrRefuses() throws {
        let passage = OnDeviceContext.Passage(label: "Selected text (a.typ, line 1)", text: "Hello", isSelection: true)
        let history: [AssistantRequest.Message] = [.init(role: .user, text: String(repeating: "x", count: 500)), .init(role: .assistant, text: "ok"),
                                                   .init(role: .user, text: "q1"), .init(role: .assistant, text: "a1")]
        let budget = OnDeviceContext.systemPrompt.count + 300
        let r = try OnDeviceContext.request(question: "Fix it", history: history, passage: passage, diagnostics: "Compiler errors:\n- x", reference: "Typst reference:\nR", budget: budget)
        #expect(r.system == OnDeviceContext.systemPrompt && r.files == nil)
        #expect(r.messages.map(\.text).dropLast() == ["q1", "a1"])    // the long first turn did not fit
        let last = try #require(r.messages.last?.text)
        #expect(last.hasPrefix("(Earlier messages") && last.contains("Selected text (a.typ, line 1):\n```\nHello\n```") && last.contains("- x")
                && last.contains("Typst reference") && last.hasSuffix("Fix it"))
        #expect(throws: AssistantError.passageTooLarge) {
            try OnDeviceContext.request(question: "Fix it", history: [], passage: .init(label: "S", text: String(repeating: "y", count: 400), isSelection: true),
                                        diagnostics: nil, reference: nil, budget: budget)
        }
        #expect(OnDeviceContext.characterBudget(contextTokens: OnDeviceContext.fallbackContextTokens) == 6144)
    }

    @Test func questionsGetTheirOwnPromptWithoutTheEditFormat() throws {
        #expect(!OnDeviceContext.questionPrompt.contains("SEARCH") && OnDeviceContext.systemPrompt.contains("<<<<<<< SEARCH"))
        #expect(OnDeviceContext.asksForChange(classifierReply: "CHANGE") && OnDeviceContext.asksForChange(classifierReply: " change.\n"))
        #expect(!OnDeviceContext.asksForChange(classifierReply: "QUESTION") && !OnDeviceContext.asksForChange(classifierReply: "")
                && !OnDeviceContext.asksForChange(classifierReply: "QUESTION or CHANGE"))
        #expect(OnDeviceContext.questionTurn("How?", context: nil) == "How?")
        let turn = OnDeviceContext.questionTurn("How?", context: "S:\n```\nx\n```")
        #expect(turn.hasPrefix("Question: How?") && turn.hasSuffix("Answer the question: How?") && turn.contains("```\nx\n```"))
        let r = try OnDeviceContext.request(question: turn, history: [], passage: nil, diagnostics: nil, reference: nil, budget: 6144, system: OnDeviceContext.questionPrompt)
        #expect(r.system == OnDeviceContext.questionPrompt && r.messages.last?.text == turn)
        #expect(OnDeviceContext.classifierRequest("x").system == OnDeviceContext.classifierPrompt)
    }

    @Test func clientTurnsSnapshotsIntoDeltasAndRefusals() async throws {
        let ok = OnDeviceClient { _, prompt in
            AsyncThrowingStream { c in for s in ["He", "Hello", "Hello!"] { c.yield(s) }; c.finish() }
        }
        let r = AssistantRequest(model: "", system: "S", files: nil, messages: [.init(role: .user, text: "a"), .init(role: .assistant, text: "b"), .init(role: .user, text: "c")])
        #expect(try await collect(ok.stream(r)) == [.text("He"), .text("llo"), .text("!"), .done(.endTurn, nil)])
        #expect(OnDeviceClient.prompt(r.messages) == "Earlier in this conversation:\nUser: a\n\nAssistant: b\n\nNow:\nc")
        let declined = OnDeviceClient { _, _ in AsyncThrowingStream { $0.finish(throwing: AssistantError.declined) } }
        #expect(try await collect(declined.stream(r)) == [.done(.refusal, nil)])
    }
}

@Suite struct AssistantReferenceTests {
    @Test func candidatesRankQuestionThenCountThenFirstUse() {
        let text = "#set text(size: 10pt)\n#figure(image(\"a.png\"))\n$ frac(1, 2) + calc.pow(2, 3) $ #figure[x] #let f(x) = x\n#text[y]"
        let all = NSRange(location: 0, length: (text as NSString).length)
        let names = AssistantReference.candidates(in: text, range: all, question: "How does frac work?").map(\.name)
        #expect(names.first == "frac")
        #expect(Array(names.dropFirst().prefix(2)) == ["text", "figure"])    // twice each; text is used first
        #expect(names.contains("image") && names.contains("calc.pow") && names.contains("f") && !names.contains("set") && !names.contains("let"))
        let c = AssistantReference.candidates(in: text, range: all, question: "").first { $0.name == "image" }!
        #expect((text as NSString).substring(with: NSRange(location: c.offset, length: 4)) == "mage")
        #expect(AssistantReference.candidates(in: text, range: all, question: "", limit: 2).count == 2)
    }

    @Test func blockKeepsWhatFitsInOrder() {
        let e = [AssistantReference.Entry(name: "a", text: String(repeating: "a", count: 30)), .init(name: "b", text: String(repeating: "b", count: 100)), .init(name: "c", text: "c")]
        let block = AssistantReference.block(e, budget: 60)
        #expect(block == "Typst reference:\n\n" + String(repeating: "a", count: 30) + "\n\nc\n")
        #expect(AssistantReference.block(e, budget: 10) == nil)
        #expect(AssistantReference.entry(name: "x", signature: "x(a: int)", docs: "First para.\n\nMore.") == .init(name: "x", text: "```typst\nx(a: int)\n```\nFirst para."))
        #expect(AssistantReference.entry(name: "x", signature: nil, docs: nil) == nil)
    }
}

@Suite struct AssistantSearchTests {
    private func searching(_ model: String) -> AssistantRequest {
        var r = request
        r.model = model
        r.tools = [.webSearch]
        return r
    }

    @Test func supportDependsOnProviderAndModel() {
        func p(_ id: String) -> AssistantProvider { provider(id) }
        #expect(AssistantPermissions.supportsWebSearch(provider: p("anthropic"), model: "claude-opus-5-5"))
        #expect(!AssistantPermissions.supportsWebSearch(provider: p("anthropic"), model: "other"))
        #expect(AssistantPermissions.supportsWebSearch(provider: p("openrouter"), model: "anthropic/claude-sonnet-5.5"))
        #expect(AssistantPermissions.supportsWebSearch(provider: p("opencode-zen"), model: "gpt-6-luna"))
        #expect(AssistantPermissions.supportsWebSearch(provider: p("opencode-zen"), model: "gemini-4-argon"))
        #expect(AssistantPermissions.supportsWebSearch(provider: p("opencode-zen"), model: "claude-opus-5-5"))
        for (id, model) in [("opencode-go", "kimi-k3"), ("openai", "gpt-6"), ("deepseek", "deepseek-chat"), ("moonshot", "kimi"), ("ollama", "llama"),
                            ("custom-local", "x"), ("on-device", "Apple Foundation Model")] {
            #expect(!AssistantPermissions.supportsWebSearch(provider: p(id), model: model), "\(id)")
        }
    }

    @Test func anthropicToolOnlyForClaudeWhenEnabled() throws {
        let direct = AnthropicClient(provider: provider("anthropic"), key: "k", transport: StubTransport(chunks: []).transport)
        let tools = try #require(body(try direct.urlRequest(searching("claude-opus-5-5")))["tools"] as? [[String: Any]])
        #expect(tools.count == 1 && tools[0]["type"] as? String == "web_search_20260209" && tools[0]["name"] as? String == "web_search" && tools[0]["max_uses"] as? Int == 5)
        var off = request; off.model = "claude-opus-5-5"
        #expect(body(try direct.urlRequest(off))["tools"] == nil)
        #expect(body(try direct.urlRequest(searching("qwen3.8-max")))["tools"] == nil)
        let gateway = OpenCodeClient(provider: provider("opencode-go"), key: "k", transport: StubTransport(chunks: []).transport)
        let route = GatewayRoute(api: .messages, base: "https://g/anthropic/v1", maxOutput: nil)
        #expect(body(try gateway.urlRequest(searching("claude-haiku-5-5"), route: route).0)["tools"] != nil)
        #expect(body(try gateway.urlRequest(searching("qwen3.8-max"), route: route).0)["tools"] == nil)
    }

    @Test func otherWiresCarryTheirOwnTool() throws {
        let responses = body(ResponsesWire.request(searching("gpt-6-luna"), url: URL(string: "https://g/r")!, key: "k", maxOutput: nil))
        #expect((responses["tools"] as? [[String: String]]) == [["type": "web_search"]])
        let gemini = body(GeminiWire.request(searching("gemini-4-argon"), url: URL(string: "https://g/m")!, key: "k", maxOutput: nil))
        #expect(((gemini["tools"] as? [[String: Any]])?.first)?["google_search"] != nil)
        let router = OpenAICompatibleClient(provider: provider("openrouter"), key: "k", transport: StubTransport(chunks: []).transport)
        #expect((body(try router.urlRequest(searching("m")))["plugins"] as? [[String: String]]) == [["id": "web"]])
        for id in ["openai", "deepseek", "ollama"] {
            let c = OpenAICompatibleClient(provider: provider(id), key: "k", transport: StubTransport(chunks: []).transport)
            let b = body(try c.urlRequest(searching("m")))
            #expect(b["plugins"] == nil && b["tools"] == nil, "\(id)")
        }
        var off = request; off.model = "m"
        #expect(body(ResponsesWire.request(off, url: URL(string: "https://g/r")!, key: "k", maxOutput: nil))["tools"] == nil)
        #expect(body(GeminiWire.request(off, url: URL(string: "https://g/m")!, key: "k", maxOutput: nil))["tools"] == nil)
        #expect(body(try OpenAICompatibleClient(provider: provider("openrouter"), key: "k", transport: StubTransport(chunks: []).transport).urlRequest(off))["plugins"] == nil)
    }

    @Test func serverToolBlocksAreSkippedAndPauseTurnEndsTheAnswer() async throws {
        let stub = StubTransport(chunks: [
            "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"usage\":{\"input_tokens\":5}}}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"server_tool_use\",\"id\":\"s1\",\"name\":\"web_search\",\"input\":{}}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"que\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"ry\\\":\\\"typst 0.14\\\"}\"}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n",
            "data: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"web_search_tool_result\",\"tool_use_id\":\"s1\",\"content\":[]}}\n\n",
            "data: {\"type\":\"content_block_stop\",\"index\":1}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":2,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hi\"}}\n\n",
            "data: {\"type\":\"content_block_delta\",\"index\":2,\"delta\":{\"type\":\"citations_delta\",\"citation\":{\"type\":\"web_search_result_location\"}}}\n\n",
            "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"pause_turn\"},\"usage\":{\"output_tokens\":9}}\n\n",
            "data: {\"type\":\"message_stop\"}\n\n",
        ])
        let c = AnthropicClient(provider: provider("anthropic"), key: "k", transport: stub.transport)
        let events = try await collect(c.stream(searching("claude-opus-5-5")))
        #expect(events == [.reasoning("Searching: typst 0.14\n\n"), .text("Hi"), .done(.paused, AssistantUsage(input: 5, output: 9))])
    }
}

@Suite struct AssistantPermissionTests {
    @Test func defaultsAndOverrides() {
        var global = AssistantPermissions()
        #expect(global.policy(.webSearch) == .ask && global.policy(.diagnostics) == .allow && global.policy(.changeFiles) == .allow
                && global.policy(.createFiles) == .ask && global.policy(.readFiles) == .allow)
        global.set(.webSearch, .never)
        global.set(.readFiles, .never)    // not a choice of this permission: ignored
        #expect(global.policy(.webSearch) == .never && global.policy(.readFiles) == .allow)
        var local = AssistantPermissions()
        local.set(.webSearch, .allow)
        #expect(global.overriding(with: local).policy(.webSearch) == .allow && global.overriding(with: nil).policy(.webSearch) == .never)
    }

    @Test func editsAreFilteredByPermission() {
        let change = ProposedEdit(path: "a.typ", search: "x", replace: "y"), create = ProposedEdit(path: "b.typ", search: "", replace: "z")
        var p = AssistantPermissions()
        #expect(p.mode(change) == .apply && p.mode(create) == .ask)    // creating asks by default
        p.set(.createFiles, .allow)
        #expect(p.mode(create) == .apply)
        p.set(.changeFiles, .ask)
        #expect(p.mode(change) == .ask && p.mode(create) == .ask)      // the stricter wins
        p.set(.changeFiles, .allow)
        p.set(.createFiles, .never)
        #expect(p.mode(change) == .apply && !p.shows(create))
        p.set(.changeFiles, .never)
        #expect(!p.shows(change) && p.mode(change) == .hidden)
    }

    @Test func oldStoredProposeEditsMapsToAskOrNever() throws {
        func decode(_ json: String) throws -> AssistantPermissions { try JSONDecoder().decode(AssistantPermissions.self, from: Data(json.utf8)) }
        let allow = try decode(#"{"policies":{"proposeEdits":"allow","createFiles":"never"}}"#)
        #expect(allow.policy(.changeFiles) == .ask && allow.policy(.createFiles) == .never)
        #expect(try decode(#"{"policies":{"proposeEdits":"never"}}"#).policy(.changeFiles) == .never)
        #expect(try decode(#"{"policies":{"proposeEdits":"allow","changeFiles":"allow"}}"#).policy(.changeFiles) == .allow)
        #expect(try decode(#"{}"#).policy(.changeFiles) == .allow)
        let round = try JSONDecoder().decode(AssistantPermissions.self, from: JSONEncoder().encode(allow))
        #expect(round == allow)
    }

    @Test func changeSummaryTitle() {
        #expect(AssistantChangeSummary.title(changes: 1, files: 1) == "1 Change in 1 File")
        #expect(AssistantChangeSummary.title(changes: 3, files: 2) == "3 Changes in 2 Files")
    }

    @Test func promptWithoutEditsHasNoEditFormat() {
        let plain = AssistantContext.systemPrompt(proposeEdits: false)
        #expect(!plain.contains("SEARCH") && plain.contains("cannot change files"))
        #expect(AssistantContext.systemPrompt(proposeEdits: true) == AssistantContext.systemPrompt)
    }

    @Test func conversationsWithoutPermissionsStillDecode() throws {
        var c = AssistantConversation(providerID: nil, model: "m")
        #expect(c.permissions == nil)
        let old = try JSONEncoder().encode(c)
        #expect(!String(decoding: old, as: UTF8.self).contains("permissions"))
        c.permissions = AssistantPermissions()
        c.permissions?.set(.webSearch, .allow)
        let back = try JSONDecoder().decode(AssistantConversation.self, from: JSONEncoder().encode(c))
        #expect(back.permissions?.policy(.webSearch) == .allow)
        #expect(try JSONDecoder().decode(AssistantConversation.self, from: old).permissions == nil)
    }
}
