import Foundation
import TypoKit

// MARK: - Errors and events

public enum AssistantError: Error, Equatable, Sendable {
    case invalidKey
    case unknownModel(String)
    /// `retryAfter` nil: no retry-after header, as with a spend cap; retrying will not help soon.
    case rateLimited(retryAfter: TimeInterval?)
    /// 5xx and 529: the provider is overloaded or failing; worth a retry.
    case server(status: Int, message: String)
    case badRequest(String)
    case http(status: Int, message: String)
    case offline(String)
    case unreadable(String)
    case keychain(String)
    case missingBaseURL
    /// The attached files exceed the budget; the paths are the largest first.
    case contextTooLarge(characters: Int, largest: [String])
    /// The on-device request does not fit the model's window.
    case passageTooLarge
    /// The on-device model's guardrails declined; the client turns this into a refusal stop.
    case declined
    case onDevice(String)
    /// An agent's failure, already worded for the panel.
    case agent(String)

    public var message: String {
        switch self {
        case .invalidKey: String(localized: "The API key was rejected. Check it in Settings › Intelligence.", bundle: .module)
        case .unknownModel(let m): String(localized: "The model “\(m)” is not known to this provider or not available to your account.", bundle: .module)
        case .rateLimited(let after?): String(localized: "The provider's rate limit was reached. Try again in \(Int(after.rounded(.up))) seconds.", bundle: .module)
        case .rateLimited(nil): String(localized: "The provider's rate limit or spending limit was reached.", bundle: .module)
        case .server(let status, let m): String(localized: "The provider is unavailable (HTTP \(status)). \(m)", bundle: .module).trimmingCharacters(in: .whitespaces)
        case .badRequest(let m): String(localized: "The provider rejected the request: \(m)", bundle: .module)
        case .http(let status, let m): String(localized: "The provider answered with HTTP \(status). \(m)", bundle: .module).trimmingCharacters(in: .whitespaces)
        case .offline(let m): String(localized: "The provider could not be reached. \(m)", bundle: .module)
        case .unreadable(let m): String(localized: "The provider's answer could not be read. \(m)", bundle: .module)
        case .keychain(let m): String(localized: "The key could not be saved in the Keychain: \(m)", bundle: .module)
        case .missingBaseURL: String(localized: "This provider has no base URL. Enter it in Settings › Intelligence.", bundle: .module)
        case .contextTooLarge(let n, let largest):
            String(localized: "The attached files hold \(n.formatted()) characters, more than can be sent at once. Detach some files, for example \(largest.prefix(3).joined(separator: ", ")).", bundle: .module)
        case .passageTooLarge: String(localized: "This is too long for the on-device model. Select a smaller passage and ask again.", bundle: .module)
        case .declined: String(localized: "The model declined to answer this request.", bundle: .module)
        case .onDevice(let m), .agent(let m): m
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .server, .offline: true
        case .rateLimited(let after): after != nil
        default: false
        }
    }
}

public enum AssistantStopReason: Equatable, Sendable {
    case endTurn, maxTokens, refusal
    /// The model stopped to call client-side tools.
    case toolUse
    /// The provider's server-side tool loop hit its limit (Anthropic `pause_turn`); the answer so far is all there is.
    case paused
    case other(String)
}

public struct AssistantUsage: Equatable, Sendable {
    public var input: Int?
    public var output: Int?
}

public enum AssistantEvent: Equatable, Sendable {
    case text(String)
    case reasoning(String)
    /// A finished call of a client-side tool (`ClientTool`).
    case toolCall(ToolCall)
    /// A call the client ran itself (the on-device framework's loop) with its result; the agent loop only shows it.
    case toolRan(ToolCall, ToolResult)
    case done(AssistantStopReason, AssistantUsage?)
}

/// What one turn sends: the stable prefix (system prompt, then the attached files) before the conversation.
public struct AssistantRequest: Sendable, Equatable {
    public struct Message: Sendable, Equatable {
        public enum Role: String, Sendable { case user, assistant }
        public var role: Role
        public var text: String
        /// Assistant turns: the tool calls it made. User turns: the results answering the turn before.
        public var calls: [ToolCall] = []
        public var results: [ToolResult] = []
        public init(role: Role, text: String, calls: [ToolCall] = [], results: [ToolResult] = []) {
            self.role = role; self.text = text; self.calls = calls; self.results = results
        }
    }
    public var model: String
    public var system: String
    /// The attached files block, or nil without files.
    public var files: String?
    /// Alternating user/assistant turns, ending with a user turn.
    public var messages: [Message]
    /// The conversation's id; gateways that bill per session (OpenCode Go) need it on every turn.
    public var session: String?
    /// Server-side tools switched on for this turn; the caller has checked that the model supports them.
    public var tools: Set<AssistantTool> = []
    /// Client-side tools the model may call; the caller has checked that the model supports function calling.
    public var clientTools: [ClientTool] = []
    public init(model: String, system: String, files: String?, messages: [Message]) {
        self.model = model; self.system = system; self.files = files; self.messages = messages
    }
}

