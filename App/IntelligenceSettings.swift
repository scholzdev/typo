import SwiftUI
import TypoKit
import TypoACP
import TypoAssistant
import TypoMCP
import TypstEngine

/// Settings › Intelligence, laid out like Xcode's: agents, model providers, the defaults for new conversations,
/// what agents may do in Typo, and the MCP server. Sub-pages: a provider, Permissions, Skills and Plug-ins.
struct IntelligenceSettings: View {
    @Environment(SettingsNavigation.self) private var nav
    @State private var addingCustom = false
    @State private var addingAgent = false
    @State private var showingPrivacy = false
    private let store = AssistantProviderStore.shared
    @AppStorage(SettingsKey.assistantDefaultProvider) private var defaultProvider = ""
    @AppStorage(SettingsKey.assistantDefaultModel) private var defaultModel = ""

    /// The fixed sub-pages; any other page id is a provider's UUID.
    enum Page: String { case permissions, skills, plugins }

    var body: some View {
        let page = nav.page?.tab == .intelligence ? nav.page : nil
        switch page.flatMap({ Page(rawValue: $0.id) }) {
        case .permissions: AgentPermissionsSettings()
        case .skills: SkillsSettings()
        case .plugins: PluginsSettings()
        case nil:
            if let id = page.flatMap({ UUID(uuidString: $0.id) }), let p = store.provider(id) {
                ProviderSettings(provider: p) { nav.page = nil }
            } else {
                list
            }
        }
    }

