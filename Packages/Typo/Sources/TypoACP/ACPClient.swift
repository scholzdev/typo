import Foundation
import Synchronization
import JSONRPC
import ACPProtocol
import TypoAssistant
import TypoKit
import TypstEngine

extension ACPToolCall {
    /// The files the call names in its diffs and locations.
    public var paths: [String] {
        var seen = Set<String>()
        return (diffs.map(\.path) + locations).filter { seen.insert($0).inserted }
    }

    /// Changes the call makes; `search` is the old text, empty for a new file.
    public var diffs: [ProposedEdit] {
        content.compactMap { c in
            guard c["type"]?.string == "diff", let path = c["path"]?.string, let new = c["newText"]?.string else { return nil }
            return ProposedEdit(path: path, search: c["oldText"]?.string ?? "", replace: new)
        }
    }

    var isEdit: Bool { changesFiles || !diffs.isEmpty }

    /// The shell line an `execute` call runs: `rawInput.command` as a string, or as an argument list (quoted, so the
    /// policy reads the same words), else the title without the backticks Claude Code wraps it in.
    public var commandLine: String? {
        guard kind == "execute" else { return nil }
        if let s = rawInput?["command"]?.string { return s }
        if let a = rawInput?["command"]?.array {
            let words = a.compactMap(\.string)
            return words.count == a.count && !words.isEmpty ? AgentAccess.quote(words) : nil
        }
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.count > 1, t.hasPrefix("`"), t.hasSuffix("`") { return String(t.dropFirst().dropLast()) }
        return t.isEmpty ? nil : t
    }

    /// The call as the permission policy sees it.
    public var accessRequest: AgentAccess.Request {
        AgentAccess.Request(kind: kind, title: title, command: commandLine, paths: paths)
    }

    /// The finished call for the transcript; the name is the kind (an identifier), the row shows the title.
    var event: AssistantEvent {
        let arguments: JSONValue = ["title": .string(title), "input": rawInput ?? [:]]
        let text = content.compactMap { c -> String? in
            switch c["type"]?.string {
            case "content": c["content"]?["text"]?.string
            case "diff": c["path"]?.string.map { "Changed \($0)" }
            case "terminal": "Ran a command."
            default: nil
            }
        }.joined(separator: "\n")
        let failed = status == "failed"
        return .toolRan(ToolCall(id: id, name: kind ?? "tool", arguments: String(decoding: arguments.json, as: UTF8.self)),
                        ToolResult(callID: id, content: text.isEmpty ? (failed ? "Failed." : "Done.") : text, isError: failed))
    }
}

/// One prompt turn's `session/update`s as assistant events. A tool call is shown once it completed or failed, or
/// when the turn ends; never as `.toolCall`, which the agent loop would run itself.
struct ACPTurn {
    var calls: [String: ACPToolCall] = [:]
    var order: [String] = []
    var shown: Set<String> = []
    /// Edit calls between the update that named their files and their end, which the host watches.
    var editing: Set<String> = []

    enum EditStep: Sendable, Equatable { case started(ACPToolCall), ended(ACPToolCall, completed: Bool) }

    mutating func call(_ id: String, _ u: JSONValue) -> ACPToolCall {
        if calls[id] == nil { order.append(id); calls[id] = ACPToolCall(id: id) }
        calls[id]!.merge(u)
        return calls[id]!
    }

    mutating func apply(_ u: JSONValue) -> [AssistantEvent] {
        switch u["sessionUpdate"]?.string {
        case "agent_message_chunk": return u["content"]?["text"]?.string.map { [.text($0)] } ?? []
        case "agent_thought_chunk": return u["content"]?["text"]?.string.map { [.reasoning($0)] } ?? []
        case "tool_call", "tool_call_update":
            guard let id = u["toolCallId"]?.string else { return [] }
            let c = call(id, u)
            guard c.status == "completed" || c.status == "failed", shown.insert(id).inserted else { return [] }
            return [c.event]
        default: return []
        }
    }

