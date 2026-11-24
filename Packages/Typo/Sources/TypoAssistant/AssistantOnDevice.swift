import Foundation
import FoundationModels
import Synchronization
import TypoKit

/// Apple's on-device model as the UI sees it.
public enum OnDeviceAvailability: Equatable, Sendable {
    case available, deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady

    public var isAvailable: Bool { self == .available }

    /// The provider row's status line.
    public var status: String {
        switch self {
        case .available: String(localized: "Runs on this Mac", bundle: .module)
        case .deviceNotEligible: String(localized: "This Mac does not support Apple Intelligence", bundle: .module)
        case .appleIntelligenceNotEnabled: String(localized: "Turn on Apple Intelligence in System Settings", bundle: .module)
        case .modelNotReady: String(localized: "The model is still downloading. Try again later.", bundle: .module)
        }
    }
}

/// Streams cumulative snapshots of the answer for instructions and a prompt. Tests replace it.
public typealias OnDeviceGenerate = @Sendable (_ instructions: String, _ prompt: String) -> AsyncThrowingStream<String, Error>

/// Like `OnDeviceGenerate`, with the tools the framework may call while it answers.
public typealias OnDeviceToolGenerate = @Sendable (_ instructions: String, _ prompt: String, _ kit: OnDeviceToolKit) -> AsyncThrowingStream<String, Error>

/// What the on-device tools share: how a call is run (the app asks the user first when the permission says Ask), where each
/// finished call is reported, and the few calls one answer may make.
public final class OnDeviceToolKit: Sendable {
    public static let maxCalls = 3, resultLimit = 1_500
    public let tools: [ClientTool]
    private let run: ToolRunner
    private let report: @Sendable (ToolCall, ToolResult) -> Void
    private let used = Mutex(0)

    public init(tools: [ClientTool], run: @escaping ToolRunner, report: @escaping @Sendable (ToolCall, ToolResult) -> Void) {
        self.tools = tools; self.run = run; self.report = report
    }

    /// The tool's answer for the model: capped to the small window, a refusal when the user denied, and a plain
    /// message once the answer has used its calls.
    public func invoke(_ tool: ClientTool, _ arguments: [String: String] = [:]) async -> String {
        guard used.withLock({ $0 += 1; return $0 }) <= Self.maxCalls else { return "No more tool calls are allowed for this answer. Answer with what you have." }
        let json = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let call = ToolCall(id: UUID().uuidString, name: tool.rawValue, arguments: json)
        let result = await run(call)
        report(call, result)
        return ToolOutput.capped(result.content, limit: Self.resultLimit)
    }
}

private struct OnDeviceDocsTool: Tool {
    let kit: OnDeviceToolKit
    let name = ClientTool.typstDocs.rawValue
    let description = ClientTool.typstDocs.summary
    @Generable struct Arguments {
        @Guide(description: "What to look up, for example table cell merge")
        var query: String
    }
    func call(arguments: Arguments) async throws -> String { await kit.invoke(.typstDocs, ["query": arguments.query]) }
}

private struct OnDeviceDiagnosticsTool: Tool {
    let kit: OnDeviceToolKit
    let name = ClientTool.getDiagnostics.rawValue
    let description = ClientTool.getDiagnostics.summary
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String { await kit.invoke(.getDiagnostics) }
}

private struct OnDeviceOutlineTool: Tool {
    let kit: OnDeviceToolKit
    let name = ClientTool.getOutline.rawValue
    let description = ClientTool.getOutline.summary
    @Generable struct Arguments {
        @Guide(description: "Path of a .typ file relative to the project folder")
        var path: String
    }
    func call(arguments: Arguments) async throws -> String { await kit.invoke(.getOutline, ["path": arguments.path]) }
}

