import SwiftUI
import TypoKit
import TypoACP
import TypoAssistant
import TypoMCP
import TypstEngine

/// Settings › Intelligence: the model providers and the defaults for new conversations.
struct IntelligenceSettings: View {
    @Environment(SettingsNavigation.self) private var nav
    @State private var addingCustom = false
    private let store = AssistantProviderStore.shared
    @AppStorage(SettingsKey.assistantDefaultProvider) private var defaultProvider = ""
    @AppStorage(SettingsKey.assistantDefaultModel) private var defaultModel = ""

    var body: some View {
        if nav.page?.tab == .intelligence, let id = nav.page.flatMap({ UUID(uuidString: $0.id) }), let p = store.provider(id) {
            ProviderSettings(provider: p) { nav.page = nil }
        } else {
            list
        }
    }

    private var list: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.purple.gradient, in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Assistant").font(.headline)
                        Text("Chat about your project and review the changes it proposes before they are applied.")
                        Text("Model providers receive the files you attach to a conversation.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Providers") {
                ForEach(store.providers) { p in
                    if p.isOnDevice {
                        row(p)
                    } else {
                        Button { open(p) } label: { row(p).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Delete", role: .destructive) { store.remove(p.id) } }
                    }
                }
                HStack {
                    Menu("Add a Provider…") {
                        ForEach(AssistantPreset.all) { preset in
                            Button("\(preset.name) (\(preset.organization))") { add(AssistantProvider(preset: preset)) }
                        }
                        Section("Agents (ACP)") {
                            ForEach(AssistantPreset.agents) { preset in
                                Button(preset.command?.isEmpty == true ? "\(preset.name)…" : "\(preset.name) (\(preset.organization))") { add(AssistantProvider(preset: preset)) }
                            }
                        }
                    }
                    .fixedSize()
                    Button("Add a Model Provider…") { addingCustom = true }
                }
            }
            AssistantPermissionsSection()
            Section("Chat") {
                Picker("Default provider", selection: $defaultProvider) {
                    Text("Automatic").tag("")
                    ForEach(store.providers) { p in Text(p.name).tag(p.id.uuidString) }
                }
                if let p = store.provider(UUID(uuidString: defaultProvider)), !p.isOnDevice, !p.isAgent {
                    LabeledContent("Default model") {
                        TextField("Default model", text: $defaultModel, prompt: Text(p.model)).labelsHidden().multilineTextAlignment(.trailing)
                    }
                }
                Text("Used for new conversations. Automatic picks the first ready provider, else the on-device model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            MCPServerSection()
        }
        .pane()
        .sheet(isPresented: $addingCustom) { AddModelProviderSheet { add($0) } }
        .onAppear { store.refreshAvailability() }
    }

    private func add(_ p: AssistantProvider) {
        store.add(p)
        open(p)
    }

    private func open(_ p: AssistantProvider) {
        nav.page = SettingsSubpage(tab: .intelligence, id: p.id.uuidString, title: p.name)
    }

    private func row(_ p: AssistantProvider) -> some View {
        let ready = store.isReady(p)
        return HStack(spacing: 10) {
            Image(systemName: p.isOnDevice ? "apple.intelligence" : p.preset.symbol)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(p.isOnDevice ? Color.purple : p.preset.isLocal ? .green : .blue, in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name)
                Text(p.organization).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.status(p)).font(.callout).foregroundStyle(ready ? Color.secondary : .orange)
        }
    }
}

/// typo-mcp, the app's Typst tools for agents outside Typo, and registering it with Claude Code and Claude Desktop.
private struct MCPServerSection: View {
    private let path = Bundle.main.path(forAuxiliaryExecutable: "typo-mcp")
    @State private var inCode = false
    @State private var inDesktop = false
    @State private var busy = false
    @State private var result: (ok: Bool, text: String)?