    mutating func finish() -> [AssistantEvent] {
        defer { shown.formUnion(order) }
        return order.filter { !shown.contains($0) }.compactMap { calls[$0]?.event }
    }

    /// What the host learns after an update of call `id`: an edit call starts once it names files, and ends with its status.
    mutating func editStep(_ id: String) -> EditStep? {
        guard let c = calls[id] else { return nil }
        if c.status == "completed" || c.status == "failed" { return editing.remove(id) != nil ? .ended(c, completed: c.status == "completed") : nil }
        return c.isEdit && !c.paths.isEmpty && editing.insert(id).inserted ? .started(c) : nil
    }

    /// The calls still editing when the turn ends; they count as completed, so what they wrote is taken in.
    mutating func endEdits() -> [EditStep] {
        defer { editing = [] }
        return order.filter(editing.contains).compactMap { calls[$0].map { .ended($0, completed: true) } }
    }
}

/// A weak reference the agent's threads can carry.
final class ACPHostRef: @unchecked Sendable {
    weak var value: (any ACPHost)?
    init(_ value: (any ACPHost)?) { self.value = value }
}

/// One running agent with one session: its process, the connection, and the turn in progress.
public final class ACPAgent: Sendable {
    private struct State {
        var sessionID = ""
        var turn = ACPTurn()
        /// Set while a turn streams; updates and permission requests outside a turn are dropped or cancelled.
        var emit: (@Sendable ([AssistantEvent]) -> Void)?
        var permissions: [UUID: CheckedContinuation<String?, Never>] = [:]
        var inFlight: Task<Void, Never>?
        var turnNumber = 0
        /// The modes and models the session offers.
        var options = ACPSessionOptions()
        /// The host's edit steps run one after another, so a call's end never overtakes its start.
        var hostWork: Task<Void, Never>?

        mutating func send(_ steps: [ACPTurn.EditStep], to host: ACPHostRef) {
            for step in steps {
                let previous = hostWork
                hostWork = Task { @MainActor in
                    await previous?.value
                    switch step {
                    case .started(let c): await host.value?.editStarted(c)
                    case .ended(let c, let completed): await host.value?.editEnded(c, completed: completed)
                    }
                }
            }
        }
    }

    let connection: ACPConnection
    let process: ACPProcess?
    private let host: ACPHostRef
    private let state = Mutex(State())

    init(connection: ACPConnection, process: ACPProcess?, host: (any ACPHost)?) {
        self.connection = connection
        self.process = process
        self.host = ACPHostRef(host)
        connection.start(handler: { [weak self] method, params in
            await self?.handle(method, params) ?? .failure(ACPError(ACPError.internalError, "The window closed."))
        }, onNotification: { [weak self] method, params in self?.notified(method, params) })
    }

    public var isAlive: Bool { !connection.isClosed }

    /// Starts the agent of `command` in `cwd` and opens a session; returns it with the agent's name and version.
    /// `mcp`: the path of the bundled typo-mcp, which the session gets as an MCP server for `cwd`.
    /// `meta`: the `_meta` of `session/new`, such as `claudeCodeMeta(plugins:)`.
    public static func launch(command: String, cwd: URL, host: (any ACPHost)?, mcp: String? = nil, meta: JSONValue? = nil) async throws -> (agent: ACPAgent, info: String) {
        let words = ACPProcess.words(command)
        guard let name = words.first else { throw ACPError(ACPError.closed, "The agent has no command. Enter it in Settings › Intelligence.") }
        let env = ACPProcess.environment()
        guard let executable = ACPProcess.locate(name, path: env["PATH"] ?? "") else {
            throw ACPError(ACPError.closed, "“\(name)” was not found. " + (name == "npx" ? "Install Node.js, which brings npx." : "Install it, or enter its full path in Settings › Intelligence."))
        }
        let process = try ACPProcess(executable: executable, arguments: Array(words.dropFirst()), environment: env, cwd: cwd)
        let connection = ACPConnection(input: process.stdout, output: process.stdin) { [process] in
            let tail = process.lastError
            return tail.isEmpty ? "The agent stopped." : "The agent stopped:\n\(tail)"
        }
        let agent = ACPAgent(connection: connection, process: process, host: host)
        do {
            return (agent, try await agent.connect(cwd: cwd, mcp: mcp, meta: meta))
        } catch {
            agent.close()
            throw error
        }
    }