/// The thin adapter over FoundationModels.
public enum AppleOnDeviceModel {
    public static var availability: OnDeviceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable: .modelNotReady
        }
    }

    /// The model's context window in tokens; it reads 0 while the model is unavailable, then the pre-27 value stands in.
    public static var contextTokens: Int {
        let n = SystemLanguageModel.default.contextSize
        return n > 0 ? n : OnDeviceContext.fallbackContextTokens
    }

    public static let generate: OnDeviceGenerate = { instructions, prompt in
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    let session = LanguageModelSession(model: .default, instructions: instructions)
                    for try await snapshot in session.streamResponse(to: prompt) { c.yield(snapshot.content) }
                    c.finish()
                } catch {
                    c.finish(throwing: map(error))
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    /// Like `generate`, with the kit's tools: the framework runs the loop and calls them as the model asks.
    public static let generateWithTools: OnDeviceToolGenerate = { instructions, prompt, kit in
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    let tools: [any Tool] = kit.tools.compactMap { t -> (any Tool)? in
                        switch t {
                        case .typstDocs: OnDeviceDocsTool(kit: kit)
                        case .getDiagnostics: OnDeviceDiagnosticsTool(kit: kit)
                        case .getOutline: OnDeviceOutlineTool(kit: kit)
                        default: nil
                        }
                    }
                    let session = LanguageModelSession(model: .default, tools: tools, instructions: instructions)
                    for try await snapshot in session.streamResponse(to: prompt) { c.yield(snapshot.content) }
                    c.finish()
                } catch {
                    c.finish(throwing: map(error))
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    static func map(_ error: Error) -> Error {
        if let e = error as? LanguageModelError {
            switch e {
            case .contextSizeExceeded: return AssistantError.passageTooLarge
            case .guardrailViolation, .refusal: return AssistantError.declined
            case .unsupportedLanguageOrLocale: return AssistantError.onDevice(String(localized: "The on-device model does not support this language.", bundle: .module))
            case .rateLimited: return AssistantError.rateLimited(retryAfter: nil)
            default: return AssistantError.onDevice(e.localizedDescription)
            }
        }
        // macOS 27 moved the old GenerationError cases to LanguageModelError (above) and this one.
        if let e = error as? SystemLanguageModel.Error, case .assetsUnavailable = e {
            return AssistantError.onDevice(String(localized: "The on-device model is still downloading or not available on this Mac.", bundle: .module))
        }
        return error
    }
}

/// The on-device model behind the common client protocol.
public struct OnDeviceClient: AssistantClient {
    let generate: OnDeviceGenerate
    let generateWithTools: OnDeviceToolGenerate
    public init(generate: @escaping OnDeviceGenerate = AppleOnDeviceModel.generate, generateWithTools: @escaping OnDeviceToolGenerate = AppleOnDeviceModel.generateWithTools) {
        self.generate = generate; self.generateWithTools = generateWithTools
    }

    /// Earlier turns go into the one prompt; the session starts fresh each time.
    static func prompt(_ messages: [AssistantRequest.Message]) -> String {
        guard let last = messages.last else { return "" }
        let earlier = messages.dropLast().map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
        return earlier.isEmpty ? last.text : "Earlier in this conversation:\n" + earlier.joined(separator: "\n\n") + "\n\nNow:\n" + last.text
    }

    public func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> { stream(request, run: nil) }

    /// With `run` and tools in the request the framework calls them itself; each finished call is reported as `toolRan`.
    public func stream(_ request: AssistantRequest, run: ToolRunner?) -> AsyncThrowingStream<AssistantEvent, Error> {
        let generate = generate, generateWithTools = generateWithTools
        let tools = request.clientTools.filter(ClientTool.onDeviceTools.contains)
        return AsyncThrowingStream { c in
            let task = Task {
                var sent = ""
                func pump(_ source: AsyncThrowingStream<String, Error>) async throws {
                    for try await snapshot in source {
                        // Snapshots grow the answer; shortcut: a snapshot that rewrites earlier text only adds its new tail.
                        guard snapshot.count > sent.count else { continue }
                        c.yield(.text(String(snapshot.dropFirst(sent.count))))
                        sent = snapshot
                    }
                }
                let prompt = Self.prompt(request.messages)
                do {
                    if let run, !tools.isEmpty {
                        let kit = OnDeviceToolKit(tools: tools, run: run) { c.yield(.toolRan($0, $1)) }
                        do { try await pump(generateWithTools(request.system, prompt, kit)) } catch AssistantError.passageTooLarge where sent.isEmpty {
                            try await pump(generate(request.system, prompt))    // the tool results did not fit: answer without them
                        }
                    } else {
                        try await pump(generate(request.system, prompt))
                    }
                    c.yield(.done(.endTurn, nil))
                    c.finish()
                } catch AssistantError.declined {
                    c.yield(.done(.refusal, nil))
                    c.finish()
                } catch {
                    c.finish(throwing: error)
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    public func models() async throws -> [String] { [AssistantPreset.onDevice.models[0]] }
}

/// Context for the small on-device window: a passage instead of whole files.
public enum OnDeviceContext {
    /// `SystemLanguageModel.contextSize`'s own value before macOS 27 (FoundationModels.swiftinterface); the app passes the live one.
    public static let fallbackContextTokens = 4096

    /// Prompt characters for a context window: half the window, leaving the rest to the answer, at a conservative 3 characters a token.
    public static func characterBudget(contextTokens: Int) -> Int { contextTokens * 3 / 2 }

    public static let systemPrompt = """
    You help the user write a Typst document in the Typo editor. Answer briefly, in the user's language, with Markdown.
    Most messages are questions about Typst. Answer a question with an explanation and a short example in a ```typst fence. \
    A question never changes the document: do not repeat the passage and do not write an edit block for it.
    The passage from the user's document is only context.
    Only when the user asks you to change, rewrite, fix or insert text in the document, write an edit block exactly like this, \
    with the file's path:
    <<<<<<< SEARCH path/to/file.typ
    exact existing text, occurring once in the file
    =======
    replacement text
    >>>>>>> REPLACE
    Copy the SEARCH text exactly from the passage. The user accepts or rejects each block; never say a change was accepted or applied.
    """

    /// The small model echoes the passage back when it also knows the edit format, so a question gets its own prompt
    /// without that format. `classifierPrompt` decides which one a message gets.
    public static let questionPrompt = """
    You help the user with Typst, the markup-based typesetting system, in the Typo editor. The user asks a question. \
    Answer it briefly in prose, in the user's language, with Markdown, and give a short example in a ```typst fence. \
    Never repeat or rewrite the user's document.
    """

    /// What the question prompt adds when tools are on: the small model must be told to use them, and only those it has.
    public static func toolNote(_ tools: [ClientTool]) -> String {
        let names = tools.filter(ClientTool.onDeviceTools.contains).map(\.rawValue)
        return names.isEmpty ? "" : " You can call these tools: \(names.joined(separator: ", ")). Look up Typst syntax with typst_docs instead of guessing. Call at most \(OnDeviceToolKit.maxCalls) tools."
    }

    public static let classifierPrompt = """
    Classify the user's message to a Typst editor assistant. Reply with exactly one word: CHANGE if the user asks to change, \
    fix, rewrite, translate, insert or delete text in their document; QUESTION otherwise (asking how something works, what \
    something means, or for an example).
    """

    public static func classifierRequest(_ text: String) -> AssistantRequest {
        AssistantRequest(model: AssistantPreset.onDevice.models[0], system: classifierPrompt, files: nil, messages: [.init(role: .user, text: text)])
    }

    /// An unclear reply counts as a question: a wrong prose answer costs less than an unwanted edit.
    public static func asksForChange(classifierReply: String) -> Bool {
        let r = classifierReply.uppercased()
        return r.contains("CHANGE") && !r.contains("QUESTION")
    }

    /// The last turn of a question: the question before and after its context, which keeps the model from continuing the context.
    public static func questionTurn(_ text: String, context: String?) -> String {
        guard let context, !context.isEmpty else { return text }
        return "Question: \(text)\n\nFor context only:\n\(context)\n\nAnswer the question: \(text)"
    }

    /// The heading section holding `caret`: from the nearest heading line before it to the next heading of the same or a higher level.
    public static func section(around caret: Int, in text: String) -> NSRange {
        let ns = text as NSString
        var lines: [(range: NSRange, level: Int)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, _, enclosing, _ in
            let line = ns.substring(with: enclosing).drop { $0 == " " || $0 == "\t" }
            let level = line.prefix { $0 == "=" }.count
            lines.append((enclosing, level > 0 && line.dropFirst(level).first == " " ? level : 0))
        }
        guard !lines.isEmpty else { return NSRange(location: 0, length: ns.length) }
        let at = lines.lastIndex { $0.range.location <= caret } ?? 0
        let head = lines[...at].lastIndex { $0.level > 0 }
        let start = head.map { lines[$0].range.location } ?? 0
        let level = head.map { lines[$0].level } ?? 1
        let next = lines[(at + 1)...].first { $0.level > 0 && $0.level <= level }
        return NSRange(location: start, length: (next?.range.location ?? ns.length) - start)
    }

    /// Whole lines of `range` around `caret` that fit `limit` characters, growing below and above the caret's line in turn.
    /// One line longer than `limit` is returned whole.
    public static func excerpt(of range: NSRange, around caret: Int, in text: String, limit: Int) -> NSRange {
        guard range.length > limit else { return range }
        var lines: [NSRange] = []
        (text as NSString).enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, _, r, _ in lines.append(r) }
        guard !lines.isEmpty else { return range }
        var lo = lines.lastIndex { $0.location <= caret } ?? 0, hi = lo, grew = true
        while grew {
            grew = false
            if hi + 1 < lines.count, NSMaxRange(lines[hi + 1]) - lines[lo].location <= limit { hi += 1; grew = true }
            if lo > 0, NSMaxRange(lines[hi]) - lines[lo - 1].location <= limit { lo -= 1; grew = true }
        }
        return NSRange(location: lines[lo].location, length: NSMaxRange(lines[hi]) - lines[lo].location)
    }

    /// The text the model works on.
    public struct Passage: Equatable, Sendable {
        /// "Selected text (a.typ, lines 2–3)" or "Section around the cursor (a.typ, lines 10–40)".
        public var label: String
        public var text: String
        /// A selection is refused when too long; a section was already cut to fit.
        public var isSelection: Bool
        public init(label: String, text: String, isSelection: Bool) { self.label = label; self.text = text; self.isSelection = isSelection }
    }

    /// The passage for a request: the selection, else the caret's section cut to `limit` around the caret.
    public static func passage(path: String, text: String, selection: NSRange, limit: Int) -> Passage {
        let ns = text as NSString
        if selection.length > 0 {
            return Passage(label: "Selected text (\(path), \(lines(selection, ns)))", text: ns.substring(with: selection), isSelection: true)
        }
        let section = section(around: selection.location, in: text)
        let r = excerpt(of: section, around: selection.location, in: text, limit: limit)
        let kind = r == section ? "Section around the cursor" : "Part of the section around the cursor"
        return Passage(label: "\(kind) (\(path), \(lines(r, ns)))", text: ns.substring(with: r), isSelection: false)
    }

    public static func lines(_ r: NSRange, _ ns: NSString) -> String {
        let a = AssistantContext.line(of: r.location, in: ns), b = AssistantContext.line(of: max(r.location, NSMaxRange(r) - 1), in: ns)
        return a == b ? "line \(a)" : "lines \(a)–\(b)"
    }

    /// One request within `budget` characters. The question, passage and errors must fit or it throws; the reference and
    /// then the newest earlier turns fill what is left, and leaving turns out is said in the prompt.
    public static func request(question: String, history: [AssistantRequest.Message], passage: Passage?, diagnostics: String?,
                               reference: String?, budget: Int, system: String = systemPrompt) throws(AssistantError) -> AssistantRequest {
        let systemPrompt = system
        let passageBlock = passage.map { "\($0.label):\n```\n\($0.text)\n```" }
        var current = [passageBlock, diagnostics].compactMap { $0 }
        var used = systemPrompt.count + question.count + current.reduce(0) { $0 + $1.count + 2 }
        guard used <= budget else { throw .passageTooLarge }
        if let reference, used + reference.count + 2 <= budget {
            current.append(reference)
            used += reference.count + 2
        }
        var kept: [AssistantRequest.Message] = []
        for m in history.reversed() {
            guard used + m.text.count + 16 <= budget else { break }
            used += m.text.count + 16
            kept.insert(m, at: 0)
        }
        while kept.first?.role == .assistant { kept.removeFirst() }
        if kept.count < history.count { current.insert("(Earlier messages of this conversation are left out.)", at: 0) }
        let last = AssistantRequest.Message(role: .user, text: (current + [question]).joined(separator: "\n\n"))
        return AssistantRequest(model: AssistantPreset.onDevice.models[0], system: systemPrompt, files: nil, messages: kept + [last])
    }
}