// MARK: - Transport

public struct AssistantHTTPResponse: Sendable {
    public let status: Int
    /// Lowercased names.
    public let headers: [String: String]
    public let body: AsyncThrowingStream<Data, Error>
    public init(status: Int, headers: [String: String], body: AsyncThrowingStream<Data, Error>) {
        self.status = status; self.headers = headers; self.body = body
    }
}

/// Performs a request and streams the body. Tests inject stubs; the app uses `urlSession`.
public typealias AssistantTransport = @Sendable (URLRequest) async throws -> AssistantHTTPResponse

public enum AssistantHTTP {
    public static let urlSession: AssistantTransport = { req in
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        let http = resp as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] { headers[String(describing: k).lowercased()] = String(describing: v) }
        let body = AsyncThrowingStream<Data, Error> { c in
            let task = Task {
                do {
                    var line = Data()
                    for try await b in bytes {
                        line.append(b)
                        if b == 0x0A { c.yield(line); line.removeAll(keepingCapacity: true) }
                    }
                    if !line.isEmpty { c.yield(line) }
                    c.finish()
                } catch { c.finish(throwing: error) }
            }
            c.onTermination = { _ in task.cancel() }
        }
        return AssistantHTTPResponse(status: http?.statusCode ?? 0, headers: headers, body: body)
    }

    static func collect(_ body: AsyncThrowingStream<Data, Error>, limit: Int = 1 << 20) async throws -> Data {
        var out = Data()
        for try await chunk in body where out.count < limit { out.append(chunk) }
        return out
    }

    /// Maps a non-2xx answer to a typed error; `key` is scrubbed from any server message.
    static func error(status: Int, headers: [String: String], body: Data, model: String, key: String?) -> AssistantError {
        var message = serverMessage(body) ?? String(decoding: body.prefix(300), as: UTF8.self)
        if let key, !key.isEmpty { message = message.replacingOccurrences(of: key, with: "…") }
        switch status {
        case 401: return .invalidKey
        case 404: return .unknownModel(model)
        case 429: return .rateLimited(retryAfter: headers["retry-after"].flatMap(TimeInterval.init))
        case 400: return .badRequest(message)
        case 500...599: return .server(status: status, message: message)
        default: return .http(status: status, message: message)
        }
    }

    /// Removes the key from messages that came from the server inside a stream.
    static func scrub(_ e: AssistantError, key: String?) -> AssistantError {
        guard let key, !key.isEmpty else { return e }
        switch e {
        case .badRequest(let m): return .badRequest(m.replacingOccurrences(of: key, with: "…"))
        case .server(let s, let m): return .server(status: s, message: m.replacingOccurrences(of: key, with: "…"))
        case .http(let s, let m): return .http(status: s, message: m.replacingOccurrences(of: key, with: "…"))
        default: return e
        }
    }

    /// `error.message` of an Anthropic or OpenAI-style error body.
    static func serverMessage(_ body: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return ((obj["error"] as? [String: Any])?["message"] as? String) ?? (obj["error"] as? String) ?? (obj["message"] as? String)
    }

    static func json(_ object: [String: Any]) -> Data {
        // Sorted keys: identical turns render identical bytes, which prompt caching needs.
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    static func url(_ base: String, _ path: String) throws -> URL {
        let trimmed = base.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let url = URL(string: (trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed) + path), url.scheme != nil else {
            throw AssistantError.missingBaseURL
        }
        return url
    }
}

// MARK: - Server-sent events

public struct SSEEvent: Equatable, Sendable {
    public var event: String?
    public var data: String
}

/// Splits a byte stream into events; chunks may break anywhere, even inside a UTF-8 sequence.
public struct SSEParser: Sendable {
    private var pending = Data()
    private var event: String?
    private var data: [String] = []
    public init() {}