    /// `initialize` and `session/new`; returns the agent's name and version.
    func connect(cwd: URL, mcp: String? = nil, meta: JSONValue? = nil) async throws -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let info = try await connection.request("initialize", [
            "protocolVersion": .int(ACPProtocolInfo.protocolVersion),
            "clientCapabilities": ["fs": ["readTextFile": true, "writeTextFile": true], "terminal": false],
            "clientInfo": ["name": "typo", "title": "Typo", "version": .string(version)],
        ])
        if let v = info["protocolVersion"]?.int, v != ACPProtocolInfo.protocolVersion {
            throw ACPError(ACPError.internalError, "The agent speaks protocol version \(v); Typo speaks version \(ACPProtocolInfo.protocolVersion).")
        }
        var params: JSONValue = ["cwd": .string(cwd.path), "mcpServers": .array(mcp.map { [["name": "typo", "command": .string($0), "args": ["--project", .string(cwd.path)], "env": []]] } ?? [])]
        if let meta, case .object(var o) = params { o["_meta"] = meta; params = .object(o) }
        let session = try await connection.request("session/new", params)
        guard let id = session["sessionId"]?.string else { throw ACPError(ACPError.internalError, "The agent opened no session.") }
        let options = ACPSessionOptions.parse(session)
        state.withLock { $0.sessionID = id; $0.options = options }
        Task { @MainActor [host] in host.value?.optionsChanged(options) }
        let a = info["agentInfo"]
        return [a?["title"]?.string ?? a?["name"]?.string ?? "The agent", a?["version"]?.string].compactMap { $0 }.joined(separator: " ")
    }

    /// The `session/new` `_meta` with which the Claude Code ACP adapter loads the plugin folders `plugins`
    /// (its `claudeCode.options` go into the Claude Agent SDK's options); nil without plugins.
    public static func claudeCodeMeta(plugins: [URL]) -> JSONValue? {
        plugins.isEmpty ? nil : ["claudeCode": ["options": ["plugins": .array(plugins.map { ["type": "local", "path": .string($0.path)] })]]]
    }

    /// The agent's mode for the "Change files" permission: it asks before edits, accepts them, or only plans.
    public static func mode(for policy: PermissionPolicy) -> String {
        switch policy {
        case .ask: "default"
        case .allow: "acceptEdits"
        case .never: "plan"
        }
    }

    /// Puts the session in the mode of `policy`, when the agent offers that mode.
    public func apply(_ policy: PermissionPolicy) async {
        await select(mode: Self.mode(for: policy))
    }

    /// Puts the session in mode `id`, when the agent offers it.
    public func select(mode id: String) async {
        await select(id, in: \.modes, always: true)
    }

    /// Switches the session to model `id` when the agent offers it and it isn't the current one.
    public func select(model id: String) async {
        await select(id, in: \.models, always: false)
    }

    /// `always`: sent even when the option is current already (the agent may change its mode by itself).
    private func select(_ id: String, in key: WritableKeyPath<ACPSessionOptions, ACPSelector?>, always: Bool) async {
        let r: (method: String, params: JSONValue)? = state.withLock { s in
            guard let sel = s.options[keyPath: key], sel.choices.contains(where: { $0.id == id }), always || sel.current != id else { return nil }
            return sel.request(id, session: s.sessionID)
        }
        guard let r, (try? await connection.request(r.method, r.params)) != nil else { return }
        let options = state.withLock { s in s.options[keyPath: key]?.current = id; return s.options }
        await MainActor.run { [host] in host.value?.optionsChanged(options) }
    }

    /// Ends the process in the background.
    public func close() {
        guard let process else { return }
        Thread { process.shutdown() }.start()
    }

    /// Sends one prompt and streams the turn into `emit`; cancelling sends `session/cancel` and still waits for the
    /// agent's answer, so the next turn never overlaps this one.
    func prompt(_ blocks: [JSONValue], emit: @escaping @Sendable ([AssistantEvent]) -> Void) async throws -> AssistantStopReason {
        if let previous = state.withLock({ $0.inFlight }) {
            // A stopped turn the agent never closes must not block the next one for good.
            await withTaskGroup(of: Void.self) { g in
                g.addTask { await previous.value }
                g.addTask { try? await Task.sleep(for: .seconds(10)) }
                await g.next()
                g.cancelAll()
            }
        }
        let (session, number) = state.withLock { [host] s in
            s.send(s.turn.endEdits(), to: host)    // a turn that never ended
            s.turn = ACPTurn()
            s.turnNumber += 1
            s.emit = emit
            return (s.sessionID, s.turnNumber)
        }
        let request = Task { [connection] in try await connection.request("session/prompt", ["sessionId": .string(session), "prompt": .array(blocks)]) }
        state.withLock { $0.inFlight = Task { _ = try? await request.value } }
        let result: JSONValue
        do {
            result = try await withTaskCancellationHandler { try await request.value } onCancel: { cancel() }
        } catch {
            await settle(number)
            throw error
        }
        emit(state.withLock { $0.turn.finish() })
        await settle(number)
        return switch result["stopReason"]?.string {
        case "end_turn": .endTurn
        case "max_tokens", "max_turn_requests": .maxTokens
        case "refusal": .refusal
        case let r: .other(r ?? "unknown")
        }
    }

    /// Ends the turn's updates and waits until the host took in what its edit calls wrote.
    private func settle(_ number: Int) async {
        let work = state.withLock { [host] s -> Task<Void, Never>? in
            guard s.turnNumber == number else { return nil }    // the next turn started and ended these already
            s.emit = nil
            s.send(s.turn.endEdits(), to: host)
            return s.hostWork
        }
        await work?.value
    }

    func cancel() {
        let (session, waiting) = state.withLock { s in
            defer { s.permissions = [:]; s.emit = nil }
            return (s.sessionID, Array(s.permissions.values))
        }
        connection.notify("session/cancel", ["sessionId": .string(session)])
        waiting.forEach { $0.resume(returning: nil) }
    }

    private func notified(_ method: String, _ params: JSONValue) {
        guard method == "session/update", let u = params["update"] else { return }
        // Arrives right after session/new, outside any turn, so it can't go through the turn below.
        if u["sessionUpdate"]?.string == "available_commands_update" {
            let commands = ACPCommand.list(u["availableCommands"])
            Task { @MainActor [host] in host.value?.commandsChanged(commands) }
            return
        }
        if let plan = ACPPlan.parse(u) {
            // Like the other updates, a plan outside a turn has no answer to join.
            if state.withLock({ $0.emit != nil }) { Task { @MainActor [host] in host.value?.planChanged(plan) } }
            return
        }
        if let options = state.withLock({ s in s.options.apply(update: u) ? s.options : nil }) {
            Task { @MainActor [host] in host.value?.optionsChanged(options) }
            return
        }
        let (events, emit, call) = state.withLock { [host] s -> ([AssistantEvent], (@Sendable ([AssistantEvent]) -> Void)?, ACPToolCall?) in
            guard s.emit != nil else { return ([], nil, nil) }
            let events = s.turn.apply(u)
            let id = u["toolCallId"]?.string
            if let id, let step = s.turn.editStep(id) { s.send([step], to: host) }
            return (events, s.emit, id.flatMap { s.turn.calls[$0] })
        }
        if let call { Task { @MainActor [host] in host.value?.toolCallChanged(call) } }
        if !events.isEmpty { emit?(events) }
    }

    private func handle(_ method: String, _ params: JSONValue) async -> Result<JSONValue, ACPError> {
        let invalid = ACPError(ACPError.invalidParams, "Missing parameters for \(method).")
        switch method {
        case "session/request_permission":
            let options = (params["options"]?.array ?? []).compactMap { o in
                o["optionId"]?.string.map { ACPOption(id: $0, name: o["name"]?.string ?? $0, kind: o["kind"]?.string ?? "") }
            }
            let key = UUID(), host = host
            let choice: String? = await withCheckedContinuation { k in
                let call: ACPToolCall? = state.withLock { s in
                    guard s.emit != nil, let tc = params["toolCall"], let id = tc["toolCallId"]?.string else { return nil }
                    s.permissions[key] = k
                    let c = s.turn.call(id, tc)
                    // The request may be the first to name the files, and the tool waits for its answer.
                    if let step = s.turn.editStep(id) { s.send([step], to: host) }
                    return c
                }
                guard let call else { return k.resume(returning: nil) }
                Task { @MainActor in
                    let answer = await host.value?.permission(for: call, options: options)
                    if let k = self.state.withLock({ $0.permissions.removeValue(forKey: key) }) { k.resume(returning: answer) }
                }
            }
            return .success(["outcome": choice.map { ["outcome": "selected", "optionId": .string($0)] } ?? ["outcome": "cancelled"]])
        case "fs/read_text_file":
            guard let path = params["path"]?.string else { return .failure(invalid) }
            do {
                guard let text = try await host.value?.readTextFile(path) else { throw ACPError(ACPError.internalError, "The window closed.") }
                return .success(["content": .string(Self.slice(text, line: params["line"]?.int, limit: params["limit"]?.int))])
            } catch { return .failure(Self.wire(error)) }
        case "fs/write_text_file":
            guard let path = params["path"]?.string, let content = params["content"]?.string else { return .failure(invalid) }
            do {
                guard let host = host.value else { throw ACPError(ACPError.internalError, "The window closed.") }
                try await host.writeTextFile(path, content: content)
                return .success(.null)
            } catch { return .failure(Self.wire(error)) }
        default:
            return .failure(ACPError(ACPError.methodNotFound, "Typo does not offer \(method)."))
        }
    }

    private static func wire(_ e: Error) -> ACPError { e as? ACPError ?? ACPError(ACPError.internalError, e.localizedDescription) }

    /// `limit` lines from the 1-based `line` on.
    static func slice(_ text: String, line: Int?, limit: Int?) -> String {
        guard line != nil || limit != nil else { return text }
        let lines = text.components(separatedBy: "\n").dropFirst(max((line ?? 1) - 1, 0))
        return lines.prefix(limit ?? lines.count).joined(separator: "\n")
    }
}

