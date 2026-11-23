import AppKit
import SwiftUI
import TypoKit
import ACPProtocol
import TypoACP
import TypoAssistant
import TypstEngine

extension FocusedValues {
    @Entry var assistant: AssistantModel?
}

/// One window's assistant: the mode switch, its conversations, the prompt, and the answer being streamed.
@MainActor @Observable final class AssistantModel {
    enum Mode { case navigator, assistant }

    /// A send held until the user accepts that files go to `provider`.
    struct PendingConsent {
        let provider: AssistantProvider
        let files: [String]
        let resume: @MainActor () -> Void
    }

    /// A send held until the user says whether the model may search the web for it.
    struct PendingSearch {
        let provider: AssistantProvider
        let resume: @MainActor (_ search: Bool, _ always: Bool) -> Void
    }

    var mode = Mode.navigator
    let project: Project
    private let store: AssistantConversationStore
    private let providers = AssistantProviderStore.shared
    private(set) var conversations: [AssistantConversation]
    var currentID: UUID?
    var draft = ""
    /// The agent's slash commands, offered when the prompt starts with "/".
    var agentCommands: [ACPCommand] = []
    /// Files sent with the next message; by default the file shown in the editor.
    var attachments: [RelPath] = []
    /// Files from outside the project sent with the next message.
    var externalAttachments: [URL] = []
    /// The first editor's selection when the window switched to the assistant (the editor is not on screen then).
    private(set) var selection: (path: RelPath, range: NSRange)?
    /// Provider and model for a new conversation; a conversation keeps its own.
    var draftProviderID: UUID?
    var draftModel = ""
    /// A message that is not part of the transcript, such as files too large to send.
    var notice: String?
    var pendingConsent: PendingConsent?
    var pendingSearch: PendingSearch?

    /// A tool call held until the user answers whether the assistant may run it.
    struct PendingTool {
        let call: ToolCall
        let question: String
    }
    enum ToolAnswer { case once, always, deny }
    var pendingTool: PendingTool?
    private var toolAnswer: CheckedContinuation<ToolAnswer, Never>?

    /// An agent's tool call held until the user picks one of the agent's options.
    struct PendingPermission {
        let call: ACPToolCall
        let options: [ACPOption]
    }
    /// Agents may ask for several tool calls at once; the cards are answered one after another.
    private var permissionQueue: [(pending: PendingPermission, answer: CheckedContinuation<String?, Never>)] = []
    var pendingPermission: PendingPermission? { permissionQueue.first?.pending }
    /// The agents running for this window's conversations.
    private let agents = ACPSessions()
    /// The files each running edit tool of an agent names, by tool call, with the answer its changes join.
    private var agentEdits: [String: (snapshots: [AgentSnapshot], conversation: UUID, message: UUID)] = [:]
    /// Overrides chosen before the first message; they move into the conversation when it starts.
    private var draftPermissions: AssistantPermissions?
    /// The assistant message being streamed.
    private(set) var streamingID: UUID?
    /// The conversation of the running turn; one turn runs per window, and it keeps running while another conversation is shown.
    private(set) var streamingConversation: UUID?
    /// When the running turn started, for its duration.
    private var turnStart: Date?
    /// The running turn's tool calls as the agent reports them, for the live rows.
    private(set) var liveTools: [ACPToolCall] = []
    /// Conversations whose last turn the user stopped; not saved.
    private var stopped: Set<UUID> = []
    /// The modes and models each agent provider offered last, so the menus show them before a conversation's session starts.
    private(set) var agentOptions: [UUID: ACPSessionOptions] = [:]
    /// The mode picked before the first message.
    var draftAgentMode: String?
    /// Groups, order, unread and disclosure state of the sidebar list.
    var layout: AssistantConversationLayout { didSet { if layout != oldValue { layoutStore.save(layout) } } }
    private let layoutStore: AssistantConversationLayoutStore
    /// True while the context of a message is being gathered, before it is sent.
    private(set) var preparing = false
    private var task: Task<Void, Never>?
    /// Where each applied change of this session went, by message and edit index, for Revert. Changes of an earlier
    /// session are not tracked: the files were reloaded since.
    private var ledger: [String: AppliedChange] = [:]
    /// Bumped when a tracked change moves or is edited by hand, so the views refresh what Revert may do.
    private(set) var changesRevision = 0

    private struct AppliedChange {
        let path: RelPath
        let changeID: UUID?
        let created: Bool
    }