    public mutating func feed(_ chunk: Data) -> [SSEEvent] {
        pending.append(chunk)
        var out: [SSEEvent] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            var line = String(decoding: pending[pending.startIndex..<nl], as: UTF8.self)
            pending.removeSubrange(pending.startIndex...nl)
            if line.hasSuffix("\r") { line.removeLast() }
            if let e = take(line) { out.append(e) }
        }
        return out
    }

    /// The last event when the stream ends without a blank line.
    public mutating func finish() -> [SSEEvent] {
        var out: [SSEEvent] = []
        if !pending.isEmpty, let e = take(String(decoding: pending, as: UTF8.self)) { out.append(e) }
        pending.removeAll()
        if let e = take("") { out.append(e) }
        return out
    }

    private mutating func take(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            defer { event = nil; data = [] }
            return data.isEmpty ? nil : SSEEvent(event: event, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let (field, value) = line.firstIndex(of: ":").map { (String(line[..<$0]), String(line[line.index(after: $0)...])) } ?? (line, "")
        let v = value.hasPrefix(" ") ? String(value.dropFirst()) : value
        switch field {
        case "data": data.append(v)
        case "event": event = v
        default: break
        }
        return nil
    }
}

// MARK: - Clients

/// Runs one tool call for a client that drives its own tool loop (the on-device model); the app answers on the main actor.
public typealias ToolRunner = @MainActor @Sendable (ToolCall) async -> ToolResult

public protocol AssistantClient: Sendable {
    /// Streams one answer. Cancelling the consuming task cancels the request.
    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error>
    /// Like `stream`, for a client that calls `request.clientTools` itself through `run`; others ignore `run`.
    func stream(_ request: AssistantRequest, run: ToolRunner?) -> AsyncThrowingStream<AssistantEvent, Error>
    /// The provider's model ids; throws without a models endpoint.
    func models() async throws -> [String]
}

public enum AssistantClients {
    public static func make(_ provider: AssistantProvider, key: String?, transport: @escaping AssistantTransport = AssistantHTTP.urlSession,
                            onDevice: @escaping OnDeviceGenerate = AppleOnDeviceModel.generate,
                            onDeviceTools: @escaping OnDeviceToolGenerate = AppleOnDeviceModel.generateWithTools) -> any AssistantClient {
        switch provider.preset.wire {
        case .onDevice: OnDeviceClient(generate: onDevice, generateWithTools: onDeviceTools)
        case .anthropic: AnthropicClient(provider: provider, key: key, transport: transport)
        case .openAI: OpenAICompatibleClient(provider: provider, key: key, transport: transport)
        case .openCode: OpenCodeClient(provider: provider, key: key, transport: transport)
        // The live agent needs the window's sessions and host; the assistant builds that client (TypoACP) itself.
        case .acp: AgentOutsidePanel()
        }
    }
}

struct AgentOutsidePanel: AssistantClient {
    func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: AssistantError.agent(String(localized: "Agents answer in the assistant panel only.", bundle: .module))) }
    }

    func models() async throws -> [String] { [] }
}

extension AssistantClient {
    public func stream(_ request: AssistantRequest, run: ToolRunner?) -> AsyncThrowingStream<AssistantEvent, Error> { stream(request) }

    /// Sends the request, maps errors, and feeds each body chunk through SSE into `handle`, which returns events
    /// or nil when the answer is complete.
    func run(_ request: URLRequest, model: String, key: String?, transport: @escaping AssistantTransport,
             handle: @escaping @Sendable (inout DecodeState, SSEEvent) throws -> [AssistantEvent]) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    let resp = try await send(request, transport)
                    guard (200..<300).contains(resp.status) else {
                        throw AssistantHTTP.error(status: resp.status, headers: resp.headers, body: try await AssistantHTTP.collect(resp.body), model: model, key: key)
                    }
                    var parser = SSEParser(), state = DecodeState()
                    for try await chunk in resp.body {
                        for e in parser.feed(chunk) { for out in try handle(&state, e) { c.yield(out) } }
                        if state.finished { break }
                    }
                    if !state.finished { for e in parser.finish() { for out in try handle(&state, e) { c.yield(out) } } }
                    if !state.finished {
                        // Some servers close without a final marker; a stream that got a stop reason still counts.
                        guard let reason = state.stopReason else { throw AssistantError.unreadable(String(localized: "The answer ended early.", bundle: .module)) }
                        c.yield(.done(reason, state.usage))
                    }
                    c.finish()
                } catch let e as AssistantError {
                    c.finish(throwing: AssistantHTTP.scrub(e, key: key))
                } catch {
                    c.finish(throwing: error)
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    func send(_ request: URLRequest, _ transport: AssistantTransport) async throws -> AssistantHTTPResponse {
        do { return try await transport(request) } catch let e as URLError where e.code != .cancelled {
            throw AssistantError.offline(e.localizedDescription)
        }
    }

    func getModels(_ request: URLRequest, transport: AssistantTransport, key: String?) async throws -> [String] {
        let resp = try await send(request, transport)
        let body = try await AssistantHTTP.collect(resp.body)
        guard (200..<300).contains(resp.status) else { throw AssistantHTTP.error(status: resp.status, headers: resp.headers, body: body, model: "", key: key) }
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any], let data = obj["data"] as? [[String: Any]] else {
            throw AssistantError.unreadable(String(localized: "No model list.", bundle: .module))
        }
        return data.compactMap { $0["id"] as? String }
    }
}