/// The running agents of one window, one per conversation. Each turn builds a new `ACPClient`; the process and
/// session outlive it here.
public final class ACPSessions: Sendable {
    private struct Entry {
        let command: String
        let agent: Task<ACPAgent, Error>
    }
    private let entries = Mutex<[String: Entry]>([:])
    public init() {}

    /// The conversation's agent, started when there is none, it died, or its command changed. `fresh`: its session
    /// has not seen this conversation yet.
    func agent(for key: String, command: String, start: @escaping @Sendable () async throws -> ACPAgent) async throws -> (agent: ACPAgent, fresh: Bool) {
        let (task, fresh, old) = entries.withLock { e -> (Task<ACPAgent, Error>, Bool, Task<ACPAgent, Error>?) in
            if let x = e[key], x.command == command { return (x.agent, false, nil) }
            let t = Task { try await start() }
            defer { e[key] = Entry(command: command, agent: t) }
            return (t, true, e[key]?.agent)
        }
        if let old { Self.close(old) }
        do {
            let agent = try await task.value
            guard agent.isAlive else {
                // The process ended since the last turn: start over with a new session.
                entries.withLock { if $0[key]?.agent == task { $0[key] = nil } }
                agent.close()
                return try await self.agent(for: key, command: command, start: start)
            }
            return (agent, fresh)
        } catch {
            entries.withLock { if $0[key]?.agent == task { $0[key] = nil } }
            throw error
        }
    }

