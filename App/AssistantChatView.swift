import AppKit
import SwiftUI
import TypoKit
import ACPProtocol
import TypoACP
import TypoAssistant
import TypstEngine

/// The editor area in assistant mode, like Xcode's conversations: a breadcrumb, the transcript in a centred column,
/// and the prompt box (or the permission bar) at the bottom.
struct AssistantChatView: View {
    @Bindable var model: AssistantModel
    private let providers = AssistantProviderStore.shared
    @Environment(\.openSettings) private var openSettings
    @State private var showsPermissions = false
    static let column: CGFloat = 760

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !providers.hasReadyProvider {
                ContentUnavailableView {
                    Label("Set Up a Model Provider", systemImage: "sparkles")
                } description: {
                    Text(providers.onDevice.isAvailable ? "" : "\(providers.onDevice.status). You can also add a model provider with your own API key.")
                } actions: {
                    Button("Open Intelligence Settings") {
                        UserDefaults.standard.set("intelligence", forKey: SettingsKey.tab)
                        openSettings()
                    }
                }
                .onAppear { providers.refreshAvailability() }
            } else if model.showsDiff {
                VSplitView {
                    conversation.frame(minHeight: 260)
                    AssistantDiffPanel(model: model).frame(minHeight: 120, idealHeight: 280)
                }
            } else {
                conversation
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var conversation: some View {
                transcript
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 8) {
                            if let pending = model.shownPermission {
                                AssistantPermissionBar(model: model, pending: pending)
                            } else {
                                AssistantPromptBox(model: model)
                            }
                        }
                        .frame(maxWidth: Self.column)
                        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 14)
                        .frame(maxWidth: .infinity)
                        // The transcript scrolls under the prompt; it must not show through.
                        .background(Color(nsColor: .textBackgroundColor))
                    }
    }

    /// "✦ › Title", with the conversation's permissions and New Conversation at the right.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            Text(model.current?.title ?? "New Conversation").font(.system(size: 12)).lineLimit(1)
            Spacer()
            if model.current?.messages.contains(where: { !$0.edits.isEmpty }) == true || model.showsDiff {
                Toggle("Changes", systemImage: "plusminus", isOn: Binding(get: { model.showsDiff }, set: { model.showsDiff = $0 }))
                    .toggleStyle(.button).buttonStyle(.borderless).labelStyle(.iconOnly)
                    .help("Show the changes of this conversation")
            }
            Button("Permissions", systemImage: "checkmark.shield") { showsPermissions.toggle() }
                .buttonStyle(.borderless).labelStyle(.iconOnly)
                .help("What the assistant may do in this conversation")
                .popover(isPresented: $showsPermissions, arrowEdge: .bottom) { AssistantPermissionsPopover(model: model) }
            Button("New Conversation", systemImage: "square.and.pencil") { model.newConversation() }
                .buttonStyle(.borderless).labelStyle(.iconOnly)
                .help("Starts a new conversation with the assistant")
        }
        .padding(.horizontal, 12).frame(height: 30)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    let turns = AssistantTurn.split(model.current?.messages ?? [])
                    ForEach(Array(turns.enumerated()), id: \.element.id) { i, t in
                        AssistantTurnView(model: model, turn: t, header: Self.header(t, after: i > 0 ? turns[i - 1] : nil)).id(t.id).assistantEntrance()
                    }
                    if let notice = model.notice {
                        Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if let pending = model.pendingConsent { consent(pending) }
                    if let pending = model.pendingSearch { search(pending) }
                    if let pending = model.shownTool { tool(pending) }
                    if let pending = model.shownPermission { permissionDiffs(pending) }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: Self.column)
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.current?.messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.current?.messages.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.shownTool?.call.id) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.shownPermission?.call.id) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.current?.messages.last?.toolCalls?.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.currentID) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    /// A turn starts a new section when it is the first, on a new day, or an hour after the one before.
    static func header(_ t: AssistantTurn, after previous: AssistantTurn?) -> Date? {
        guard let d = t.user?.created else { return nil }
        guard let p = previous?.answers.last?.created ?? previous?.user?.created else { return d }
        return !Calendar.current.isDate(d, inSameDayAs: p) || d.timeIntervalSince(p) > 3600 ? d : nil
    }

    /// Asked before a message when the permission to search the web is "Ask".
    private func search(_ p: AssistantModel.PendingSearch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("May the assistant search the web?", systemImage: "globe").font(.headline)
            Text("Search queries go to \(p.provider.name).").fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Don't Search") { p.resume(false, false) }
                Button("Always in This Conversation") { p.resume(true, true) }
                Button("Allow Once") { p.resume(true, false) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Asked when the model calls a tool whose permission is "Ask".
    private func tool(_ p: AssistantModel.PendingTool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(p.question, systemImage: "doc.text.magnifyingglass").font(.headline)
            Text(model.provider?.isOnDevice == true ? "It stays on this Mac." : "What it reads goes to \(model.provider?.name ?? "the provider").").fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Deny") { model.answerTool(.deny) }
                Button("Always in This Conversation") { model.answerTool(.always) }
                Button("Allow Once") { model.answerTool(.once) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The changes an agent asks to make, above the permission bar.
    @ViewBuilder private func permissionDiffs(_ p: AssistantModel.PendingPermission) -> some View {
        ForEach(Array(p.call.diffs.enumerated()), id: \.offset) { _, d in
            let path = ACPFiles.projectPath(d.path, root: model.project.rootURL)?.raw ?? d.path
            AssistantChangeCard(edit: ProposedEdit(path: path, search: d.search, replace: d.replace), status: .pending, showsButtons: false)
        }
    }

    /// The one-time notice before a provider first receives files.
    private func consent(_ p: AssistantModel.PendingConsent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Send to \(p.provider.name)?", systemImage: "network").font(.headline)
            Text(p.provider.isAgent
                 ? "\(p.provider.name) runs on this Mac in the project folder. It reads and changes the project's files, and sends what it reads to its own provider."
                 : p.files.isEmpty
                 ? "Your message and the selected text will be sent to \(p.provider.name) (\(p.provider.host))."
                 : "The contents of \(p.files.joined(separator: ", ")) and your message will be sent to \(p.provider.name) (\(p.provider.host)). Files you attach later are sent too.")
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { model.pendingConsent = nil }
                Button("Continue") { p.resume() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// One answer: tool calls, the text with its code cards, edits still waiting for a decision, errors.
struct AssistantMessageView: View {
    let model: AssistantModel
    let message: AssistantMessage

    var body: some View {
        let streaming = model.streamingID == message.id
        VStack(alignment: .leading, spacing: 10) {
            if !streaming || !message.text.isEmpty, let r = message.reasoning, !r.isEmpty {
                DisclosureGroup {
                    Text(r).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Thought", systemImage: "bubble.left").foregroundStyle(.secondary)
                }
                .assistantEntrance()
            }
            ForEach(message.toolCalls ?? []) { AssistantToolRow(exchange: $0, note: model.accessNotes[$0.call.id]).assistantEntrance() }
            let permissions = model.permissions
            let segments = AssistantEdits.segments(message.text)
            let files = Set(model.project.allFiles.map(\.raw))
            ForEach(Array(segments.enumerated()), id: \.offset) { i, s in
                switch s {
                case .text(let t): AssistantMarkdown(text: t, files: files) { model.openFile($0) }.assistantEntrance()
                case .edit(let e):
                    // The edit's index among the message's edits, which is what `edits` (accepted/rejected) is keyed by.
                    let index = segments[..<i].count { if case .edit = $0 { true } else { false } }
                    // Applied changes show as the turn's file capsules and in the diff panel.
                    if message.edits[index] != .accepted, permissions.shows(e) || message.edits[index] != nil {
                        AssistantEditCard(model: model, message: message, index: index, edit: e).assistantEntrance()
                    }
                }
            }
            if message.truncated {
                Text("The answer reached the length limit and may be incomplete.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = message.error {
                HStack(alignment: .firstTextBaseline) {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    Button("Retry") { model.retry(message) }.disabled(model.isBusy)
                }
            }
            if model.pendingEdits(message).count > 1, !streaming {
                Button("Accept All") { Task { await model.acceptAll(message) } }
                    .help("Applies every pending change of this answer, one after another")
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One change of an answer, bound to the model: applied, waiting for Accept, reverted, rejected or failed.
struct AssistantEditCard: View {
    let model: AssistantModel
    let message: AssistantMessage
    let index: Int
    let edit: ProposedEdit

    var body: some View {
        AssistantChangeCard(edit: edit, status: status, showsButtons: model.streamingID != message.id,
                            revertBlocker: model.revertBlocker(message, index),
                            open: { if model.canShowInEditor(message, edit, index: index) { Task { await model.showInEditor(message, index) } } },
                            accept: { Task { await model.accept(message, index) } },
                            reject: { model.reject(message, index) },
                            revert: { Task { await model.revert(message, index) } })
    }

    private var status: AssistantChangeCard.Status {
        switch message.edits[index] {
        case .accepted?: .applied
        case .reverted?: .reverted
        case .rejected?: .rejected
        case .failed?: .failed(message.editFailures?[index] ?? "The change was not applied.")
        case nil:
            if case .failed(let why) = model.resolution(edit) { .failed(why) } else { .pending }
        }
    }
}

/// The prompt at the bottom, like Xcode's: the field, then attach, model and mode menus and send.
struct AssistantPromptBox: View {
    @Bindable var model: AssistantModel
    private let providers = AssistantProviderStore.shared
    @State private var focusRequest = 0
    @State private var commandIndex = 0
    @State private var mentionQuery: AssistantPromptField.Query?
    /// The draft the completion list was closed for with Escape; it opens again once the draft changes.
    @State private var dismissed: String?
    @State private var picksFiles = false
    @State private var showsModes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.current == nil { suggestions }
            VStack(alignment: .leading, spacing: 8) {
                if !chipFiles.isEmpty || !model.externalAttachments.isEmpty, model.provider?.isOnDevice != true { attachmentChips }
                AssistantPromptField(text: $model.draft, mentions: $model.mentions, query: $mentionQuery, selection: $commandIndex,
                                     dismissed: $dismissed, items: completions, focusRequest: focusRequest) { model.send() }
                    .overlay(alignment: .topLeading) {
                        if model.draft.isEmpty {
                            Text(placeholder).font(.system(size: 14)).foregroundStyle(.placeholder).allowsHitTesting(false)
                        }
                    }
                    .onChange(of: model.draft) { old, new in
                        commandIndex = 0
                        if dismissed != nil, new != dismissed { dismissed = nil }
                    }
                    .onChange(of: mentionQuery) { commandIndex = 0 }
                    .frame(minHeight: 52, alignment: .topLeading)
                HStack(spacing: 14) {
                    if model.provider?.isOnDevice != true { attachMenu }
                    modelMenu
                    modeMenu
                    Spacer(minLength: 0)
                    sendButton
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
            .contentShape(Rectangle())
            .onTapGesture { focusRequest += 1 }
        }
        .onAppear { focusRequest += 1 }
        .onChange(of: model.currentID) { focusRequest += 1 }
        .sheet(isPresented: $picksFiles) { AssistantFilePicker(model: model) }
    }

    /// The agent or provider by name, without the "(ACP)" of its preset.
    private var providerName: String { (model.provider?.name ?? "the assistant").replacingOccurrences(of: " (ACP)", with: "") }

    private var placeholder: String {
        model.current?.messages.isEmpty == false ? "Follow up with \(providerName)" : "New conversation with \(providerName)"
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chipFiles, id: \.self) { f in
                    chip(name: (f.raw as NSString).lastPathComponent, help: f.raw) { model.attachments.removeAll { $0 == f } }
                }
                ForEach(model.externalAttachments, id: \.self) { u in
                    chip(name: u.lastPathComponent, help: u.path) { model.externalAttachments.removeAll { $0 == u } }
                }
            }
        }
    }

    /// Attached files without the ones the draft mentions, which show in the text.
    private var chipFiles: [RelPath] { model.attachments.filter { !model.mentions.contains($0) } }

    private func chip(name: String, help: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
            Text(name)
            Button(action: remove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Detach \(help)")
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
        .help(help)
    }

    private var sendButton: some View {
        Group {
            if model.isStreaming {
                Button { model.stop() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 10, weight: .bold)).frame(width: 26, height: 26)
                        .background(.quaternary, in: Circle())
                }
                .accessibilityLabel("Stop").help("Stop the answer")
            } else {
                let empty = model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { model.send() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 13, weight: .semibold)).frame(width: 26, height: 26)
                        .foregroundStyle(empty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.white))
                        .background(empty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.accentColor), in: Circle())
                }
                .accessibilityLabel("Send").help("Send (Return)")
                .disabled(empty || !(model.provider.map(providers.isReady) ?? false))
            }
        }
        .buttonStyle(.plain)
    }

    /// The agent's commands matching what follows "/", until the first space.
    private var commandMatches: [ACPCommand] {
        guard model.draft.hasPrefix("/"), !model.draft.contains(" ") else { return [] }
        let typed = model.draft.dropFirst().lowercased()
        // Names starting with the typed text first, then names containing it.
        let all = model.agentCommands.filter { typed.isEmpty || $0.name.lowercased().contains(typed) }
        return all.filter { $0.name.lowercased().hasPrefix(typed) } + all.filter { !$0.name.lowercased().hasPrefix(typed) }
    }

    /// The completion list's entries: project files after "@", else the agent's commands after "/".
    private var completions: [AssistantPromptField.Completion] {
        guard dismissed != model.draft else { return [] }
        // On-device answers take no files.
        if let q = mentionQuery, model.provider?.isOnDevice != true {
            let paths = model.project.allFiles.map(\.raw).filter(FileKind.isText)
            return AssistantMentions.matches(q.query, in: paths).map { .init(id: $0, kind: .file, name: ($0 as NSString).lastPathComponent, detail: nil, help: $0) }
        }
        return commandMatches.map { c in
            let k = AssistantCommandKind.classify(c.description)
            return .init(id: c.name, kind: k.kind == .skill ? .skill : .command, name: c.name, detail: k.description.isEmpty ? nil : k.description, help: k.description)
        }
    }

    // MARK: Suggestions

    /// Three prompts for an empty conversation, the ones that fit the project's state first.
    private var suggestions: some View {
        VStack(spacing: 8) {
            ForEach(Array(picks.prefix(3).enumerated()), id: \.offset) { _, p in
                Button { p.1() } label: {
                    Text(p.0).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [AssistantPalette.amber, AssistantPalette.coral, AssistantPalette.raspberry], startPoint: .leading, endPoint: .trailing))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.background, in: Capsule())
                        .overlay(Capsule().strokeBorder(.separator))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var picks: [(String, () -> Void)] {
        var out: [(String, () -> Void)] = []
        if model.hasErrors, model.permissions.policy(.diagnostics) != .never { out.append(("Help me fix the compile errors", { model.send(.fixErrors) })) }
        if model.hasSelection { out.append(("Explain the selected text", { model.send(.explain) })) }
        if model.project.isRepository {
            out.append(("Review the changes I made on this branch", { model.send("Review the changes I made on this branch.") }))
        }
        for t in ["Explain this project's structure", "Improve the wording of this section", "Check my citations", "Make my tables consistent"] {
            out.append((t, { model.send(t + ".") }))
        }
        return out
    }

    // MARK: Menus

    private func menuLabel(_ title: String) -> some View {
        // One Text: a menu label keeps only a text and an icon, and puts the icon first.
        (Text(title + " ") + Text(Image(systemName: "chevron.up.chevron.down")).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary))
            .font(.system(size: 12)).lineLimit(1)
    }

    private var attachMenu: some View {
        Menu {
            Button("Add Content from Project…") { picksFiles = true }
            Button("Upload Files…") { upload() }
        } label: {
            Image(systemName: "paperclip")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Attach Files").help("Attach files to the next message")
    }

    private func upload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            // A file inside the project is attached by its project path, like one picked from the project.
            if let rel = ACPFiles.projectPath(url.path, root: model.project.rootURL) {
                if !model.attachments.contains(rel) { model.attachments.append(rel) }
            } else if !model.externalAttachments.contains(url) {
                model.externalAttachments.append(url)
            }
        }
    }

    /// The model of the conversation's provider, and Other… to switch provider.
    private var modelMenu: some View {
        Menu {
            if let p = model.provider {
                if p.isAgent, let models = model.shownAgentOptions?.models, !models.choices.isEmpty {
                    let byDefault = models.choices.first { $0.id == models.current }?.name
                    Toggle(byDefault.map { "Default (\($0))" } ?? "Default", isOn: Binding(get: { model.model.isEmpty }, set: { _ in model.choose(p, model: "") }))
                    Divider()
                    ForEach(models.choices) { c in
                        Toggle(c.name, isOn: Binding(get: { model.model == c.id }, set: { _ in model.choose(p, model: c.id) }))
                    }
                    Divider()
                } else if !p.isAgent, !p.isOnDevice, case let ms = models(of: p), ms.count > 1 {
                    ForEach(ms, id: \.self) { m in Toggle(m, isOn: Binding(get: { model.model == m }, set: { _ in model.choose(p, model: m) })) }
                    Divider()
                }
            }
            Menu("Other…") {
                ForEach(providers.providers) { p in
                    Toggle(p.name, isOn: Binding(get: { model.provider?.id == p.id }, set: { _ in model.choose(p, model: models(of: p).first ?? p.model) }))
                        .disabled(!providers.isReady(p))
                }
            }
        } label: {
            menuLabel(modelTitle)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Model").help("The model of this conversation")
    }

    private func models(of p: AssistantProvider) -> [String] {
        Array(Set([providers.defaultModel(for: p), p.model] + p.preset.models).filter { !$0.isEmpty }).sorted()
    }

    private var modelTitle: String {
        guard let p = model.provider else { return "Choose a Model" }
        if p.isAgent {
            let models = model.shownAgentOptions?.models
            let id = model.model.isEmpty ? models?.current : model.model
            return models?.choices.first { $0.id == id }?.name ?? providerName
        }
        return p.isOnDevice ? p.name : model.model
    }

    /// The agent's modes, when it offers any.
    @ViewBuilder private var modeMenu: some View {
        if model.provider?.isAgent == true, let modes = model.shownAgentOptions?.modes, !modes.choices.isEmpty {
            let shown = currentMode(modes)
            Menu {
                ForEach(modes.choices) { c in
                    Toggle(c.name, isOn: Binding(get: { shown == c.id }, set: { _ in model.setAgentMode(c.id) }))
                }
                Divider()
                Button("About Modes…") { showsModes = true }
            } label: {
                let name = modes.choices.first { $0.id == shown }?.name ?? "Default"
                menuLabel(name.localizedCaseInsensitiveContains("mode") ? name : name + " Mode")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Mode").help("How freely the agent works in this conversation")
            .popover(isPresented: $showsModes, arrowEdge: .top) { AssistantModesAbout(modes: modes.choices) }
        }
    }

    /// The conversation's pick, else the mode the "Change files" permission maps to, else the agent's own.
    private func currentMode(_ modes: ACPSelector) -> String? {
        if let m = model.agentMode { return m }
        let mapped = ACPAgent.mode(for: model.permissions.policy(.changeFiles))
        return modes.choices.contains { $0.id == mapped } ? mapped : modes.current
    }
}

/// "About Modes…": what each of the agent's modes does.
struct AssistantModesAbout: View {
    let modes: [ACPChoice]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Modes").font(.headline)
            ForEach(modes) { m in
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.name).fontWeight(.medium)
                    Text(m.description ?? Self.fallback(m.id)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14).frame(width: 300)
    }

    /// Our wording for the common mode ids when the agent gives no description.
    static func fallback(_ id: String) -> String {
        switch id {
        case "default": "Edits files inside the project and asks before running commands or touching anything outside it."
        case "acceptEdits": "Fewer prompts: the agent decides on edits itself."
        case "plan": "Plans and answers without changing files."
        case "bypassPermissions": "Never asks; the agent does what it decides."
        default: "A mode of the agent."
        }
    }
}

/// "Add Content from Project…": the project's text files to attach.
struct AssistantFilePicker: View {
    @Bindable var model: AssistantModel
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).padding(10)
            List {
                ForEach(model.project.allFiles.filter { FileKind.isText($0.raw) && (filter.isEmpty || $0.raw.localizedCaseInsensitiveContains(filter)) }, id: \.self) { f in
                    Toggle(f.raw, isOn: Binding(get: { model.attachments.contains(f) },
                                                set: { on in if on { model.attachments.append(f) } else { model.attachments.removeAll { $0 == f } } }))
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 420, height: 440)
    }
}

/// Xcode's intelligence colors (sRGB), for the suggestion chips.
enum AssistantPalette {
    static let amber = Color(.sRGB, red: 1.000, green: 0.718, blue: 0.200)
    static let coral = Color(.sRGB, red: 0.976, green: 0.482, blue: 0.345)
    static let raspberry = Color(.sRGB, red: 0.980, green: 0.263, blue: 0.408)
}

extension NSAttributedString.Key {
    /// The `RelPath` an "@" mention token in the prompt stands for.
    static let typoMention = NSAttributedString.Key("TypoMention")
}

/// The prompt's text: Return sends, Shift-Return breaks the line, and "@file" mentions are grey monospaced tokens
/// that delete as one. Shows the "/" and "@" completions in a panel under the caret.
struct AssistantPromptField: NSViewRepresentable {
    struct Query: Equatable { var range: NSRange; var query: String }

    struct Completion: Identifiable {
        enum Kind { case command, skill, file }
        var id: String
        var kind: Kind
        var name: String
        var detail: String?
        var help: String
    }

    @Binding var text: String
    @Binding var mentions: [RelPath]
    @Binding var query: Query?
    @Binding var selection: Int
    @Binding var dismissed: String?
    var items: [Completion]
    var focusRequest: Int
    var send: () -> Void

    static let font = NSFont.systemFont(ofSize: 14)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = context.coordinator.textView
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = true
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.font = Self.font
        tv.textColor = .labelColor
        tv.typingAttributes = Coordinator.base
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.setAccessibilityLabel("Prompt")
        tv.resigned = { [weak coordinator = context.coordinator] in coordinator?.hidePopup() }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        let tv = c.textView
        if tv.string != text, !tv.hasMarkedText() {
            // Set from outside (sent, a command picked, a suggestion): plain text, so no mentions.
            c.updating = true
            tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Coordinator.base))
            tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            c.updating = false
            DispatchQueue.main.async { c.sync() }
        }
        if c.focusRequest != focusRequest {
            c.focusRequest = focusRequest
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        c.updatePopup()
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) { coordinator.hidePopup() }

    /// As tall as the text, from one line up to ten; then it scrolls.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let tv = context.coordinator.textView
        guard let width = proposal.width, width > 0, let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let line = lm.defaultLineHeight(for: Self.font)
        return CGSize(width: width, height: min(max(lm.usedRect(for: tc).height, line), line * 10))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AssistantPromptField
        let textView = PromptTextView(usingTextLayoutManager: false)
        var focusRequest = -1
        var updating = false
        private var panel: NSPanel?
        private var host: CompletionHost?

        static let base: [NSAttributedString.Key: Any] = [.font: AssistantPromptField.font, .foregroundColor: NSColor.labelColor]

        init(_ parent: AssistantPromptField) { self.parent = parent }

        // MARK: Text

        func textDidChange(_ notification: Notification) { sync() }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updating else { return }
            updateQuery()
        }

        func textView(_ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:],
                      toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]) -> [NSAttributedString.Key: Any] {
            // Typing next to a token never continues it.
            Self.base
        }

        /// The draft and its mentions from the text; a token edited inside turns back into plain text.
        func sync() {
            guard let storage = textView.textStorage else { return }
            var paths: [RelPath] = [], broken: [NSRange] = []
            storage.enumerateAttribute(.typoMention, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard let path = value as? RelPath else { return }
                if storage.attributedSubstring(from: range).string == (path.raw as NSString).lastPathComponent {
                    if !paths.contains(path) { paths.append(path) }
                } else {
                    broken.append(range)
                }
            }
            if !broken.isEmpty {
                storage.beginEditing()
                for r in broken { storage.setAttributes(Self.base, range: r) }
                storage.endEditing()
            }
            if parent.text != textView.string { parent.text = textView.string }
            if parent.mentions != paths { parent.mentions = paths }
            updateQuery()
        }

        private func updateQuery() {
            let sel = textView.selectedRange()
            let q = sel.length == 0 && !textView.hasMarkedText() ? AssistantMentions.query(in: textView.string, caret: sel.location) : nil
            let new = q.map { Query(range: $0.range, query: $0.query) }
            if parent.query != new { parent.query = new }
        }

        // MARK: Keys

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let items = parent.items
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else if items.indices.contains(parent.selection) {
                    choose(parent.selection)
                } else {
                    parent.send()
                }
                return true
            case #selector(NSResponder.insertTab(_:)):
                if items.indices.contains(parent.selection) { choose(parent.selection) } else { textView.window?.selectNextKeyView(nil) }
                return true
            // Held arrows repeat, so the whole list can be walked through.
            case #selector(NSResponder.moveUp(_:)):
                guard !items.isEmpty else { return false }
                parent.selection = max(parent.selection - 1, 0)
                return true
            case #selector(NSResponder.moveDown(_:)):
                guard !items.isEmpty else { return false }
                parent.selection = min(parent.selection + 1, items.count - 1)
                return true
            // Escape; with no list it does nothing rather than open the system's word completion.
            case #selector(NSResponder.cancelOperation(_:)), #selector(NSTextView.complete(_:)):
                if !items.isEmpty { parent.dismissed = parent.text }
                return true
            default:
                return false
            }
        }

        func choose(_ i: Int) {
            guard parent.items.indices.contains(i) else { return }
            let c = parent.items[i]
            switch c.kind {
            case .command, .skill:
                parent.text = "/\(c.name) "
            case .file:
                guard let q = parent.query, let path = RelPath(c.id) else { return }
                let token = NSMutableAttributedString(string: c.name, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .typoMention: path,
                ])
                token.append(NSAttributedString(string: " ", attributes: Self.base))
                guard textView.shouldChangeText(in: q.range, replacementString: token.string) else { return }
                textView.textStorage?.replaceCharacters(in: q.range, with: token)
                textView.didChangeText()
                textView.setSelectedRange(NSRange(location: q.range.location + token.length, length: 0))
                textView.typingAttributes = Self.base
            }
        }

        // MARK: Completion panel

        /// Shows the completions under the start of what they complete (above it when the screen ends below).
        func updatePopup() {
            let items = parent.items
            guard !items.isEmpty, let window = textView.window, window.firstResponder === textView else { return hidePopup() }
            let list = AssistantCompletionList(items: items, selected: min(parent.selection, items.count - 1)) { [weak self] in self?.choose($0) }
            let panel = self.panel ?? makePanel()
            host?.rootView = list
            let anchor = parent.query?.range.location ?? 0
            let caret = textView.firstRect(forCharacterRange: NSRange(location: anchor, length: 0), actualRange: nil)
            let size = NSSize(width: 240, height: CGFloat(min(items.count, 9)) * 22 + 10)
            var origin = NSPoint(x: caret.minX - 10, y: caret.minY - 4 - size.height)
            if let screen = window.screen, origin.y < screen.visibleFrame.minY { origin.y = caret.maxY + 4 }
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
            panel.invalidateShadow()
        }

        func hidePopup() {
            guard let panel, panel.isVisible || panel.parent != nil else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            // A hidden panel kept showing its old rows when it came back; a new one starts fresh.
            self.panel = nil
            host = nil
        }

        private func makePanel() -> NSPanel {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.becomesKeyOnlyIfNeeded = true
            let blur = NSVisualEffectView()
            blur.material = .menu
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.maskImage = Self.roundedMask(12)
            let host = CompletionHost(rootView: AssistantCompletionList(items: [], selected: 0) { _ in })
            host.translatesAutoresizingMaskIntoConstraints = false
            blur.addSubview(host)
            NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: blur.leadingAnchor), host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                                         host.topAnchor.constraint(equalTo: blur.topAnchor), host.bottomAnchor.constraint(equalTo: blur.bottomAnchor)])
            panel.contentView = blur
            self.panel = panel
            self.host = host
            return panel
        }

        private static func roundedMask(_ r: CGFloat) -> NSImage {
            let image = NSImage(size: NSSize(width: 2 * r + 1, height: 2 * r + 1), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
                return true
            }
            image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
            image.resizingMode = .stretch
            return image
        }
    }
}

