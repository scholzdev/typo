import SwiftUI
import TypoKit
import TypoAssistant

extension SettingsKey {
    /// JSON of the global `AssistantPermissions`.
    static let assistantPermissions = "assistantPermissions"
}

extension AssistantPermissions {
    /// The global defaults from Settings › Intelligence.
    static var stored: AssistantPermissions {
        get { UserDefaults.standard.data(forKey: SettingsKey.assistantPermissions).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self() }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: SettingsKey.assistantPermissions) }
    }
}

extension SettingsKey {
    static let agentCommands = "agentAllowedCommands"
    static let agentControlsFiles = "agentControlsFileAccess"
    static let agentFolders = "agentAllowedFolders"
    static let agentWebAccess = "agentWebAccess"
}

extension AgentAccess {
    /// Settings › Intelligence › Permissions, for every agent and project; plain defaults so they read as they are.
    static var stored: AgentAccess {
        get {
            let d = UserDefaults.standard
            return AgentAccess(commands: d.stringArray(forKey: SettingsKey.agentCommands) ?? [],
                               controlsFiles: d.object(forKey: SettingsKey.agentControlsFiles) as? Bool ?? true,
                               folders: d.stringArray(forKey: SettingsKey.agentFolders) ?? [],
                               web: d.string(forKey: SettingsKey.agentWebAccess).flatMap(PermissionPolicy.init) ?? .ask)
        }
        set {
            let d = UserDefaults.standard
            d.set(newValue.commands, forKey: SettingsKey.agentCommands)
            d.set(newValue.controlsFiles, forKey: SettingsKey.agentControlsFiles)
            d.set(newValue.folders, forKey: SettingsKey.agentFolders)
            d.set(newValue.web.rawValue, forKey: SettingsKey.agentWebAccess)
        }
    }
}

/// Settings › Intelligence › Permissions, as in Xcode: a card, file and folder access, the allowed commands, web access,
/// then what API providers may do by default.
struct AgentPermissionsSettings: View {
    @State private var access = AgentAccess.stored
    @State private var explains = false
    @State private var newCommand: String?
    @State private var selectedCommand: String?
    @State private var selectedFolder: String?

    var body: some View {
        Form {
            SettingsHeaderCard(symbol: "hand.raised.fill", title: "Permissions",
                               text: "Specify agent access to tools and terminal commands. These settings apply to all agents in Typo, and to all projects.")
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Control File & Folder Access")
                        Text("File & folder access will be controlled by these settings.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Control File & Folder Access", isOn: $access.controlsFiles).labelsHidden().toggleStyle(.switch)
                    Button { explains = true } label: { Image(systemName: "info.circle").font(.system(size: 16)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("About File & Folder Access")
                        .popover(isPresented: $explains, arrowEdge: .bottom) { explanation }
                }
                if access.controlsFiles, !access.folders.isEmpty {
                    rules(\.folders, selection: $selectedFolder, title: "Allowed Folders",
                          text: "Folders outside the project you always allowed. Agents may read and write files in them without asking.",
                          add: addFolder)
                }
            }
            Section {
                rules(\.commands, selection: $selectedCommand, title: "Allowed Commands",
                      text: "Commands you grant permission to in the coding assistant will appear here. You will be asked for permission for any commands not listed here.",
                      add: { newCommand = "" })
                if newCommand != nil {
                    TextField("Command", text: Binding(get: { newCommand ?? "" }, set: { newCommand = $0 }), prompt: Text("cargo check"))
                        .labelsHidden()
                        .onSubmit(addCommand)
                        .onExitCommand { newCommand = nil }
                }
            }
            Section {
                Picker(selection: $access.web) {
                    ForEach(PermissionPolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Web Access")
                    Text("When an agent fetches a web page or searches the web.")
                }
            }
            AssistantPermissionsSection()
        }
        .pane()
        .onChange(of: access) { AgentAccess.stored = access }
        // "Always Allow" in a conversation adds rules while this page is open.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
            let stored = AgentAccess.stored
            if stored != access { access = stored }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Control File & Folder Access").font(.headline)
            Text("When this is on, agents that read or write files through Typo may do so in the project folder. For a file anywhere else, Typo asks first, and an agent's request to change, move or delete files outside the project asks even when changes are allowed. Always Allow adds the folder to Allowed Folders.")
            Text("When this is off, Typo refuses files outside the project, and requests to change them follow “Change files”.")
            Text("Agents that read or run things with their own tools follow their own settings for what they don't ask about.").foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 320)
        .padding(14)
    }