    /// The conversation's agent if one runs; never starts one.
    public func running(_ key: String) async -> ACPAgent? {
        guard let t = entries.withLock({ $0[key]?.agent }), let a = try? await t.value, a.isAlive else { return nil }
        return a
    }

    /// Stops the conversation's agent: it was deleted or moved to another provider, or it needs a new login.
    public func close(_ key: String) {
        if let e = entries.withLock({ $0.removeValue(forKey: key) }) { Self.close(e.agent) }
    }

    public func closeAll() {
        entries.withLock { e in defer { e = [:] }; return Array(e.values) }.forEach { Self.close($0.agent) }
    }

    private static func close(_ t: Task<ACPAgent, Error>) {
        Task { try? await t.value.close() }
    }
}

/// An agent behind the common client protocol. The agent keeps the conversation itself: each turn sends only the
/// newest message, and the agent reads and writes the project through `ACPHost`.
public struct ACPClient: AssistantClient {
    let provider: AssistantProvider
    let sessions: ACPSessions?
    let attachments: [URL]
    /// The "Change files" permission, applied as the agent's mode at each turn.
    let changeFiles: PermissionPolicy?
    /// The mode picked for the conversation, which wins over `changeFiles`.
    let mode: String?
    let start: @Sendable () async throws -> ACPAgent