    var body: some View {
        Section("MCP Server") {
            Text("Gives AI agents Typo's Typst tools: compile errors, page previews, Typst docs, packages and fonts.")
            if let path {
                LabeledContent("Command") {
                    Text(path).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                }
                HStack {
                    Button("Copy Command") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(path, forType: .string) }
                    Spacer()
                    Button(inCode ? "Added to Claude Code" : "Add to Claude Code") { Task { await addToCode(path) } }.disabled(inCode || busy)
                    Button(inDesktop ? "Added to Claude Desktop" : "Add to Claude Desktop") { addToDesktop(path) }.disabled(inDesktop)
                }
                if let result {
                    Text(result.text).font(.caption).foregroundStyle(result.ok ? Color.secondary : .red).textSelection(.enabled)
                }
            } else {
                Text("This build of Typo has no typo-mcp.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            guard path != nil else { return }
            inDesktop = MCPInstall.isAdded(try? Data(contentsOf: MCPInstall.desktopConfig))
            inCode = await Task.detached { ACPProcess.claude(["mcp", "get", "typo"])?.ok == true }.value
        }
    }

    private func addToCode(_ path: String) async {
        busy = true
        defer { busy = false }
        guard let r = await Task.detached(operation: { ACPProcess.claude(["mcp", "add", "--scope", "user", "typo", "--", path]) }).value else {
            result = (false, "Claude Code was not found. Install it, or add the command above to it yourself.")
            return
        }
        inCode = r.ok
        result = r.ok ? (true, "Added to Claude Code for all your projects.") : (false, r.text.isEmpty ? "claude mcp add failed." : r.text)
    }

    private func addToDesktop(_ path: String) {
        result = MCPInstall.addToDesktop(command: path)
        inDesktop = result?.ok == true
    }
}

/// One provider's page: key, base URL, model, and a connection test.
private struct ProviderSettings: View {
    @State var provider: AssistantProvider
    let deleted: () -> Void
    @Environment(SettingsNavigation.self) private var nav
    private let store = AssistantProviderStore.shared
    @State private var key = ""
    @State private var keyError: String?
    @State private var models: [String] = []
    @State private var busy = false
    @State private var result: (ok: Bool, text: String)?
    @State private var confirmDelete = false
    @State private var found: (ok: Bool, text: String)?

    private var preset: AssistantPreset { provider.preset }
    private var baseURLEditable: Bool { preset.baseURL == nil }

    var body: some View {
        Form {
            if provider.isAgent { agent } else { model }
            Section {
                Button("Delete Provider…", role: .destructive) { confirmDelete = true }
            }
        }
        .pane()
        .onChange(of: provider) { store.update(provider) }
        .onChange(of: provider.name) { nav.page?.title = provider.name }
        .confirmationDialog("Delete \(provider.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.remove(provider.id); deleted() }
        } message: {
            Text(provider.isAgent ? "Its command is removed." : "Its API key is removed from the Keychain.")
        }
    }