    private func addCommand() {
        let c = (newCommand ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        newCommand = nil
        guard !c.isEmpty, !c.contains(where: \.isNewline), !access.commands.contains(c) else { return }
        access.commands = (access.commands + [c]).sorted()
        selectedCommand = c
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Allow"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = AgentAccess.resolve(url.path)
        if !access.folders.contains(path) { access.folders = (access.folders + [path]).sorted() }
    }

    /// A titled list as in Xcode: rows sorted alphabetically, a click selects one, + and − below.
    private func rules(_ list: WritableKeyPath<AgentAccess, [String]>, selection: Binding<String?>, title: String, text: String,
                       add: @escaping () -> Void) -> some View {
        let items = access[keyPath: list]
        return VStack(alignment: .leading, spacing: 0) {
            Text(title)
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
            ForEach(Array(items.sorted().enumerated()), id: \.element) { i, item in
                Text(item).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(selection.wrappedValue == item ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(i.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.04)))
                    .contentShape(Rectangle())
                    .onTapGesture { selection.wrappedValue = item }
            }
            if items.isEmpty {
                Text("None").foregroundStyle(.tertiary).padding(.horizontal, 8).padding(.vertical, 5)
            }
            Divider().padding(.top, 4)
            HStack(spacing: 0) {
                Button(action: add) { Image(systemName: "plus").frame(width: 24, height: 20).contentShape(Rectangle()) }
                    .accessibilityLabel("Add")
                Divider().frame(height: 14)
                Button {
                    if let s = selection.wrappedValue { access[keyPath: list].removeAll { $0 == s }; selection.wrappedValue = nil }
                } label: { Image(systemName: "minus").frame(width: 24, height: 20).contentShape(Rectangle()) }
                    .disabled(selection.wrappedValue.map { !items.contains($0) } ?? true)
                    .accessibilityLabel("Remove")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }
}

/// What the assistant may do by default.
struct AssistantPermissionsSection: View {
    @State private var permissions = AssistantPermissions.stored

    var body: some View {
        Section("Defaults") {
            ForEach(AssistantPermission.allCases) { p in
                VStack(alignment: .leading, spacing: 2) {
                    if p.choices.count > 1 {
                        Picker(p.title, selection: Binding(get: { permissions.policy(p) }, set: { permissions.set(p, $0) })) {
                            ForEach(p.choices, id: \.self) { Text($0.title).tag($0) }
                        }
                    } else {
                        LabeledContent(p.title, value: "Always on")
                    }
                    Text(p.detail).font(.caption).foregroundStyle(.secondary)
                    if p == .webSearch {
                        Text("Works with Claude, GPT and Gemini models (also through OpenCode) and with OpenRouter.").font(.caption).foregroundStyle(.secondary)
                    }
                    if p == .viewPreview {
                        Text("Works with Claude, GPT-4o/5/6 and Gemini models.").font(.caption).foregroundStyle(.secondary)
                    }
                    if p == .projectFiles || p == .searchProject {
                        Text("Works with Claude, GPT, Gemini and other models that call functions. The on-device model can only read outlines.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: permissions) { AssistantPermissions.stored = permissions }
    }
}

/// "This conversation may:" in the sidebar header: the permissions as toggles over the defaults.
struct AssistantPermissionsPopover: View {
    @Bindable var model: AssistantModel

    var body: some View {
        let effective = model.permissions
        VStack(alignment: .leading, spacing: 10) {
            Text("This conversation may:").font(.headline)
            ForEach(AssistantPermission.allCases) { p in row(p, effective.policy(p)) }
            Divider()
            HStack {
                Text("Defaults are set in Settings › Intelligence.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { model.resetPermissions() }.controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private func row(_ p: AssistantPermission, _ policy: PermissionPolicy) -> some View {
        let searchMissing = (p == .webSearch && !model.canSearch) || ((p == .projectFiles || p == .searchProject) && !model.canUseTools) || (p == .viewPreview && !model.canSeeImages)
        VStack(alignment: .leading, spacing: 2) {
            if p.choices.count == 1 {
                Toggle(p.title, isOn: .constant(true)).disabled(true)
            } else {
                Toggle(p.title, isOn: Binding(get: { p == .changeFiles || p == .createFiles ? policy != .never : policy == p.onPolicy },
                                              set: { model.setPermission(p, $0 ? p.onPolicy : .never) }))
                    .disabled(searchMissing)
            }
            Text(searchMissing ? "Not available with \(model.provider?.name ?? "this provider")" : policy == .ask && p == .webSearch ? "Asks before each message" : policy == .ask && p == .projectFiles ? "Asks before reading a file" : policy == .ask && p == .viewPreview ? "Asks before looking at the preview" : policy == .ask && (p == .changeFiles || p == .createFiles) ? "Shows a card to accept first" : policy == .allow && p == .changeFiles ? "Applies changes right away" : policy == .allow && p == .createFiles ? "Creates files right away" : p.detail)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