    public init(provider: AssistantProvider, sessions: ACPSessions?, attachments: [URL], changeFiles: PermissionPolicy? = nil, mode: String? = nil,
                start: @escaping @Sendable () async throws -> ACPAgent) {
        self.provider = provider; self.sessions = sessions; self.attachments = attachments; self.changeFiles = changeFiles; self.mode = mode; self.start = start
    }

    /// The newest user message with its context block, after a recap of earlier turns when the session is new
    /// (the app restarted or the agent died), and the attached files as links the agent can read.
    static func prompt(_ r: AssistantRequest, fresh: Bool, attachments: [URL]) -> [JSONValue] {
        let last = r.messages.last?.text ?? ""
        let earlier = fresh ? r.messages.dropLast().suffix(10).map { m in
            "\(m.role == .user ? "User" : "Assistant"): " + (m.text.count > 1500 ? m.text.prefix(1500) + "…" : m.text)
        } : []
        // A slash command only works at the very start of the prompt, so it goes without the recap.
        let text = earlier.isEmpty || last.hasPrefix("/") ? last : "Earlier in this conversation:\n\n" + earlier.joined(separator: "\n\n") + "\n\nNow:\n" + last
        return [["type": "text", "text": .string(text)]]
            + attachments.map { ["type": "resource_link", "uri": .string($0.absoluteString), "name": .string($0.lastPathComponent)] }
    }

    /// The panel's message for an agent's error.
    public static func failure(_ e: Error, preset: AssistantPreset) -> Error {
        guard let e = e as? ACPError else { return e }
        switch e.code {
        case ACPError.authRequired: return AssistantError.agent(preset.loginHint ?? "The agent asks you to log in first. Log in with its own command line tool, then try again.")
        case ACPError.closed: return AssistantError.agent(e.message)
        default: return AssistantError.agent("The agent reported an error: \(e.message)")
        }
    }