/// The prompt's text view: a mention token deletes as a whole, and pasted text arrives plain.
final class PromptTextView: NSTextView {
    var resigned: () -> Void = {}

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    override func deleteBackward(_ sender: Any?) {
        selectToken(at: selectedRange().location - 1)
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        selectToken(at: selectedRange().location)
        super.deleteForward(sender)
    }

    /// Selects the mention token holding character `i`, when the caret is an insertion point next to it.
    private func selectToken(at i: Int) {
        guard selectedRange().length == 0, !hasMarkedText(), let storage = textStorage, i >= 0, i < storage.length else { return }
        var r = NSRange()
        if storage.attribute(.typoMention, at: i, longestEffectiveRange: &r, in: NSRange(location: 0, length: storage.length)) != nil {
            setSelectedRange(r)
        }
    }

    override func resignFirstResponder() -> Bool {
        let done = super.resignFirstResponder()
        if done { resigned() }
        return done
    }
}

/// Clicks reach the completion list although its panel never becomes key.
final class CompletionHost: NSHostingView<AssistantCompletionList> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Xcode's completion popup: an icon and the name per row, the selected row on a white rounded highlight.
struct AssistantCompletionList: View {
    let items: [AssistantPromptField.Completion]
    let selected: Int
    let choose: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                        HStack(spacing: 6) {
                            icon(c).frame(width: 16)
                            Text(c.name).foregroundStyle(i == selected ? .primary : .secondary).lineLimit(1).truncationMode(.middle).layoutPriority(1)
                            if let d = c.detail { Text(d).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1) }
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(i == selected ? Color(nsColor: .textBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { choose(i) }
                        .help(c.help)
                        .accessibilityAddTraits(.isButton)
                    }
                }
                .padding(5)
            }
            .scrollIndicators(.visible)
            // No animation: held arrows would otherwise outrun the scrolling.
            // Scrolls by the rows' own ids: a second `.id(index)` on the rows froze the list when it was filtered.
            .onChange(of: selected) { _, i in if items.indices.contains(i) { proxy.scrollTo(items[i].id) } }
        }
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
    }

    @ViewBuilder private func icon(_ c: AssistantPromptField.Completion) -> some View {
        switch c.kind {
        case .command: Image(systemName: "gearshape").foregroundStyle(.secondary)
        case .skill: Image(systemName: "rosette").foregroundStyle(.secondary)
        case .file: AssistantFileIcon(path: c.id)
        }
    }
}
