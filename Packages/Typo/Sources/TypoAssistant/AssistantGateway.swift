import Foundation
import Synchronization
import TypoKit

/// The protocol a gateway model speaks, with the base URL it is served under.
public struct GatewayRoute: Equatable, Sendable {
    public enum API: String, Sendable { case chatCompletions = "chat-completions", responses, messages, generateContent = "generate-content" }
    public let api: API
    public let base: String
    /// The model's output limit, when the gateway lists one.
    public let maxOutput: Int?

    public var url: String {
        switch api {
        case .chatCompletions: base + "/chat/completions"
        case .responses: base + "/responses"
        case .messages: base + "/messages"
        case .generateContent: base
        }
    }
}

/// OpenCode Zen and Go: one key for models that each keep their own protocol (chat completions, Responses, Anthropic
/// Messages, Gemini). The public model list says which one and where; without it the model id's family decides.
public struct OpenCodeClient: AssistantClient {
    let provider: AssistantProvider
    let key: String?
    let transport: AssistantTransport

    /// One chat model of the list: its route, keyed by id.
    public typealias Catalog = [String: GatewayRoute]

    private static let cache = Mutex<[String: (fetched: Date, catalog: Catalog)]>([:])

    /// Reads `{base}/v1/models`: chat models only, each with its recommended protocol (Gemini through generate-content).
    public static func parseCatalog(_ data: Data) -> Catalog {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let list = obj["data"] as? [[String: Any]] else { return [:] }
        var out: Catalog = [:]
        for m in list where m["type"] as? String == "chat" {
            guard let id = m["id"] as? String, let apis = m["api"] as? [String: Any] else { continue }
            let output = (m["limit"] as? [String: Any])?["output"] as? Int
            let preferred = [m["recommended_api"] as? String, "generate-content", "chat-completions", "messages", "responses"].compactMap { $0 }
            for name in preferred {
                guard let api = GatewayRoute.API(rawValue: name), let base = (apis[name] as? [String: Any])?["base_url"] as? String else { continue }
                out[id] = GatewayRoute(api: api, base: base, maxOutput: output)
                break
            }
        }
        return out
    }

    /// The route by the model's family, for a model the list does not have (or when the list is unreachable).
    public static func fallbackRoute(_ model: String, root: String) -> GatewayRoute {
        let root = root.hasSuffix("/") ? String(root.dropLast()) : root
        if model.hasPrefix("claude") { return GatewayRoute(api: .messages, base: root + "/anthropic/v1", maxOutput: nil) }
        if ["gpt", "grok", "muse"].contains(where: model.hasPrefix) { return GatewayRoute(api: .responses, base: root + "/openai/v1", maxOutput: nil) }
        if model.hasPrefix("gemini") { return GatewayRoute(api: .generateContent, base: root + "/google/v1beta", maxOutput: nil) }
        return GatewayRoute(api: .chatCompletions, base: root + "/openai/v1", maxOutput: nil)
    }

    func catalog() async -> Catalog {
        let base = provider.baseURL
        if let hit = Self.cache.withLock({ $0[base] }), hit.fetched.timeIntervalSinceNow > -3600 { return hit.catalog }
        guard let url = try? AssistantHTTP.url(base, "/v1/models"),
              let resp = try? await send(URLRequest(url: url), transport), (200..<300).contains(resp.status),
              let body = try? await AssistantHTTP.collect(resp.body) else { return [:] }
        let catalog = Self.parseCatalog(body)
        if !catalog.isEmpty { Self.cache.withLock { $0[base] = (Date(), catalog) } }
        return catalog
    }

    func route(_ model: String) async -> GatewayRoute {
        await catalog()[model] ?? Self.fallbackRoute(model, root: provider.baseURL)
    }

    /// The request for `r` over `route`, with OpenCode's client headers, and the decoder for its stream.
    public func urlRequest(_ r: AssistantRequest, route: GatewayRoute) throws -> (URLRequest, @Sendable (inout DecodeState, SSEEvent) throws -> [AssistantEvent]) {
        guard let url = URL(string: route.url) else { throw AssistantError.missingBaseURL }
        var req: URLRequest
        let decode: @Sendable (inout DecodeState, SSEEvent) throws -> [AssistantEvent]
        switch route.api {
        case .chatCompletions:
            req = try OpenAICompatibleClient(provider: provider, key: key, transport: transport, endpoint: url).urlRequest(r)
            decode = OpenAICompatibleClient.decode
        case .messages:
            req = try AnthropicClient(provider: provider, key: key, transport: transport, endpoint: url, maxOutput: route.maxOutput, gateway: true).urlRequest(r)
            decode = AnthropicClient.decode
        case .responses:
            req = ResponsesWire.request(r, url: url, key: key, maxOutput: route.maxOutput)
            decode = ResponsesWire.decode
        case .generateContent:
            guard let gemini = URL(string: route.base + "/models/\(r.model):streamGenerateContent?alt=sse") else { throw AssistantError.missingBaseURL }
            req = GeminiWire.request(r, url: gemini, key: key, maxOutput: route.maxOutput)
            decode = GeminiWire.decode
        }
        // OpenCode Go refuses clients without their own name and a stable session per conversation.
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(r.session ?? UUID().uuidString, forHTTPHeaderField: "x-opencode-session")
        return (req, decode)
    }

