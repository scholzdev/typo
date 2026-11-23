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
            } else {
                transcript
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 8) {
                            if let latest = model.latestChanges { changesBar(latest) }
                            AssistantPromptBox(model: model)
                        }
                        .frame(maxWidth: Self.column)
                        .padding(.horizontal, 20).padding(.bottom, 14)
                        .frame(maxWidth: .infinity)
                    }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// "✦ › Title", with the conversation's permissions and New Conversation at the right.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            Text(model.current?.title ?? "New Conversation").font(.system(size: 12)).lineLimit(1)
            Spacer()
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
                        AssistantTurnView(model: model, turn: t, header: Self.header(t, after: i > 0 ? turns[i - 1] : nil)).id(t.id)
                    }
                    if let notice = model.notice {
                        Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if let pending = model.pendingConsent { consent(pending) }
                    if let pending = model.pendingSearch { search(pending) }
                    if let pending = model.shownTool { tool(pending) }
                    if let pending = model.shownPermission { permission(pending) }
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

    /// "1 Change in 1 File" with the list and Revert, for the latest answer.
    private func changesBar(_ m: AssistantMessage) -> some View {
        let changes = model.appliedChanges(m)
        let blocked = changes.compactMap { model.revertBlocker(m, $0.index) }
        return AssistantChangesBar(
            entries: changes.map { .init(id: $0.index, path: $0.edit.path, preview: $0.edit.replace.split(whereSeparator: \.isNewline).first.map(String.init) ?? "") },
            revertBlocker: blocked.count == changes.count ? blocked.first : nil,
            open: { i in Task { await model.showInEditor(m, i) } },
            revert: { Task { await model.revertAll(m) } })
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

    /// Asked when an agent wants to run a tool; the buttons are the agent's own options.
    private func permission(_ p: AssistantModel.PendingPermission) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(p.call.title.isEmpty ? "May the agent continue?" : p.call.title, systemImage: "terminal").font(.headline)
            ForEach(Array(p.call.diffs.enumerated()), id: \.offset) { _, d in
                let path = ACPFiles.projectPath(d.path, root: model.project.rootURL)?.raw ?? d.path
                AssistantChangeCard(edit: ProposedEdit(path: path, search: d.search, replace: d.replace), status: .pending, showsButtons: false)
            }
            HStack {
                Spacer()
                ForEach(p.options) { o in
                    if o.kind == "allow_once" {
                        Button(o.name) { model.answerPermission(o.id) }.keyboardShortcut(.defaultAction)
                    } else {
                        Button(o.name) { model.answerPermission(o.id) }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
            }
            ForEach(message.toolCalls ?? []) { AssistantToolRow(exchange: $0) }
            let permissions = model.permissions
            let segments = AssistantEdits.segments(message.text)
            let files = Set(model.project.allFiles.map(\.raw))
            ForEach(Array(segments.enumerated()), id: \.offset) { i, s in
                switch s {
                case .text(let t): AssistantMarkdown(text: t, files: files) { model.openFile($0) }
                case .edit(let e):
                    // The edit's index among the message's edits, which is what `edits` (accepted/rejected) is keyed by.
                    let index = segments[..<i].count { if case .edit = $0 { true } else { false } }
                    // Applied changes show as the turn's file capsules and in the diff panel.
                    if message.edits[index] != .accepted, permissions.shows(e) || message.edits[index] != nil {
                        AssistantEditCard(model: model, message: message, index: index, edit: e)
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
    @FocusState private var focused: Bool
    @State private var commandIndex = 0
    @State private var picksFiles = false
    @State private var showsModes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.current == nil { suggestions }
            VStack(alignment: .leading, spacing: 8) {
                if !model.attachments.isEmpty || !model.externalAttachments.isEmpty, model.provider?.isOnDevice != true { attachmentChips }
                if !commandMatches.isEmpty { commandList }
                TextField(placeholder, text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...10)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
                        } else if commandMatches.indices.contains(commandIndex) {
                            useCommand(commandMatches[commandIndex])
                        } else {
                            model.send()
                        }
                        return .handled
                    }
                    // Held arrows repeat, so the whole list can be walked through.
                    .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in
                        guard !commandMatches.isEmpty else { return .ignored }
                        commandIndex = max(commandIndex - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in
                        guard !commandMatches.isEmpty else { return .ignored }
                        commandIndex = min(commandIndex + 1, commandMatches.count - 1)
                        return .handled
                    }
                    .onChange(of: model.draft) { commandIndex = 0 }
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
            .onTapGesture { focused = true }
        }
        .onAppear { focused = true }
        .onChange(of: model.currentID) { focused = true }
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
                ForEach(model.attachments, id: \.self) { f in
                    chip(name: (f.raw as NSString).lastPathComponent, help: f.raw) { model.attachments.removeAll { $0 == f } }
                }
                ForEach(model.externalAttachments, id: \.self) { u in
                    chip(name: u.lastPathComponent, help: u.path) { model.externalAttachments.removeAll { $0 == u } }
                }
            }
        }
    }

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

    private var commandList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(commandMatches.enumerated()), id: \.element.id) { i, c in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            // No fixedSize: a row wider than the box cut the whole column off on the left.
                            Text("/" + c.name).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle).layoutPriority(2)
                            if let h = c.hint { Text("‹\(h)›").font(.caption).foregroundStyle(.tertiary).lineLimit(1).layoutPriority(1) }
                            Text(c.description).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(i == commandIndex ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { useCommand(c) }
                        .accessibilityAddTraits(.isButton)
                        .id(i)
                    }
                }
            }
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            // No animation: held arrows would otherwise outrun the scrolling.
            .onChange(of: commandIndex) { _, i in proxy.scrollTo(i) }
        }
    }

    private func useCommand(_ c: ACPCommand) { model.draft = "/\(c.name) " }

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