    /// An agent: the command that starts it, whether that command is found, and a test that starts it once.
    @ViewBuilder private var agent: some View {
        Section {
            Text(preset.caption).font(.caption).foregroundStyle(.secondary)
            if preset.command?.isEmpty == true { TextField("Description", text: $provider.name) }
            TextField("Command", text: Binding(get: { provider.command ?? "" }, set: { provider.command = $0 }), prompt: Text("agent --acp"))
                .font(.body.monospaced())
            if let found { Text(found.text).font(.caption).foregroundStyle(found.ok ? Color.secondary : .orange) }
            if let hint = preset.loginHint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: provider.command) { found = await Self.lookup(provider.command ?? "") }
        Section {
            HStack {
                Button("Test Agent") { run(testAgent) }
                if busy { ProgressView().controlSize(.small) }
            }
            .disabled(busy)
            if let result {
                Text(result.text).font(.caption).foregroundStyle(result.ok ? Color.secondary : .red).textSelection(.enabled)
            }
            Text("Test Agent starts the agent and stops it again. The agent works in the project folder and sends what it reads to its own provider.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Whether the command's program is on the user's PATH.
    private static func lookup(_ command: String) async -> (ok: Bool, text: String)? {
        guard let name = ACPProcess.words(command).first else { return nil }
        let path = await Task.detached { ACPProcess.userPATH() }.value
        if let found = ACPProcess.locate(name, path: path) { return (true, "Found \(found).") }
        return (false, name == "npx" ? "npx was not found. Install Node.js, which brings npx." : "\(name) was not found. Install it, or enter its full path.")
    }

    /// Starts the agent in the home folder, opens a session and stops it.
    private func testAgent() async throws -> String {
        do {
            let (agent, info) = try await ACPAgent.launch(command: provider.command ?? "", cwd: FileManager.default.homeDirectoryForCurrentUser, host: nil)
            agent.close()
            return "Connected to \(info)."
        } catch {
            throw ACPClient.failure(error, preset: preset)
        }
    }

    @ViewBuilder private var model: some View {
        Section {
            Text(preset.caption).font(.caption).foregroundStyle(.secondary)
            if preset.id == AssistantPreset.customInternet.id || preset.id == AssistantPreset.customLocal.id {
                TextField("Description", text: $provider.name)
            }
            if baseURLEditable {
                TextField("Base URL", text: $provider.baseURL, prompt: Text("https://…/v1"))
            } else {
                LabeledContent("Base URL", value: provider.baseURL)
            }
        }
        if !preset.isLocal || preset.id == AssistantPreset.customLocal.id {
            Section("API Key") {
                HStack {
                    SecureField(store.keyed.contains(provider.id) ? "Stored in the Keychain" : "API key", text: $key)
                        .accessibilityLabel("API key")
                    Button("Save") {
                        do { try store.setKey(key, for: provider); key = ""; keyError = nil } catch { keyError = (error as? AssistantError)?.message ?? error.localizedDescription }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Remove Key") { store.removeKey(for: provider) }.disabled(!store.keyed.contains(provider.id))
                }
                if preset.id == AssistantPreset.customInternet.id {
                    TextField("API Key Header", text: $provider.keyHeader)
                    Text("Authorization sends “Bearer <key>”; any other header sends the key as it is.").font(.caption).foregroundStyle(.secondary)
                }
                if let keyError { Text(keyError).font(.caption).foregroundStyle(.red) }
                Text(preset.needsKey ? "The key is kept in your Keychain only." : "Optional. The key is kept in your Keychain only.").font(.caption).foregroundStyle(.secondary)
            }
        }
        Section("Model") {
            let choices = Array(Set(models + preset.models + [provider.model]).filter { !$0.isEmpty }).sorted()
            if preset.modelsPath != nil && !choices.isEmpty {
                Picker("Default model", selection: $provider.model) {
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                }
            }
            TextField("Model id", text: $provider.model, prompt: Text("Type the model id"))
            HStack {
                if preset.modelsPath != nil {
                    Button("Refresh Models") { run { let list = try await store.client(for: provider).models(); models = list; return "\(list.count) models available." } }
                }
                Button("Test Connection") { run(test) }
                if busy { ProgressView().controlSize(.small) }
            }
            .disabled(busy)
            if let result {
                Text(result.text).font(.caption).foregroundStyle(result.ok ? Color.secondary : .red).textSelection(.enabled)
            }
            Text("Refresh Models and Test Connection contact the provider; nothing else is sent until you send a message.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Lists the models where possible, else asks for a one-word answer.
    private func test() async throws -> String {
        let client = store.client(for: provider)
        if preset.modelsPath != nil { return "Connected. \(try await client.models().count) models available." }
        var reply = ""
        for try await e in client.stream(AssistantRequest(model: provider.model, system: "Reply with the single word OK.", files: nil, messages: [.init(role: .user, text: "Test")])) {
            if case .text(let t) = e { reply += t }
        }
        return "Connected. The model answered “\(reply.prefix(40))”."
    }

    private func run(_ work: @escaping @MainActor () async throws -> String) {
        busy = true
        result = nil
        Task {
            do { result = (true, try await work()) } catch {
                result = (false, (error as? AssistantError)?.message ?? error.localizedDescription)
            }
            busy = false
        }
    }
}

/// "Add a Model Provider…": a custom server on the internet or on this Mac.
private struct AddModelProviderSheet: View {
    let add: (AssistantProvider) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var local = false
    @State private var url = ""
    @State private var key = ""
    @State private var header = "Authorization"
    @State private var description = ""
    @State private var port = 8080
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Location", selection: $local) {
                Text("Internet Hosted").tag(false)
                Text("Locally Hosted").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().padding()
            Form {
                if local {
                    TextField("Port", value: $port, format: .number.grouping(.never))
                    TextField("Description", text: $description, prompt: Text("My Model Server"))
                } else {
                    TextField("URL", text: $url, prompt: Text("https://example.com/v1"))
                    SecureField("API Key", text: $key, prompt: Text("Optional"))
                    TextField("API Key Header", text: $header)
                    TextField("Description", text: $description, prompt: Text("My Model Server"))
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { save() }.keyboardShortcut(.defaultAction).disabled(local ? !(1...65535).contains(port) : URL(string: url)?.scheme == nil)
            }
            .padding()
        }
        .frame(width: 440)
    }

    private func save() {
        let name = description.trimmingCharacters(in: .whitespaces)
        let p = local ? AssistantProvider.local(port: port, description: name.isEmpty ? "Local Model (\(port))" : name)
            : AssistantProvider(preset: .customInternet, name: name.isEmpty ? (URL(string: url)?.host() ?? url) : name, baseURL: url, keyHeader: header)
        if !local, !key.isEmpty {
            do { try AssistantProviderStore.shared.setKey(key, for: p) } catch { self.error = (error as? AssistantError)?.message ?? error.localizedDescription; return }
        }
        add(p)
        dismiss()
    }
}