/// Per-stream decoding state.
public struct DecodeState: Sendable {
    var stopReason: AssistantStopReason?
    var usage: AssistantUsage?
    var finished = false
    /// Anthropic server tool calls being streamed: content block index to the JSON of its input so far.
    var toolInput: [Int: String] = [:]
    /// Client tool calls being streamed, by content block index (Anthropic) or tool call index (chat completions).
    var calls: [Int: (id: String?, name: String, json: String)] = [:]
}

/// The Anthropic Messages API, raw HTTP (no Swift SDK).
public struct AnthropicClient: AssistantClient {
    public static let version = "2026-10-21"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    public static let maxTokens = 64_000
    let provider: AssistantProvider
    let key: String?
    let transport: AssistantTransport
    /// Set by a gateway: its own URL, a Bearer key, the model's output limit, and none of Anthropic's fallback
    /// parameters (the gateway also serves models that are not Claude).
    var endpoint: URL?
    var maxOutput: Int?
    var gateway = false

    /// Haiku 5.5 has no server-side fallback; the guide says not to send the parameter to it.
    static func usesFallback(_ model: String) -> Bool { !model.hasPrefix("claude-haiku") }

    func headers(_ req: inout URLRequest, model: String?) {
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key ?? "", forHTTPHeaderField: "x-api-key")
        if gateway { req.setValue("Bearer \(key ?? "")", forHTTPHeaderField: "Authorization") }
        req.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        if !gateway, let model, Self.usesFallback(model) { req.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
    }

