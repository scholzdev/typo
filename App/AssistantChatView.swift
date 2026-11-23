import AppKit
import SwiftUI
import TypoKit
import ACPProtocol
import TypoACP
import TypoAssistant
import TypstEngine

/// The editor column in assistant mode: the transcript over Xcode-style prompt box.
struct AssistantChatView: View {
    @Bindable var model: AssistantModel
    private let providers = AssistantProviderStore.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
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
            VStack(spacing: 0) {
                transcript
                if let latest = model.latestChanges { changesBar(latest) }
                AssistantPromptBox(model: model)
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(model.current?.messages ?? []) { m in
                        AssistantMessageView(model: model, message: m).id(m.id)
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
                .padding(16)
            }
            .onChange(of: model.current?.messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.current?.messages.count) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.shownTool?.call.id) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.shownPermission?.call.id) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: model.current?.messages.last?.toolCalls?.count) { proxy.scrollTo("end", anchor: .bottom) }
            .overlay {
                if model.current == nil && model.pendingConsent == nil && model.pendingSearch == nil && model.notice == nil {
                    ContentUnavailableView("Ask About Your Document", systemImage: "sparkles",
                                           description: Text("The assistant reads the files you attach and changes them as you ask, and you can revert what it did."))
                }
            }
        }
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