    public func stream(_ request: AssistantRequest) -> AsyncThrowingStream<AssistantEvent, Error> {
        let sessions = sessions, start = start, attachments = attachments, changeFiles = changeFiles, mode = mode, preset = provider.preset, command = provider.command ?? ""
        return AsyncThrowingStream { c in
            let task = Task {
                do {
                    guard let sessions else { throw AssistantError.agent("Agents answer in the assistant panel only.") }
                    let (agent, fresh) = try await sessions.agent(for: request.session ?? "", command: command, start: start)
                    try Task.checkCancellation()    // stopped while the agent was starting
                    // Every turn, not once: the agent may change its mode by itself.
                    if let mode { await agent.select(mode: mode) } else if let changeFiles { await agent.apply(changeFiles) }
                    // The request's model is the conversation's pick; empty keeps the agent's default.
                    if !request.model.isEmpty { await agent.select(model: request.model) }
                    let reason = try await agent.prompt(Self.prompt(request, fresh: fresh, attachments: attachments)) { events in
                        for e in events { c.yield(e) }
                    }
                    c.yield(.done(reason, nil))
                    c.finish()
                } catch {
                    // A process that failed to log in keeps failing after the user logged in again: start anew next time.
                    if (error as? ACPError)?.code == ACPError.authRequired { sessions?.close(request.session ?? "") }
                    c.finish(throwing: Self.failure(error, preset: preset))
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    public func models() async throws -> [String] { [] }
}

/// How the agent's file access maps onto the project.
public enum ACPFiles {
    /// The project path of an agent's absolute path, or nil outside `root`, with `..` and symlinks resolved on both sides.
    public static func projectPath(_ path: String, root: URL) -> RelPath? {
        let base = AgentAccess.resolve(root.path), full = AgentAccess.resolve(path)
        guard full.hasPrefix(base + "/") else { return nil }
        return RelPath(String(full.dropFirst(base.count + 1)))
    }

    /// The smallest replacement that turns `old` into `new`: the common start and end stay, so undo, the AI marks and
    /// Revert cover only what the agent changed. Nil when nothing changed.
    public static func replacement(old: String, new: String) -> Replacement? {
        let o = old as NSString, n = new as NSString
        let limit = min(o.length, n.length)
        var start = 0, end = 0
        while start < limit, o.character(at: start) == n.character(at: start) { start += 1 }
        while end < limit - start, o.character(at: o.length - 1 - end) == n.character(at: n.length - 1 - end) { end += 1 }
        guard start + end < max(o.length, n.length) else { return nil }
        // A change across lines covers whole lines, so its gutter bar starts and ends with the lines it changed rather than
        // at a shared "#" of the next line.
        let middle = { (s: NSString, from: Int, to: Int) in s.substring(with: NSRange(location: from, length: max(to - from, 0))).contains("\n") }
        if middle(o, start, o.length - end) || middle(n, start, n.length - end) {
            while start > 0, o.character(at: start - 1) != 10 { start -= 1 }
            end = 0
            while end < limit - start, o.character(at: o.length - 1 - end) == n.character(at: n.length - 1 - end) { end += 1 }
            while end > 0, o.length - end > 0, o.character(at: o.length - end - 1) != 10 { end -= 1 }
        }
        // Never split a surrogate pair.
        if start > 0, UTF16.isLeadSurrogate(o.character(at: start - 1)) { start -= 1 }
        if end > 0, UTF16.isTrailSurrogate(o.character(at: o.length - end)) { end -= 1 }
        return Replacement(range: NSRange(location: start, length: o.length - start - end),
                           text: n.substring(with: NSRange(location: start, length: n.length - start - end)))
    }

    /// The change as the transcript shows it: the whole lines around it, before and after.
    public static func edit(path: String, old: String, _ r: Replacement) -> ProposedEdit {
        let o = old as NSString
        let lines = o.lineRange(for: r.range)
        let head = o.substring(with: NSRange(location: lines.location, length: r.range.location - lines.location))
        let tail = o.substring(with: NSRange(location: NSMaxRange(r.range), length: NSMaxRange(lines) - NSMaxRange(r.range)))
        func trimmed(_ s: String) -> String { s.hasSuffix("\n") ? String(s.dropLast()) : s }
        return ProposedEdit(path: path, search: trimmed(o.substring(with: lines)), replace: trimmed(head + r.text + tail))
    }

    /// `edit` in the answer's edit block format, so the transcript, the changes bar and Revert treat it like the assistant's own.
    public static func block(_ edit: ProposedEdit) -> String {
        ([AssistantEdits.start + edit.path] + (edit.search.isEmpty ? [] : [edit.search]) + [AssistantEdits.divider, edit.replace, AssistantEdits.end])
            .joined(separator: "\n")
    }
}