    private var list: some View {
        Form {
            SettingsHeaderCard(symbol: "sparkles", fill: AnyShapeStyle(LinearGradient(colors: [.orange, .pink, .purple, .blue], startPoint: .bottomLeading, endPoint: .topTrailing)),
                               title: "Intelligence",
                               text: "Chat about your project and let agents work on it, with the model of your choice. Third-party models and agents get access to your project's files.",
                               link: ("About Intelligence in Typo & Privacy…", { showingPrivacy = true }))
            Section {
                // Only Claude is offered for now; agents of other presets the user set up earlier stay listed.
                ForEach(AssistantPreset.agents.filter { $0.id == "acp-claude" }) { preset in
                    let set = store.configured.filter { $0.presetID == preset.id }
                    if set.isEmpty {
                        HStack(spacing: 10) {
                            ProviderIcon(presetID: preset.id)
                            titled(preset.shortName, preset.organization)
                            Spacer()
                            Button("Get") { add(AssistantProvider(preset: preset)) }
                                .buttonBorderShape(.capsule)
                                .accessibilityLabel("Get \(preset.shortName)")
                        }
                    }
                    ForEach(set) { p in agentRow(p) }
                }
                ForEach(store.configured.filter { $0.isAgent && $0.presetID != "acp-claude" }) { p in agentRow(p) }
            } header: {
                Text("Agents")
            } footer: {
                HStack { Spacer(); Button("Add an Agent…") { addingAgent = true } }
            }
            Section {
                ForEach(store.providers.filter { !$0.isAgent }) { p in
                    if p.isOnDevice {
                        row(p)
                    } else {
                        Button { open(p) } label: { row(p).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .contextMenu { Button("Delete", role: .destructive) { store.remove(p.id) } }
                    }
                }
            } header: {
                Text("Model Providers")
            } footer: {
                HStack {
                    Spacer()
                    Menu("Add a Provider…") {
                        ForEach(AssistantPreset.all) { preset in
                            Button("\(preset.name) (\(preset.organization))") { add(AssistantProvider(preset: preset)) }
                        }
                    }
                    .fixedSize()
                    Button("Add a Model Provider…") { addingCustom = true }
                }
            }
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
            Section("Agents in Typo") {
                SettingsPageRow(title: "Permissions", subtitle: "Control what the assistant and agents may do in your projects.") { go(.permissions, "Permissions") }
                SettingsPageRow(title: "Skills", subtitle: "Typo's skills and your own, written in plain words.") { go(.skills, "Skills") }
                SettingsPageRow(title: "Plug-ins", subtitle: "Add and manage plug-ins that bring skills to agents.") { go(.plugins, "Plug-ins") }
            }
            MCPServerSection()
        }
        .pane()
        .sheet(isPresented: $addingCustom) { AddModelProviderSheet { add($0) } }
        .sheet(isPresented: $addingAgent) { AddAgentSheet { add($0) } }
        .sheet(isPresented: $showingPrivacy) { IntelligencePrivacySheet() }
        .onAppear { store.refreshAvailability() }
    }

    private func go(_ page: Page, _ title: String) {
        nav.page = SettingsSubpage(tab: .intelligence, id: page.rawValue, title: title)
    }

    private func add(_ p: AssistantProvider) {
        store.add(p)
        open(p)
    }

    private func open(_ p: AssistantProvider) {
        nav.page = SettingsSubpage(tab: .intelligence, id: p.id.uuidString, title: p.shortName)
    }

    private func titled(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func agentRow(_ p: AssistantProvider) -> some View {
        Button { open(p) } label: {
            HStack(spacing: 10) {
                ProviderIcon(presetID: p.presetID)
                titled(p.shortName, p.organization)
                Spacer()
                if !store.isReady(p) { Text(store.status(p)).foregroundStyle(.orange) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { Button("Remove", role: .destructive) { store.remove(p.id) } }
    }

    private func row(_ p: AssistantProvider) -> some View {
        let ready = store.isReady(p)
        return HStack(spacing: 10) {
            ProviderIcon(presetID: p.presetID)
            titled(p.name, p.organization)
            Spacer()
            Text(store.status(p)).foregroundStyle(ready ? Color.secondary : .orange)
            if !p.isOnDevice { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary) }
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
        Section("Model Context Protocol") {
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
    @State private var showingPrivacy = false
    @State private var showingLogin = false

    private var preset: AssistantPreset { provider.preset }
    private var baseURLEditable: Bool { preset.baseURL == nil }

    var body: some View {
        Form {
            if provider.isAgent {
                agent
            } else {
                model
                Section {
                    Button("Delete Provider…", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .pane()
        .onChange(of: provider) { store.update(provider) }
        .onChange(of: provider.name) { nav.page?.title = provider.shortName }
        .confirmationDialog("Remove \(provider.shortName)?", isPresented: $confirmDelete) {
            Button("Remove", role: .destructive) { store.remove(provider.id); deleted() }
        } message: {
            Text(provider.isAgent ? "Its command is removed. The agent itself stays installed." : "Its API key is removed from the Keychain.")
        }
        .sheet(isPresented: $showingPrivacy) { IntelligencePrivacySheet() }
        .alert("Sign In to \(provider.shortName)", isPresented: $showingLogin) {
            Button("OK") {}
        } message: {
            Text(preset.loginHint ?? "")
        }
        // The Account text's last link opens the privacy sheet; the others go to the browser.
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "typo-settings" { showingPrivacy = true; return .handled }
            return .systemAction
        })
    }

    /// An agent, as in Xcode: its card, its model, its account, and the command that starts it.
    @ViewBuilder private var agent: some View {
        Section {
            HStack(spacing: 10) {
                ProviderIcon(presetID: provider.presetID)
                Text(provider.shortName)
            }
            .padding(.vertical, 2)
        }
        Section {
            LabeledContent("Model") { Text("Chosen in each conversation").foregroundStyle(.secondary) }
        }
        Section {
            LabeledContent("Account") {
                HStack(spacing: 10) {
                    Text(found?.ok == true ? "Configured" : "Not Configured").foregroundStyle(.secondary)
                    Menu {
                        if preset.loginHint != nil { Button("How to Sign In…") { showingLogin = true } }
                        Button("Test Agent") { run(testAgent) }.disabled(busy)
                        Divider()
                        Button("Remove Agent…", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Account Options")
                }
            }
            Text(accountNote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if busy || result != nil {
                HStack {
                    if busy { ProgressView().controlSize(.small); Text("Testing…").foregroundStyle(.secondary) }
                    if let result, !busy { Text(result.text).foregroundStyle(result.ok ? Color.secondary : .red).textSelection(.enabled) }
                }
            }
        }
        Section {
            if preset.command?.isEmpty == true { TextField("Name", text: $provider.name) }
            TextField("Command", text: Binding(get: { provider.command ?? "" }, set: { provider.command = $0 }), prompt: Text("agent --acp"))
                .font(.body.monospaced())
            if let found { Text(found.text).font(.callout).foregroundStyle(found.ok ? Color.secondary : .orange) }
        } header: {
            Text("Command")
        } footer: {
            Text(preset.caption + " Test Agent starts the agent once and stops it again.").font(.callout).foregroundStyle(.secondary)
        }
        .task(id: provider.command) { found = await Self.lookup(provider.command ?? "") }
    }

    /// Where the agent's requests go, with its vendor's policies where Typo knows them.
    private var accountNote: AttributedString {
        var text = "Sign in with the agent's own command line tool; Typo never sees your login."
        if let links = VendorPolicy.links(provider.organization) {
            text += " Your requests go to \(provider.organization) and are subject to its [Privacy Policy](\(links.privacy)) and [Terms of Use](\(links.terms))."
        } else {
            text += " Your requests go to the agent's own provider, under its terms."
        }
        text += " Typo sends no usage data. [About Intelligence in Typo & Privacy…](typo-settings:privacy)"
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
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