    /// A 400 about tools on a Gemini request that carries both the search tool and function declarations.
    static func rejectsSearchWithFunctions(_ route: GatewayRoute, _ r: AssistantRequest, _ message: String) -> Bool {
        route.api == .generateContent && r.tools.contains(.webSearch) && !r.clientTools.isEmpty && message.lowercased().contains("tool")
    }

    static let userAgent = "Typo/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"

    public func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    let route = await route(request.model)
                    var request = request, yielded = false
                    while true {
                        let (req, decode) = try urlRequest(request, route: route)
                        do {
                            for try await e in run(req, model: request.model, key: key, transport: transport, handle: decode) { yielded = true; c.yield(e) }
                            break
                        } catch AssistantError.badRequest(let why) where !yielded && Self.rejectsSearchWithFunctions(route, request, why) {
                            // Some Gemini models refuse google_search next to function declarations; the project tools win.
                            request.tools.remove(.webSearch)
                            c.yield(.reasoning("This model cannot search the web and use project tools together; the web search is off for this answer.\n\n"))
                        }
                    }
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    public func models() async throws -> [String] {
        let list = await catalog()
        guard !list.isEmpty else { throw AssistantError.unreadable(String(localized: "The model list could not be loaded.", bundle: .module)) }
        return list.keys.sorted()
    }
}

/// OpenAI's Responses API (GPT, Grok and Muse on OpenCode).
enum ResponsesWire {
    static func request(_ r: AssistantRequest, url: URL, key: String?, maxOutput: Int?) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(key ?? "")", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": r.model,
            "instructions": [r.system, r.files].compactMap { $0 }.joined(separator: "\n\n"),
            "input": r.messages.flatMap { m -> [[String: Any]] in
                m.results.map { ["type": "function_call_output", "call_id": $0.callID, "output": $0.content] }
                    + m.results.compactMap { r in
                        r.image.map { ["role": "user", "content": [["type": "input_text", "text": "Image returned by the tool call \(r.callID):"], ["type": "input_image", "image_url": "data:image/png;base64," + $0.base64EncodedString()]]] as [String: Any] }
                    }
                    + (m.text.isEmpty && !(m.calls.isEmpty && m.results.isEmpty) ? [] : [["role": m.role.rawValue, "content": m.text]])
                    + m.calls.map { ["type": "function_call", "call_id": $0.id, "name": $0.name, "arguments": $0.arguments] }
            },
            "stream": true,
        ]
        if let maxOutput { body["max_output_tokens"] = maxOutput }
        var tools: [[String: Any]] = r.tools.contains(.webSearch) ? [["type": "web_search"]] : []
        tools += r.clientTools.map { ["type": "function", "name": $0.rawValue, "description": $0.summary, "parameters": $0.schema] }
        if !tools.isEmpty { body["tools"] = tools }
        req.httpBody = AssistantHTTP.json(body)
        return req
    }

    static func decode(_ s: inout DecodeState, _ e: SSEEvent) throws -> [AssistantEvent] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(e.data.utf8)) as? [String: Any] else { return [] }
        let response = obj["response"] as? [String: Any]
        func usage() {
            guard let u = response?["usage"] as? [String: Any] else { return }
            s.usage = AssistantUsage(input: u["input_tokens"] as? Int, output: u["output_tokens"] as? Int)
        }
        switch obj["type"] as? String {
        case "response.output_text.delta":
            if let t = obj["delta"] as? String, !t.isEmpty { return [.text(t)] }
        case "response.reasoning_summary_text.delta":
            if let t = obj["delta"] as? String, !t.isEmpty { return [.reasoning(t)] }
        case "response.output_item.done":
            if let item = obj["item"] as? [String: Any], item["type"] as? String == "function_call", let name = item["name"] as? String {
                let args = item["arguments"] as? String ?? ""
                return [.toolCall(ToolCall(id: item["call_id"] as? String ?? UUID().uuidString, name: name, arguments: args.isEmpty ? "{}" : args))]
            }
        case "response.refusal.delta":
            s.stopReason = .refusal
        case "response.completed":
            usage()
            s.finished = true
            return [.done(s.stopReason ?? .endTurn, s.usage)]
        case "response.incomplete":
            usage()
            let reason = (response?["incomplete_details"] as? [String: Any])?["reason"] as? String ?? ""
            s.finished = true
            return [.done(reason == "max_output_tokens" ? .maxTokens : reason == "content_filter" ? .refusal : .other(reason), s.usage)]
        case "response.failed":
            let message = (response?["error"] as? [String: Any])?["message"] as? String ?? String(localized: "The answer failed.", bundle: .module)
            throw AssistantError.server(status: 500, message: message)
        case "error":
            throw AssistantError.badRequest(obj["message"] as? String ?? (obj["error"] as? [String: Any])?["message"] as? String ?? "")
        default: break
        }
        return []
    }
}