    public func urlRequest(_ r: AssistantRequest) throws -> URLRequest {
        var req = URLRequest(url: try endpoint ?? AssistantHTTP.url(provider.baseURL, provider.preset.chatPath))
        req.httpMethod = "POST"
        headers(&req, model: r.model)
        let cache: [String: Any] = ["type": "ephemeral"]
        // Breakpoint on the last stable system block (files, else the prompt) and on the newest user turn.
        var system: [[String: Any]] = [["type": "text", "text": r.system]]
        if let files = r.files { system.append(["type": "text", "text": files]) }
        system[system.count - 1]["cache_control"] = cache
        let messages: [[String: Any]] = r.messages.enumerated().map { i, m in
            // Tool results come first in a user turn; empty text blocks are refused.
            var blocks: [[String: Any]] = m.results.map { r in
                let content: Any = r.image.map { [["type": "text", "text": r.content], ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": $0.base64EncodedString()]]] as [[String: Any]] } ?? r.content
                return ["type": "tool_result", "tool_use_id": r.callID, "content": content, "is_error": r.isError]
            }
            if !m.text.isEmpty || (m.calls.isEmpty && m.results.isEmpty) { blocks.append(["type": "text", "text": m.text]) }
            blocks += m.calls.map { ["type": "tool_use", "id": $0.id, "name": $0.name, "input": $0.input] }
            if i == r.messages.count - 1 { blocks[blocks.count - 1]["cache_control"] = cache }
            return ["role": m.role.rawValue, "content": blocks]
        }
        var body: [String: Any] = ["model": r.model, "max_tokens": min(maxOutput ?? Self.maxTokens, Self.maxTokens), "stream": true, "system": system, "messages": messages]
        if !gateway, Self.usesFallback(r.model) { body["fallbacks"] = "default" }
        // The gateway's Messages route also serves models that are not Claude; they get no Anthropic tool.
        var tools: [[String: Any]] = []
        if r.tools.contains(.webSearch), r.model.hasPrefix("claude-") {
            tools.append(["type": "web_search_20260209", "name": "web_search", "max_uses": 5])
        }
        tools += r.clientTools.map { ["name": $0.rawValue, "description": $0.summary, "input_schema": $0.schema] }
        if !tools.isEmpty { body["tools"] = tools }
        req.httpBody = AssistantHTTP.json(body)
        return req
    }

    public func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        do {
            return run(try urlRequest(request), model: request.model, key: key, transport: transport, handle: Self.decode)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    static func decode(_ s: inout DecodeState, _ e: SSEEvent) throws -> [AssistantEvent] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(e.data.utf8)) as? [String: Any] else { return [] }
        switch obj["type"] as? String {
        case "message_start":
            let usage = (obj["message"] as? [String: Any])?["usage"] as? [String: Any]
            s.usage = AssistantUsage(input: usage?["input_tokens"] as? Int, output: nil)
        case "content_block_start":
            if let i = obj["index"] as? Int, let block = obj["content_block"] as? [String: Any] {
                if block["type"] as? String == "server_tool_use" { s.toolInput[i] = "" }
                if block["type"] as? String == "tool_use", let name = block["name"] as? String { s.calls[i] = (block["id"] as? String, name, "") }
            }
        case "content_block_delta":
            let delta = obj["delta"] as? [String: Any]
            switch delta?["type"] as? String {
            case "text_delta": if let t = delta?["text"] as? String { return [.text(t)] }
            case "thinking_delta": if let t = delta?["thinking"] as? String { return [.reasoning(t)] }
            case "input_json_delta":
                guard let i = obj["index"] as? Int, let t = delta?["partial_json"] as? String else { break }
                if s.toolInput[i] != nil { s.toolInput[i]! += t } else if s.calls[i] != nil { s.calls[i]!.json += t }
            default: break    // citations_delta, signature_delta
            }
        case "content_block_stop":
            if let i = obj["index"] as? Int, let c = s.calls.removeValue(forKey: i) {
                return [.toolCall(ToolCall(id: c.id ?? UUID().uuidString, name: c.name, arguments: c.json.isEmpty ? "{}" : c.json))]
            }
            // A finished web search call shows its query; other server blocks (results) stay out of the transcript.
            if let i = obj["index"] as? Int, let json = s.toolInput.removeValue(forKey: i),
               let query = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["query"] as? String {
                return [.reasoning("Searching: \(query)\n\n")]
            }
        case "message_delta":
            if let r = (obj["delta"] as? [String: Any])?["stop_reason"] as? String {
                s.stopReason = switch r {
                case "end_turn", "stop_sequence": .endTurn
                case "max_tokens": .maxTokens
                case "refusal": .refusal
                case "pause_turn": .paused
                case "tool_use": .toolUse
                default: .other(r)
                }
            }
            if let out = (obj["usage"] as? [String: Any])?["output_tokens"] as? Int { s.usage = AssistantUsage(input: s.usage?.input, output: out) }
        case "message_stop":
            s.finished = true
            return [.done(s.stopReason ?? .endTurn, s.usage)]
        case "error":
            let err = obj["error"] as? [String: Any]
            let message = err?["message"] as? String ?? ""
            switch err?["type"] as? String {
            case "overloaded_error": throw AssistantError.server(status: 529, message: message)
            case "api_error": throw AssistantError.server(status: 500, message: message)
            case "rate_limit_error": throw AssistantError.rateLimited(retryAfter: nil)
            case "authentication_error": throw AssistantError.invalidKey
            default: throw AssistantError.badRequest(message)
            }
        default: break    // ping
        }
        return []
    }

    public func models() async throws -> [String] {
        var req = URLRequest(url: try AssistantHTTP.url(provider.baseURL, "/models?limit=100"))
        headers(&req, model: nil)
        return try await getModels(req, transport: transport, key: key)
    }
}

/// OpenAI-compatible Chat Completions: OpenAI, DeepSeek, Kimi, GLM, Qwen, Ollama, LM Studio and custom servers.
public struct OpenAICompatibleClient: AssistantClient {
    let provider: AssistantProvider
    let key: String?
    let transport: AssistantTransport
    /// A gateway's chat completions URL, instead of the preset's path.
    var endpoint: URL?

    func auth(_ req: inout URLRequest) {
        guard let key, !key.isEmpty else { return }
        let header = provider.keyHeader.trimmingCharacters(in: .whitespaces).isEmpty ? "Authorization" : provider.keyHeader
        req.setValue(header.caseInsensitiveCompare("Authorization") == .orderedSame ? "Bearer \(key)" : key, forHTTPHeaderField: header)
    }