struct AssistantMessageView: View {
    let model: AssistantModel
    let message: AssistantMessage

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        } else {
            answer
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = message.reasoning, !r.isEmpty {
                DisclosureGroup("Reasoning") {
                    Text(r).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            let permissions = model.permissions
            let segments = AssistantEdits.segments(message.text)
            ForEach(Array(segments.enumerated()), id: \.offset) { i, s in
                switch s {
                case .text(let t): AssistantMarkdown(text: t)
                case .edit(let e):
                    // The edit's index among the message's edits, which is what `edits` (accepted/rejected) is keyed by.
                    let index = segments[..<i].count { if case .edit = $0 { true } else { false } }
                    if permissions.shows(e) || message.edits[index] != nil { AssistantEditCard(model: model, message: message, index: index, edit: e) }
                }
            }
            ForEach(message.toolCalls ?? []) { AssistantToolRow(exchange: $0) }
            if model.streamingID == message.id {
                ProgressView().controlSize(.small)
            }
            if message.truncated {
                Text("The answer reached the length limit and may be incomplete.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = message.error {
                HStack(alignment: .firstTextBaseline) {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    Button("Retry") { model.retry(message) }.disabled(model.isStreaming)
                }
            }
            if model.pendingEdits(message).count > 1, model.streamingID != message.id {
                Button("Accept All") { Task { await model.acceptAll(message) } }
                    .help("Applies every pending change of this answer, one after another")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One tool call as a compact row ("Read kapitel.typ"); it expands to what the tool returned.
struct AssistantToolRow: View {
    let exchange: ToolExchange

    var body: some View {
        DisclosureGroup {
            ScrollView {
                Text(exchange.result ?? "Waiting for the result…")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(maxHeight: 160)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: exchange.isError ? "exclamationmark.triangle" : "wrench.and.screwdriver")
                Text(exchange.title).lineLimit(1).truncationMode(.middle)
                if exchange.result == nil { ProgressView().controlSize(.mini) }
            }
            .font(.callout)
            .foregroundStyle(exchange.isError ? .orange : .secondary)
        }
    }
}

/// Markdown prose with fenced code blocks in the editor's font.
struct AssistantMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, b in
                if b.code {
                    Text(b.text)
                        .font(Font(Highlighter.baseFont))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text((try? AttributedString(markdown: b.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(b.text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Alternating prose and ``` code blocks; an unclosed fence (still streaming) is code to the end.
    static func blocks(_ text: String) -> [(code: Bool, text: String)] {
        var out: [(code: Bool, text: String)] = [], lines: [String] = [], code = false
        func flush() {
            let t = lines.joined(separator: "\n")
            if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append((code, code ? t : t.trimmingCharacters(in: .newlines))) }
            lines = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { flush(); code.toggle() } else { lines.append(line) }
        }
        flush()
        return out
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

/// The prompt at the bottom, like Xcode's: attachments, the field, the provider and model, and send.
struct AssistantPromptBox: View {
    @Bindable var model: AssistantModel
    private let providers = AssistantProviderStore.shared
    @FocusState private var focused: Bool
    @State private var commandIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.current == nil { suggestions }
            VStack(alignment: .leading, spacing: 6) {
                if !model.attachments.isEmpty && model.provider?.isOnDevice != true {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(model.attachments, id: \.self) { f in
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.text")
                                    Text((f.raw as NSString).lastPathComponent)
                                    Button { model.attachments.removeAll { $0 == f } } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.plain).foregroundStyle(.secondary)
                                        .accessibilityLabel("Detach \(f.raw)")
                                }
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                                .help(f.raw)
                            }
                        }
                    }
                }
                if !commandMatches.isEmpty { commandList }
                TextField("Ask about your document…", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
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
                HStack(spacing: 10) {
                    if model.provider?.isOnDevice != true { attachMenu }
                    providerMenu
                    // Dropped when the row is too narrow; wrapped it stood one letter per line and widened the sidebar's content.
                    ViewThatFits(in: .horizontal) {
                        Text({ switch model.permissions.policy(.changeFiles) { case .never: "Edits are off"; case .ask: model.provider?.isAgent == true ? "The agent asks before edits" : "Edits need approval"; case .allow: "Edits apply right away" } }())
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Color.clear.frame(width: 0, height: 0)
                    }
                    Spacer()
                    if model.isStreaming {
                        Button { model.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                            .buttonStyle(.plain).accessibilityLabel("Stop").help("Stop the answer")
                    } else {
                        Button { model.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                            .buttonStyle(.plain).accessibilityLabel("Send").help("Send (Return)")
                            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(model.provider.map(providers.isReady) ?? false))
                    }
                }
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .overlay { if model.isStreaming { AssistantGlow() } }
        }
        .padding(12)
        .onAppear { focused = true }
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
                            // No fixedSize: a row wider than the sidebar cut the whole column off on the left.
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

    @ViewBuilder private var suggestions: some View {
        HStack(spacing: 8) {
            if model.hasSelection { chip("Explain the selected text") { model.send(.explain) } }
            if model.hasErrors, model.permissions.policy(.diagnostics) != .never { chip("Fix the compile errors") { model.send(.fixErrors) } }
            chip("Improve the wording of this section") { model.send(.improve) }
        }
    }

    private func chip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).disabled(model.isStreaming)
    }

    private var attachMenu: some View {
        Menu {
            ForEach(model.project.allFiles.filter { FileKind.isText($0.raw) }, id: \.self) { f in
                Toggle(f.raw, isOn: Binding(get: { model.attachments.contains(f) },
                                            set: { on in if on { model.attachments.append(f) } else { model.attachments.removeAll { $0 == f } } }))
            }
        } label: {
            Image(systemName: "paperclip")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Attach Files").help("Attach or detach project files")
    }

    private var providerMenu: some View {
        Menu {
            ForEach(providers.providers) { p in
                let models = Array(Set([providers.defaultModel(for: p), p.model] + p.preset.models).filter { !$0.isEmpty }).sorted()
                if p.isOnDevice || p.isAgent || models.count <= 1 {
                    Button(p.isOnDevice || p.isAgent ? p.name : "\(p.name) – \(models.first ?? p.model)") { model.choose(p, model: models.first ?? p.model) }
                        .disabled(!providers.isReady(p))
                } else {
                    Menu(p.name) {
                        ForEach(models, id: \.self) { m in Button(m) { model.choose(p, model: m) } }
                    }
                    .disabled(!providers.isReady(p))
                }
            }
        } label: {
            Text(model.provider.map { $0.isOnDevice || $0.isAgent ? $0.name : "\($0.name) · \(model.model)" } ?? "Choose a Model").font(.caption)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 150)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Model").help("The model provider and model of this conversation")
    }
}