    init(project: Project) {
        self.project = project
        store = AssistantConversationStore(folder: AssistantConversationStore.folder(for: project.rootURL))
        let loaded = store.loadAll()
        conversations = loaded
        layoutStore = AssistantConversationLayoutStore(project.id)
        var l = layoutStore.load()
        l.reconcile(loaded.map(\.id))
        layout = l
        NotificationCenter.default.addObserver(forName: .bufferAIChangesChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changesRevision += 1 }
        }
        NotificationCenter.default.addObserver(forName: .assistantDiscardChange, object: nil, queue: .main) { [weak self] n in
            guard let b = n.object as? Buffer, let r = (n.userInfo?["range"] as? NSValue)?.rangeValue else { return }
            MainActor.assumeIsolated { guard let self, self.project.buffer(for: b.path) === b else { return }; Task { await self.discard(r, in: b) } }
        }
    }

    deinit { agents.closeAll() }

    /// Stops this window's agents; the window closes.
    func closeAgents() { agents.closeAll() }

    var current: AssistantConversation? { conversations.first { $0.id == currentID } }
    /// Whether the shown conversation's turn runs (or a message is being prepared).
    var isStreaming: Bool { (streamingID != nil && streamingConversation == currentID) || preparing }
    /// Whether any turn of the window runs; a second one waits.
    var isBusy: Bool { streamingID != nil || preparing }

    /// The permission card of the shown conversation, if its turn waits for one.
    var shownPermission: PendingPermission? { streamingConversation == currentID ? pendingPermission : nil }
    var shownTool: PendingTool? { streamingConversation == currentID ? pendingTool : nil }

    func status(of id: UUID) -> AssistantConversationStatus {
        let last = conversations.first { $0.id == id }?.messages.last
        let running = streamingConversation == id && streamingID != nil
        return .of(running: running, blocked: running && (pendingPermission != nil || pendingTool != nil),
                   answering: running && last?.id == streamingID && last?.text.isEmpty == false,
                   failed: last?.role == .assistant && last?.error != nil, stopped: stopped.contains(id))
    }

    /// The options of the shown conversation's agent, or of the agent a new conversation would use.
    var shownAgentOptions: ACPSessionOptions? { provider.flatMap { $0.isAgent ? agentOptions[$0.id] : nil } }
    var agentMode: String? { current.map { $0.agentMode } ?? draftAgentMode }

    var provider: AssistantProvider? {
        if let c = current { return providers.provider(c.providerID) }
        return providers.provider(draftProviderID) ?? providers.defaultProvider
    }

    var model: String {
        if let c = current { return c.model }
        if let p = provider { return draftProviderID == p.id && !draftModel.isEmpty ? draftModel : providers.defaultModel(for: p) }
        return ""
    }

    // MARK: Mode

    /// Switches modes; entering the assistant keeps the editor's selection, since the editor leaves the screen.
    func toggle(editor: EditorActions) {
        if mode == .navigator {
            if let c = editor.editor, let tv = c.textView, let b = c.buffer { selection = (b.path, tv.selectedRange()) } else { selection = nil }
            if attachments.isEmpty, let f = project.selectedFile, FileKind.isText(f.raw) { attachments = [f] }
            mode = .assistant
            if let id = currentID { layout.unread.remove(id) }
        } else {
            mode = .navigator
        }
    }

    /// "Explain with AI" from the editor: takes the current selection, shows the assistant and asks; a question, so no edits.
    func explainSelection(editor: EditorActions) {
        guard let c = editor.editor, let tv = c.textView, let b = c.buffer, tv.selectedRange().length > 0 else { return }
        if provider?.isAgent == true {
            // An agent works on the whole project; explaining a passage goes to a model in a new conversation.
            guard let p = providers.defaultModelProvider else {
                mode = .assistant
                notice = "Explain with AI needs a model provider. Add one in Settings › Intelligence."
                return
            }
            newConversation()
            draftProviderID = p.id
            draftModel = providers.defaultModel(for: p)
        }
        selection = (b.path, tv.selectedRange())
        if attachments.isEmpty, FileKind.isText(b.path.raw) { attachments = [b.path] }
        mode = .assistant
        send(.explain)
    }

    // MARK: Permissions

    /// The global defaults with this conversation's overrides.
    var permissions: AssistantPermissions { AssistantPermissions.stored.overriding(with: current?.permissions ?? draftPermissions) }

    private func permissions(of id: UUID) -> AssistantPermissions {
        AssistantPermissions.stored.overriding(with: conversations.first { $0.id == id }?.permissions)
    }

    var canSearch: Bool { provider.map { AssistantPermissions.supportsWebSearch(provider: $0, model: model) } ?? false }
    var canSeeImages: Bool { provider.map { AssistantPermissions.supportsVision(provider: $0, model: model) } ?? false }
    var canUseTools: Bool { provider.map { !$0.isOnDevice && AssistantPermissions.supportsTools(provider: $0, model: model) } ?? false }

    func setPermission(_ p: AssistantPermission, _ policy: PermissionPolicy?) {
        if let id = currentID {
            change(id) { var o = $0.permissions ?? AssistantPermissions(); o.set(p, policy); $0.permissions = o }
            if p == .changeFiles { applyAgentMode(id) }
        } else {
            var o = draftPermissions ?? AssistantPermissions()
            o.set(p, policy)
            draftPermissions = o
        }
    }

    func resetPermissions() {
        if let id = currentID { change(id) { $0.permissions = nil }; applyAgentMode(id) } else { draftPermissions = nil }
    }

    /// A running agent takes a changed "Change files" permission at once, not only at the next turn.
    private func applyAgentMode(_ id: UUID) {
        let policy = permissions(of: id).policy(.changeFiles)
        Task { await agents.running(id.uuidString)?.apply(policy) }
    }

    var hasSelection: Bool { (selection?.range.length ?? 0) > 0 }
    var hasErrors: Bool { project.diagnostics.contains { $0.severity == .error } }

    // MARK: Conversations

    func newConversation() {
        agentCommands = []
        currentID = nil
        draftAgentMode = nil
        draft = ""
        notice = nil
        pendingConsent = nil
        pendingSearch = nil
        draftPermissions = nil
        attachments = project.selectedFile.map { FileKind.isText($0.raw) ? [$0] : [] } ?? []
    }

    func select(_ id: UUID) {
        guard id != currentID else { return }
        currentID = id
        layout.unread.remove(id)
        notice = nil
        pendingConsent = nil
        pendingSearch = nil
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        change(id) { $0.title = t }
    }

    func setArchived(_ id: UUID, _ archived: Bool) {
        change(id) { $0.archived = archived }
        if archived, id == currentID { currentID = nil }
    }

    func delete(_ id: UUID) {
        if id == streamingConversation { stop() }
        if id == currentID { currentID = nil }
        agents.close(id.uuidString)
        conversations.removeAll { $0.id == id }
        layout.remove(id)
        store.delete(id)
    }

    /// Changes the provider and model: of the open conversation, or for the next one.
    func choose(_ p: AssistantProvider, model: String) {
        agentCommands = []
        if let id = currentID {
            if current?.providerID != p.id { agents.close(id.uuidString); change(id) { $0.agentMode = nil } }
            change(id) { $0.providerID = p.id; $0.model = model }
            if p.isAgent, !model.isEmpty { Task { await agents.running(id.uuidString)?.select(model: model) } }
        } else {
            draftProviderID = p.id; draftModel = model
        }
    }

    /// The mode menu: the conversation's agent switches at once when it runs.
    func setAgentMode(_ mode: String?) {
        guard let id = currentID else { draftAgentMode = mode; return }
        change(id) { $0.agentMode = mode }
        if let mode { Task { await agents.running(id.uuidString)?.select(mode: mode) } } else { applyAgentMode(id) }
    }

    private func change(_ id: UUID, save: Bool = true, _ f: (inout AssistantConversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        f(&conversations[i])
        if save { persist(conversations[i]) }
    }

    private func persist(_ c: AssistantConversation) {
        do { try store.save(c) } catch { notice = "The conversation could not be saved: \(error.localizedDescription)" }
    }

    // MARK: Sending

    enum Suggestion { case explain, fixErrors, improve }

    func send(_ suggestion: Suggestion) {
        switch suggestion {
        case .explain: send("Explain the selected text.")
        case .fixErrors: send("Fix the compile errors.", diagnostics: true)
        case .improve: send("Improve the wording of this section.")
        }
    }

    /// Sends `text` (the draft by default) with the attachments; nothing leaves the Mac before the provider's notice was accepted.
    /// `search` is the answer to the search question, once it was asked.
    func send(_ text: String? = nil, diagnostics: Bool = false, search: Bool? = nil) {
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming, let provider, providers.isReady(provider) else { return }
        guard !isBusy else { notice = "Another conversation is still working. Wait for it or stop it first."; return }
        notice = nil
        if providers.needsConsent(provider) {
            pendingConsent = PendingConsent(provider: provider, files: attachments.map(\.raw)) { [weak self] in
                self?.providers.consent(provider)
                self?.pendingConsent = nil
                self?.send(text, diagnostics: diagnostics, search: search)
            }
            return
        }
        let policy = permissions.policy(.webSearch)
        if search == nil, policy == .ask, canSearch {
            pendingSearch = PendingSearch(provider: provider) { [weak self] allowed, always in
                guard let self else { return }
                pendingSearch = nil
                if always { setPermission(.webSearch, .allow) }
                send(text, diagnostics: diagnostics, search: allowed)
            }
            return
        }
        let searching = canSearch && (search ?? (policy == .allow))
        let model = model, conversation = currentID
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let context = try await context(for: question, provider: provider, diagnostics: diagnostics)
                guard currentID == conversation else { return }    // the user moved to another conversation meanwhile
                if text == nil { draft = "" }
                let id = conversation ?? start(provider: provider, model: model, title: question)
                var message = AssistantMessage(role: .user, text: question, context: context)
                message.created = .now
                change(id) { [message] in $0.messages.append(message); $0.updated = .now }
                preparing = false
                respond(in: id, search: searching)
            } catch let e as AssistantError {
                notice = e.message
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    private func start(provider: AssistantProvider, model: String, title: String) -> UUID {
        var c = AssistantConversation(providerID: provider.id, model: model)
        c.permissions = draftPermissions
        c.agentMode = draftAgentMode
        draftPermissions = nil
        draftAgentMode = nil
        c.title = AssistantConversation.title(from: title)
        conversations.insert(c, at: 0)
        layout.add(c.id)
        currentID = c.id
        return c.id
    }

    /// The block sent before the question: selection or passage, compiler errors, Typst reference. Checks the size budget.
    private func context(for question: String, provider: AssistantProvider, diagnostics: Bool) async throws -> String? {
        let problems = diagnostics && permissions.policy(.diagnostics) != .never ? AssistantContext.diagnostics(self.problems) : nil
        if provider.isOnDevice {
            let budget = OnDeviceContext.characterBudget(contextTokens: AppleOnDeviceModel.contextTokens)
            let passage = onDevicePassage(limit: budget / 3)
            let reference = await reference(for: question, budget: AssistantReference.onDeviceBudget)
            // Validates the fit; the question itself is added again when the request is built.
            let probe = try OnDeviceContext.request(question: question, history: [], passage: passage, diagnostics: problems, reference: reference, budget: budget)
            let block = String(probe.messages.last!.text.dropLast(question.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return block.isEmpty ? nil : block
        }
        // The size guard, before anything is stored; an agent reads the attached files itself.
        if !provider.isAgent { _ = try AssistantContext.files(try await attachedFiles()) }
        var selected = selection.flatMap { s in project.assistantText(of: s.path).flatMap { AssistantContext.selection(path: s.path.raw, in: $0, range: s.range) } }
        if selected == nil, let path = selection?.path ?? project.selectedFile, let text = project.assistantText(of: path) {
            // Without a selection the model still needs to know which section "this section" is.
            let caret = selection?.path == path ? selection!.range.location : project.buffer(for: path)?.restoredSelection.location ?? 0
            let section = OnDeviceContext.section(around: caret, in: text), ns = text as NSString
            selected = "The cursor is in \(path.raw) at line \(AssistantContext.line(of: caret, in: ns)), within its section at \(OnDeviceContext.lines(section, ns))."
        }
        let reference = await reference(for: question, budget: AssistantReference.hostedBudget)
        let block = [selected, problems, reference].compactMap { $0 }.joined(separator: "\n\n")
        return block.isEmpty ? nil : block
    }

    private var problems: [AssistantContext.Problem] { project.assistantProblems(errorsOnly: true) }

    /// The selection, else the section around the caret of the file shown in the editor.
    private func onDevicePassage(limit: Int) -> OnDeviceContext.Passage? {
        let path = selection?.path ?? project.selectedFile
        guard let path, let text = project.assistantText(of: path) else { return nil }
        let range = selection?.path == path ? selection!.range : NSRange(location: project.buffer(for: path)?.restoredSelection.location ?? 0, length: 0)
        return OnDeviceContext.passage(path: path.raw, text: text, selection: range, limit: limit)
    }

    /// Signatures and summaries for the functions used in the selection or the caret's section, asked one at a time.
    private func reference(for question: String, budget: Int) async -> String? {
        let path = selection?.path ?? project.selectedFile
        guard let path, FileKind(path: path.raw) == .typst, let text = project.assistantText(of: path) else { return nil }
        let sel = selection?.path == path ? selection!.range : NSRange(location: project.buffer(for: path)?.restoredSelection.location ?? 0, length: 0)
        let range = sel.length > 0 ? sel : OnDeviceContext.section(around: sel.location, in: text)
        guard (try? await project.open(path)) != nil else { return nil }
        var entries: [AssistantReference.Entry] = []
        for c in AssistantReference.candidates(in: text, range: range, question: question) {
            let signature = await project.signature(in: path, at: c.offset)
            var docs: String?
            if case .builtin(let d)? = await project.definition(in: path, at: c.offset) { docs = d.docs }
            if let e = AssistantReference.entry(name: c.name, signature: signature, docs: docs) { entries.append(e) }
        }
        return AssistantReference.block(entries, budget: budget)
    }

    private func attachedFiles() async throws -> [AssistantContext.File] {
        attachments.compactMap { p in project.assistantText(of: p).map { AssistantContext.File(path: p.raw, text: $0) } }
            + externalAttachments.compactMap { u in (try? String(contentsOf: u, encoding: .utf8)).map { AssistantContext.File(path: u.lastPathComponent, text: $0) } }
    }

    /// Streams an answer to the conversation's last user message.
    private func respond(in id: UUID, search: Bool? = nil) {
        guard let conversation = conversations.first(where: { $0.id == id }), let provider = providers.provider(conversation.providerID) else { return }
        guard providers.isReady(provider) else { notice = "\(provider.name): \(providers.status(provider))."; return }
        // Also for Retry after the conversation switched to a provider not used before.
        if providers.needsConsent(provider) {
            pendingConsent = PendingConsent(provider: provider, files: attachments.map(\.raw)) { [weak self] in
                self?.providers.consent(provider)
                self?.pendingConsent = nil
                self?.respond(in: id, search: search)
            }
            return
        }
        // Retry cannot ask again: it searches only when search is allowed outright.
        let search = search ?? (permissions.policy(.webSearch) == .allow)
        let answer = AssistantMessage(role: .assistant, text: "")
        change(id, save: false) { $0.messages.append(answer) }
        streamingID = answer.id
        streamingConversation = id
        turnStart = .now
        liveTools = []
        stopped.remove(id)
        // What earlier turns changed turns grey in the gutter.
        for b in project.openBuffers { b.previousAIChanges = Set(b.aiChanges.map(\.id)) }
        let tools = provider.isAgent ? [] : permissions.offered(provider: provider, model: conversation.model)
        task = Task { [weak self] in
            guard let self else { return }
            var current = answer.id
            var rounds: [UUID] = []
            do {
                var request = try await request(conversation, provider: provider, tools: tools)
                if search, AssistantPermissions.supportsWebSearch(provider: provider, model: conversation.model) { request.tools = [.webSearch] }
                if !provider.isOnDevice { request.clientTools = tools }
                try await AssistantAgent.run(client: client(for: provider), request: request, execute: { await self.runTool($0) }) { step in
                    switch step {
                    case .nextRound:
                        let next = AssistantMessage(role: .assistant, text: "")
                        rounds.append(current)
                        change(id, save: false) { $0.messages.append(next) }
                        current = next.id
                        streamingID = next.id
                    case .result(let r):
                        update(id, current) { m in
                            guard let i = m.toolCalls?.firstIndex(where: { $0.id == r.callID }) else { return }
                            m.toolCalls![i].result = r.content
                            m.toolCalls![i].isError = r.isError
                        }
                    case .stream(let event):
                        update(id, current) { m in
                            switch event {
                            case .text(let t): m.text += t
                            case .reasoning(let r): m.reasoning = (m.reasoning ?? "") + r
                            case .toolCall(let c): m.toolCalls = (m.toolCalls ?? []) + [ToolExchange(call: c)]
                            case .toolRan: break    // the agent loop turns it into toolCall and result
                            case .done(.refusal, _):
                                // Partial output of a declined answer is discarded; an agent's text may hold changes it already made.
                                if !provider.isAgent { m.text = "" }
                                m.error = AssistantError.declined.message
                            case .done(.maxTokens, _): m.truncated = true
                            case .done(.paused, _): m.text += "\n\n*The web search limit was reached before the answer was finished.*"
                            case .done: break
                            }
                        }
                    }
                }
            } catch is CancellationError {
            } catch let e as AssistantError {
                update(id, current) { $0.error = e.message }
            } catch {
                update(id, current) { $0.error = Task.isCancelled ? nil : error.localizedDescription }
            }
            // A stopped or failed answer applies nothing; an agent writes its changes itself.
            if !provider.isAgent, !Task.isCancelled, conversations.first(where: { $0.id == id })?.messages.first(where: { $0.id == current })?.error == nil {
                for m in rounds + [current] { await applyAutomatically(id, m) }
            }
            finish(id, current)
        }
    }

    /// An agent's client shares this window's running agents; a model's is built fresh for each turn.
    private func client(for p: AssistantProvider) -> any AssistantClient {
        guard p.isAgent else { return providers.client(for: p) }
        let command = p.command ?? "", root = project.rootURL, mcp = Bundle.main.path(forAuxiliaryExecutable: "typo-mcp")
        return ACPClient(provider: p, sessions: agents, attachments: attachments.map(project.url(for:)) + externalAttachments, changeFiles: permissions.policy(.changeFiles),
                         mode: current?.agentMode) { [weak self] in
            try await ACPAgent.launch(command: command, cwd: root, host: self, mcp: mcp).agent
        }
    }

    private func request(_ c: AssistantConversation, provider: AssistantProvider, tools: [ClientTool] = []) async throws -> AssistantRequest {
        if provider.isAgent {
            // No system prompt: its edit format would have the agent write edit blocks instead of files.
            var r = AssistantRequest(model: c.model, system: "", files: nil, messages: c.wireMessages())
            r.session = c.id.uuidString
            return r
        }
        if provider.isOnDevice {
            var turns = c.wireMessages(context: false)
            let last = c.messages.last { $0.role == .user }
            if turns.last?.role == .user { turns.removeLast() }
            let budget = OnDeviceContext.characterBudget(contextTokens: AppleOnDeviceModel.contextTokens)
            // The small model needs to be told apart what it is asked: with the edit format in its prompt it answers questions with edits.
            var verdict = ""
            for try await event in providers.client(for: provider).stream(OnDeviceContext.classifierRequest(last?.text ?? "")) {
                if case .text(let t) = event { verdict += t }
            }
            if OnDeviceContext.asksForChange(classifierReply: verdict) {
                let question = [last?.context, last?.text].compactMap { $0 }.joined(separator: "\n\n")
                return try OnDeviceContext.request(question: question, history: turns, passage: nil, diagnostics: nil, reference: nil, budget: budget)
            }
            // Only a question gets the tools: a change request carries the edit format and the window has no room for both.
            var r = try OnDeviceContext.request(question: OnDeviceContext.questionTurn(last?.text ?? "", context: last?.context), history: turns,
                                                passage: nil, diagnostics: nil, reference: nil, budget: budget,
                                                system: OnDeviceContext.questionPrompt + OnDeviceContext.toolNote(tools))
            r.clientTools = tools
            return r
        }
        var r = AssistantRequest(model: c.model, system: AssistantContext.systemPrompt(proposeEdits: permissions.policy(.changeFiles) != .never, tools: tools), files: try AssistantContext.files(try await attachedFiles()), messages: c.wireMessages(tools: !tools.isEmpty))
        r.session = c.id.uuidString
        return r
    }

    private func update(_ id: UUID, _ message: UUID, _ f: (inout AssistantMessage) -> Void) {
        change(id, save: false) { c in
            if let i = c.messages.firstIndex(where: { $0.id == message }) { f(&c.messages[i]) }
        }
    }

    private func finish(_ id: UUID, _ message: UUID) {
        let duration = turnStart.map { Date.now.timeIntervalSince($0) }
        change(id) { c in
            // A stopped answer with nothing in it leaves no trace.
            c.messages.removeAll { $0.id == message && $0.text.isEmpty && $0.error == nil && $0.reasoning == nil && $0.toolCalls == nil }
            if let i = c.messages.lastIndex(where: { $0.role == .assistant }), c.messages[i].duration == nil { c.messages[i].duration = duration }
            c.updated = .now
        }
        if streamingID == message {
            streamingID = nil; streamingConversation = nil; task = nil; turnStart = nil; liveTools = []
            if id != currentID || mode != .assistant { layout.unread.insert(id) }
            // Like Xcode, a turn that changed files opens the diff panel under it.
            if id == currentID, let c = current, let t = AssistantTurn.split(c.messages).last, !t.changes.isEmpty {
                diffFile = t.changes.first?.path
                showsDiff = true
            }
        }
    }

    func stop() {
        if let id = streamingConversation, task != nil { stopped.insert(id) }
        task?.cancel()
        answerTool(.deny)
        while pendingPermission != nil { answerPermission(nil) }
    }

    // MARK: Tools

    /// Runs a call of the model if the permissions say so; a refusal goes back to the model as an error result.
    private func runTool(_ call: ToolCall) async -> ToolResult {
        func fail(_ why: String) -> ToolResult { ToolResult(callID: call.id, content: why, isError: true) }
        var decision = runningPermissions.decide(call, attached: Set(attachments.map(\.raw)))
        if case .ask(let question) = decision {
            let answer = await withCheckedContinuation { (c: CheckedContinuation<ToolAnswer, Never>) in
                pendingTool = PendingTool(call: call, question: question)
                toolAnswer = c
            }
            decision = answer == .deny ? .deny("The user declined this request.") : .run
        }
        if case .deny(let why) = decision { return fail(why) }
        return await project.runTool(call)
    }

    /// The user's answer to the card of a held tool call; "always" lets the conversation use that permission from now on.
    func answerTool(_ answer: ToolAnswer) {
        guard let c = toolAnswer else { return }
        if answer == .always, let permission = pendingTool?.call.tool?.permission { setPermission(permission, .allow) }
        pendingTool = nil
        toolAnswer = nil
        c.resume(returning: answer)
    }

    /// The user's pick on an agent's permission card; nil when the turn stopped.
    func answerPermission(_ option: String?) {
        guard !permissionQueue.isEmpty else { return }
        permissionQueue.removeFirst().answer.resume(returning: option)
    }

    /// Sends the last question again after a failed answer.
    func retry(_ message: AssistantMessage) {
        guard let id = currentID, !isBusy else { return }
        change(id) { $0.messages.removeAll { $0.id == message.id } }
        respond(in: id)
    }

    // MARK: Edits

    func resolution(_ edit: ProposedEdit) -> EditResolution {
        AssistantEdits.resolve(edit, text: RelPath(edit.path).flatMap(project.assistantText(of:)))
    }

    /// The blocks of the answer that wait for Accept or Reject (permission "Ask").
    func pendingEdits(_ m: AssistantMessage) -> [Int] {
        let allowed = permissions
        return AssistantEdits.parse(m.text).enumerated().filter { m.edits[$0.offset] == nil && allowed.mode($0.element) == .ask }.map(\.offset)
    }

    func reject(_ m: AssistantMessage, _ index: Int) {
        guard let id = currentID else { return }
        update(id, m.id) { $0.edits[index] = .rejected }
        if let c = current { persist(c) }
    }

    /// Applies every block of the answer the permissions let through right away; one whose search text is not found
    /// or ambiguous is marked failed with the reason and nothing else of it is applied.
    private func applyAutomatically(_ id: UUID, _ message: UUID) async {
        guard let m = conversations.first(where: { $0.id == id })?.messages.first(where: { $0.id == message }) else { return }
        let allowed = permissions(of: id)
        for (i, edit) in AssistantEdits.parse(m.text).enumerated() where m.edits[i] == nil && allowed.mode(edit) == .apply {
            let failure = await apply(edit, message: message, index: i, in: id)
            if let failure { update(id, message) { $0.edits[i] = .failed; $0.editFailures = ($0.editFailures ?? [:]).merging([i: failure]) { $1 } } }
        }
        if let c = conversations.first(where: { $0.id == id }) { persist(c) }
    }

    /// Applies one edit as one undoable step through `Project.assistantEdit` (a new file is created first), remembers
    /// where it landed and marks it accepted. Returns why it could not be applied, or nil.
    private func apply(_ edit: ProposedEdit, message: UUID, index: Int, in id: UUID) async -> String? {
        do {
            let applied: AppliedChange
            switch resolution(edit) {
            case .replace(let path, let r, _, _):
                let ids = try await project.assistantEdit(path, [r], actionName: "Assistant Edit")
                applied = AppliedChange(path: path, changeID: ids.first, created: false)
            case .create(let path, let content):
                let shown = project.selectedFile
                let parts = path.raw.split(separator: "/")
                let folder = parts.count > 1 ? RelPath(parts.dropLast().joined(separator: "/")) : nil
                try project.createFile(named: String(parts.last!), in: folder)
                if project.selectedFile != shown { project.selectedFile = shown }    // createFile shows the new file; the editor stays where it was
                var ids: [UUID] = []
                if !content.isEmpty { ids = try await project.assistantEdit(path, [Replacement(range: NSRange(location: 0, length: 0), text: content)], actionName: "Assistant Edit") }
                applied = AppliedChange(path: path, changeID: ids.first, created: true)
            case .failed(let why):
                return why
            }
            ledger[key(message, index)] = applied
            update(id, message) { $0.edits[index] = .accepted }
            return nil
        } catch {
            return "The change could not be applied: \(error.localizedDescription)"
        }
    }

    /// Accept of a card.
    func accept(_ m: AssistantMessage, _ index: Int) async {
        guard let id = currentID, case let edits = AssistantEdits.parse(m.text), edits.indices.contains(index) else { return }
        if let why = await apply(edits[index], message: m.id, index: index, in: id) { notice = why } else if let c = current { persist(c) }
    }

    func acceptAll(_ m: AssistantMessage) async {
        for i in pendingEdits(m) {
            guard let fresh = current?.messages.first(where: { $0.id == m.id }) else { return }
            await accept(fresh, i)
        }
    }

    // MARK: Revert

    private func key(_ message: UUID, _ index: Int) -> String { "\(message)#\(index)" }

    /// Nil when the change can be reverted; else why not (for the tooltip).
    func revertBlocker(_ m: AssistantMessage, _ index: Int) -> String? {
        _ = changesRevision
        guard m.edits[index] == .accepted else { return "This change is not applied." }
        guard let a = ledger[key(m.id, index)], let buffer = project.buffer(for: a.path) else {
            return "This change was applied in an earlier session. Use Undo in the editor."
        }
        if a.created {
            guard let id = a.changeID else { return buffer.storage.length == 0 ? nil : "The new file was edited since." }
            return buffer.canRevert(id) ? nil : "The new file was edited since."
        }
        guard let id = a.changeID, buffer.canRevert(id) else { return "The changed text was edited since, so it cannot be reverted automatically." }
        return nil
    }

    /// Puts the text of the change back, or trashes the file it created; other edits of the file stay.
    func revert(_ m: AssistantMessage, _ index: Int) async {
        guard let id = conversations.first(where: { $0.messages.contains { $0.id == m.id } })?.id, revertBlocker(m, index) == nil,
              let a = ledger[key(m.id, index)] else { return }
        do {
            if a.created {
                try await project.moveToTrash(a.path)
            } else if let c = a.changeID, let buffer = project.buffer(for: a.path) {
                buffer.revertAssistant(c)
            }
        } catch {
            notice = "The change could not be reverted: \(error.localizedDescription)"
            return
        }
        ledger[key(m.id, index)] = nil
        update(id, m.id) { $0.edits[index] = .reverted }
        if let c = conversations.first(where: { $0.id == id }) { persist(c) }
    }

    /// Reverts a file's applied edits of the conversation, newest first.
    func revert(_ change: AssistantFileChange) async {
        for e in change.edits.reversed() {
            guard let m = conversations.lazy.flatMap(\.messages).first(where: { $0.id == e.message }) else { continue }
            await revert(m, e.index)
        }
    }

    /// The gutter's "Discard Change": each change in the mark goes back, newest first, through Revert where the
    /// transcript tracks it, so its card says reverted.
    func discard(_ range: NSRange, in buffer: Buffer) async {
        for c in buffer.aiChanges(in: range).reversed() {
            let tracked = ledger.first { $0.value.changeID == c.id && $0.value.path == buffer.path }?.key.split(separator: "#")
            if let tracked, tracked.count == 2, let mid = UUID(uuidString: String(tracked[0])), let index = Int(tracked[1]),
               let m = conversations.lazy.flatMap(\.messages).first(where: { $0.id == mid }) {
                await revert(m, index)
            } else {
                buffer.revertAssistant(c.id)
            }
        }
    }

    /// The accepted changes of the answer, as (edit index, edit).
    func appliedChanges(_ m: AssistantMessage) -> [(index: Int, edit: ProposedEdit)] {
        AssistantEdits.parse(m.text).enumerated().filter { m.edits[$0.offset] == .accepted }.map { ($0.offset, $0.element) }
    }

    // MARK: Transcript

    func setFeedback(_ m: AssistantMessage, _ good: Bool?) {
        guard let id = conversations.first(where: { $0.messages.contains { $0.id == m.id } })?.id else { return }
        change(id) { c in if let i = c.messages.firstIndex(where: { $0.id == m.id }) { c.messages[i].feedback = good } }
    }

    /// The diff panel under the conversation, and the file it scrolls to.
    var showsDiff = false
    var diffFile: String?

    func showDiff(_ path: String) {
        diffFile = path
        showsDiff = true
    }

    /// Opens a project file the transcript links to, at `line` when given.
    func openFile(_ path: String, line: Int? = nil) {
        guard let rel = RelPath(path) ?? ACPFiles.projectPath(path, root: project.rootURL) else { return }
        Task {
            do { _ = try await project.open(rel) } catch { notice = "The file could not be opened: \(error.localizedDescription)"; return }
            mode = .navigator
            if let line { project.showLine(rel, line: line, column: nil) } else { project.openPermanently(rel) }
        }
    }

    // MARK: Show

    /// Whether "Show in Editor" has something to show: a change that applies cleanly, or one that is applied.
    func canShowInEditor(_ m: AssistantMessage, _ edit: ProposedEdit, index: Int) -> Bool {
        if m.edits[index] == .accepted { return true }
        guard m.edits[index] == nil, case .replace = resolution(edit) else { return false }
        return true
    }

    /// Opens the file in the editor. A pending change is drawn over the text with Accept and Reject, and the buffer
    /// stays as it is until Accept; an applied one is selected where it landed.
    func showInEditor(_ m: AssistantMessage, _ index: Int) async {
        guard case let edits = AssistantEdits.parse(m.text), edits.indices.contains(index), let path = RelPath(edits[index].path) else { return }
        let edit = edits[index]
        do {
            let buffer = try await project.open(path)
            mode = .navigator
            if m.edits[index] == .accepted {
                let tracked = ledger[key(m.id, index)]?.changeID.flatMap { id in buffer.aiChanges.first { $0.id == id && !$0.edited }?.range }
                let found = tracked ?? (buffer.storage.string as NSString).range(of: edit.replace)
                project.show(path, range: found.location == NSNotFound ? NSRange(location: 0, length: 0) : found, flash: true)
            } else if case .replace(_, let r, _, _) = resolution(edit) {
                project.show(path, range: NSRange(location: r.range.location, length: 0))
                buffer.inlineDiff = InlineDiffPreview(range: r.range, replacement: r.text, accept: { [weak self, weak buffer] in
                    buffer?.inlineDiff = nil
                    Task { await self?.accept(m, index) }
                }, reject: { [weak self, weak buffer] in
                    buffer?.inlineDiff = nil
                    self?.reject(m, index)
                })
            }
        } catch {
            notice = "The file could not be opened: \(error.localizedDescription)"
        }
    }
}

// MARK: - Agent host

extension AssistantModel: ACPHost {
    /// Edits follow the "Change files" permission where it decides alone; everything else asks with the agent's options.
    func permission(for call: ACPToolCall, options: [ACPOption]) async -> String? {
        func option(_ kind: String) -> String? { options.first { $0.kind == kind }?.id }
        let permissions = runningPermissions
        // Typo's own MCP tools only read the project; a page preview still asks, since its image goes to the provider.
        if call.title.hasPrefix("typo: "), !call.title.hasSuffix("view_preview"), let id = option("allow_once") { return id }
        if call.changesFiles {
            switch permissions.policy(.changeFiles) {
            case .allow: if let id = option("allow_once") { return id }
            case .never: if let id = option("reject_once") { return id }
            case .ask: break
            }
        }
        return await withCheckedContinuation { c in permissionQueue.append((PendingPermission(call: call, options: options), c)) }
    }

    func readTextFile(_ path: String) async throws -> String {
        let rel = try projectPath(path)
        if let b = project.buffer(for: rel) { return b.storage.string }
        guard let text = try? String(contentsOf: project.url(for: rel), encoding: .utf8) else { throw ACPError(ACPError.notFound, "\(rel.raw) does not exist or is not a text file.") }
        return text
    }

    /// Lands in the editor as one undoable step with AI marks, and in the answer as an applied change that Revert takes back.
    func writeTextFile(_ path: String, content: String) async throws {
        let rel = try projectPath(path)
        let permissions = runningPermissions
        guard permissions.policy(.changeFiles) != .never else { throw ACPError(ACPError.internalError, "The user does not allow changes to files.") }
        guard let id = streamingConversation, let message = streamingID else { throw ACPError(ACPError.internalError, "No answer is in progress.") }
        let url = project.url(for: rel)
        guard FileKind.isText(rel.raw) else {
            // No editor buffer can hold it, so nothing to keep in step: write it as it is.
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url, options: .atomic)
            return
        }
        if project.buffer(for: rel) != nil || FileManager.default.fileExists(atPath: url.path) {
            let old = try await project.open(rel).storage.string
            guard let r = ACPFiles.replacement(old: old, new: content) else { return }
            let ids = try await project.assistantEdit(rel, [r], actionName: agentEditName)
            record(ACPFiles.edit(path: rel.raw, old: old, r), AppliedChange(path: rel, changeID: ids.first, created: false), in: id, message)
        } else {
            guard permissions.policy(.createFiles) != .never else { throw ACPError(ACPError.internalError, "The user does not allow new files.") }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let shown = project.selectedFile
            try project.createFile(named: url.lastPathComponent, in: rel.parent)
            if project.selectedFile != shown { project.selectedFile = shown }    // the editor stays where it was
            let ids = content.isEmpty ? [] : try await project.assistantEdit(rel, [Replacement(range: NSRange(location: 0, length: 0), text: content)], actionName: agentEditName)
            record(ProposedEdit(path: rel.raw, search: "", replace: content), AppliedChange(path: rel, changeID: ids.first, created: true), in: id, message)
        }
    }

    /// "Claude Code Edit": the undo step names the agent that made it.
    private var agentEditName: String { "\((provider?.name ?? "Agent").replacingOccurrences(of: " (ACP)", with: "")) Edit" }

    /// Claude's own Edit and Write tools write the file themselves: hold its reload and note its text, so the write
    /// can land like `writeTextFile`'s.
    func editStarted(_ call: ACPToolCall) async {
        guard let id = streamingConversation, let message = streamingID, agentEdits[call.id] == nil else { return }
        var snapshots: [AgentSnapshot] = []
        for path in call.paths.compactMap({ ACPFiles.projectPath($0, root: project.rootURL) }) where FileKind.isText(path.raw) {
            if let s = await project.holdForAgent(path) { snapshots.append(s) }
        }
        agentEdits[call.id] = (snapshots, id, message)
    }

    /// What the call wrote becomes one "Agent Edit" step, recorded in its answer for the card, the changes bar and Revert.
    func editEnded(_ call: ACPToolCall, completed: Bool) async {
        guard let e = agentEdits.removeValue(forKey: call.id) else { return }
        for s in e.snapshots {
            if !completed {
                await project.releaseAgentHold(s)
            } else if let (edit, changeID) = await project.adoptAgentWrite(s, actionName: agentEditName) {
                record(edit, AppliedChange(path: s.path, changeID: changeID, created: s.text == nil), in: e.conversation, e.message)
            }
        }
        // A stopped answer finished already and saved without these changes.
        if streamingID != e.message, let c = conversations.first(where: { $0.id == e.conversation }) { persist(c) }
    }

    func commandsChanged(_ commands: [ACPCommand]) { agentCommands = commands }

    func optionsChanged(_ options: ACPSessionOptions) {
        let id = streamingConversation ?? currentID
        guard let p = conversations.first(where: { $0.id == id }).flatMap({ providers.provider($0.providerID) }) ?? provider, p.isAgent else { return }
        agentOptions[p.id] = options
    }

    func toolCallChanged(_ call: ACPToolCall) {
        guard streamingID != nil else { return }
        if let i = liveTools.firstIndex(where: { $0.id == call.id }) { liveTools[i] = call } else { liveTools.append(call) }
    }

    /// The permissions of the running turn's conversation; the shown one may be another.
    private var runningPermissions: AssistantPermissions { streamingConversation.map(permissions(of:)) ?? permissions }

    private func projectPath(_ path: String) throws -> RelPath {
        guard let rel = ACPFiles.projectPath(path, root: project.rootURL) else { throw ACPError(ACPError.invalidParams, "\(path) is outside the project folder.") }
        return rel
    }

    /// The change joins the streaming answer as an applied edit block, which the card, the changes bar and Revert read.
    private func record(_ edit: ProposedEdit, _ change: AppliedChange, in id: UUID, _ message: UUID) {
        update(id, message) { m in
            let index = AssistantEdits.parse(m.text).count
            let gap = m.text.isEmpty || m.text.hasSuffix("\n\n") ? "" : m.text.hasSuffix("\n") ? "\n" : "\n\n"
            m.text += gap + ACPFiles.block(edit) + "\n\n"
            m.edits[index] = .accepted
            ledger[key(message, index)] = change
        }
    }
}