/// Gemini's streamGenerateContent with server-sent events.
enum GeminiWire {
    static func request(_ r: AssistantRequest, url: URL, key: String?, maxOutput: Int?) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        // The gateway's docs only show Bearer; Google's own header is sent too, to the same host.
        req.setValue("Bearer \(key ?? "")", forHTTPHeaderField: "Authorization")
        req.setValue(key ?? "", forHTTPHeaderField: "x-goog-api-key")
        var body: [String: Any] = [
            "systemInstruction": ["parts": [["text": [r.system, r.files].compactMap { $0 }.joined(separator: "\n\n")]]],
            "contents": contents(r.messages),
        ]
        if let maxOutput { body["generationConfig"] = ["maxOutputTokens": maxOutput] }
        var tools: [[String: Any]] = r.tools.contains(.webSearch) ? [["google_search": [String: String]()]] : []
        if !r.clientTools.isEmpty { tools.append(["functionDeclarations": r.clientTools.map(declaration)]) }
        if !tools.isEmpty { body["tools"] = tools }
        req.httpBody = AssistantHTTP.json(body)
        return req
    }

    /// Google's function declaration; a tool without arguments has no `parameters`.
    static func declaration(_ t: ClientTool) -> [String: Any] {
        var d: [String: Any] = ["name": t.rawValue, "description": t.summary]
        if !((t.schema["properties"] as? [String: Any])?.isEmpty ?? true) { d["parameters"] = t.schema }
        return d
    }

    /// The conversation as Gemini's turns: a model turn keeps its `functionCall` parts, and the results go back as
    /// `functionResponse` parts of a user turn (an image beside them as `inlineData`).
    static func contents(_ messages: [AssistantRequest.Message]) -> [[String: Any]] {
        var names: [String: String] = [:]
        for m in messages { for c in m.calls { names[c.id] = c.name } }
        return messages.map { m in
            var parts: [[String: Any]] = m.results.map {
                ["functionResponse": ["name": names[$0.callID] ?? "tool", "response": [$0.isError ? "error" : "result": $0.content]] as [String: Any]]
            }
            parts += m.results.compactMap { r in r.image.map { ["inlineData": ["mimeType": "image/png", "data": $0.base64EncodedString()]] } }
            if !m.text.isEmpty { parts.append(["text": m.text]) }
            parts += m.calls.map { c in
                var part: [String: Any] = ["functionCall": ["name": c.name, "args": c.input]]
                if let sig = c.signature { part["thoughtSignature"] = sig }
                return part
            }
            if parts.isEmpty { parts = [["text": m.text]] }
            return ["role": m.role == .assistant ? "model" : "user", "parts": parts]
        }
    }

    /// No end marker: the stream closes after the chunk with a finish reason, which `run` then reports.
    static func decode(_ s: inout DecodeState, _ e: SSEEvent) throws -> [AssistantEvent] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(e.data.utf8)) as? [String: Any] else { return [] }
        if let err = obj["error"] as? [String: Any] { throw AssistantError.badRequest(err["message"] as? String ?? "") }
        if let u = obj["usageMetadata"] as? [String: Any] {
            s.usage = AssistantUsage(input: u["promptTokenCount"] as? Int, output: u["candidatesTokenCount"] as? Int)
        }
        if (obj["promptFeedback"] as? [String: Any])?["blockReason"] != nil {
            s.stopReason = .refusal
            return []
        }
        guard let candidate = (obj["candidates"] as? [[String: Any]])?.first else { return [] }
        var out: [AssistantEvent] = []
        for part in ((candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? [] {
            if let f = part["functionCall"] as? [String: Any], let name = f["name"] as? String {
                let args = (try? JSONSerialization.data(withJSONObject: f["args"] ?? [String: Any](), options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                out.append(.toolCall(ToolCall(id: f["id"] as? String ?? UUID().uuidString, name: name, arguments: args, signature: part["thoughtSignature"] as? String)))
                continue
            }
            guard let t = part["text"] as? String, !t.isEmpty else { continue }
            out.append(part["thought"] as? Bool == true ? .reasoning(t) : .text(t))
        }
        if let f = candidate["finishReason"] as? String {
            s.stopReason = switch f {
            case "STOP": .endTurn
            case "MAX_TOKENS": .maxTokens
            case "SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "RECITATION": .refusal
            default: .other(f)
            }
        }
        return out
    }
}