    public func urlRequest(_ r: AssistantRequest) throws -> URLRequest {
        var req = URLRequest(url: try endpoint ?? AssistantHTTP.url(provider.baseURL, provider.preset.chatPath))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        auth(&req)
        let system = [r.system, r.files].compactMap { $0 }.joined(separator: "\n\n")
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for m in r.messages {
            for result in m.results { messages.append(["role": "tool", "tool_call_id": result.callID, "content": result.content]) }
            // A tool message cannot carry an image: it follows as a user message.
            for result in m.results { if let png = result.image { messages.append(["role": "user", "content": [["type": "text", "text": "Image returned by the tool call \(result.callID):"], ["type": "image_url", "image_url": ["url": "data:image/png;base64," + png.base64EncodedString()]]]]) } }
            guard !m.text.isEmpty || !m.calls.isEmpty else { continue }
            var turn: [String: Any] = ["role": m.role.rawValue, "content": m.text]
            if !m.calls.isEmpty {
                turn["tool_calls"] = m.calls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]] as [String: Any] }
            }
            messages.append(turn)
        }
        var body: [String: Any] = ["model": r.model, "messages": messages, "stream": true]
        if !r.clientTools.isEmpty {
            body["tools"] = r.clientTools.map { ["type": "function", "function": ["name": $0.rawValue, "description": $0.summary, "parameters": $0.schema] as [String: Any]] as [String: Any] }
        }
        // OpenRouter's web plugin; other chat completions servers have no search.
        if r.tools.contains(.webSearch), provider.presetID == "openrouter" { body["plugins"] = [["id": "web"]] }
        req.httpBody = AssistantHTTP.json(body)
        return req
    }

    public func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        do {
            return run(try urlRequest(request), model: request.model, key: key, transport: transport, handle: Self.decode)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    static func decode(_ s: inout DecodeState, _ e: SSEEvent) throws -> [AssistantEvent] {
        func flushCalls() -> [AssistantEvent] {
            defer { s.calls = [:] }
            return s.calls.sorted { $0.key < $1.key }.map { .toolCall(ToolCall(id: $0.value.id ?? UUID().uuidString, name: $0.value.name, arguments: $0.value.json.isEmpty ? "{}" : $0.value.json)) }
        }
        if e.data == "[DONE]" {
            s.finished = true
            return flushCalls() + [.done(s.stopReason ?? .endTurn, s.usage)]
        }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(e.data.utf8)) as? [String: Any] else { return [] }
        if let err = obj["error"] {
            throw AssistantError.badRequest((err as? [String: Any])?["message"] as? String ?? String(describing: err))
        }
        if let u = obj["usage"] as? [String: Any] {
            s.usage = AssistantUsage(input: u["prompt_tokens"] as? Int, output: u["completion_tokens"] as? Int)
        }
        guard let choice = (obj["choices"] as? [[String: Any]])?.first else { return [] }
        var out: [AssistantEvent] = []
        let delta = choice["delta"] as? [String: Any]
        if let r = delta?["reasoning_content"] as? String, !r.isEmpty { out.append(.reasoning(r)) }
        if let t = delta?["content"] as? String, !t.isEmpty { out.append(.text(t)) }
        for c in delta?["tool_calls"] as? [[String: Any]] ?? [] {
            let i = c["index"] as? Int ?? 0, f = c["function"] as? [String: Any]
            var call = s.calls[i] ?? (nil, "", "")
            if let id = c["id"] as? String, !id.isEmpty { call.id = id }
            if let n = f?["name"] as? String { call.name += n }
            if let a = f?["arguments"] as? String { call.json += a }
            s.calls[i] = call
        }
        if let f = choice["finish_reason"] as? String {
            out += flushCalls()
            s.stopReason = switch f {
            case "tool_calls", "function_call": .toolUse
            case "stop": .endTurn
            case "length": .maxTokens
            case "content_filter": .refusal
            default: .other(f)
            }
        }
        return out
    }

    public func models() async throws -> [String] {
        guard let path = provider.preset.modelsPath else { throw AssistantError.unreadable(String(localized: "This provider does not list its models.", bundle: .module)) }
        var req = URLRequest(url: try AssistantHTTP.url(provider.baseURL, path))
        auth(&req)
        return try await getModels(req, transport: transport, key: key)
    }
}
