import SwiftUI
import TypoAssistant

/// The card at the top of an Intelligence page: an icon, a title and what the page is for, as in Xcode.
struct SettingsHeaderCard: View {
    let symbol: String
    var fill: AnyShapeStyle = AnyShapeStyle(Color.blue.gradient)
    let title: String
    let text: String
    var link: (title: String, action: () -> Void)? = nil

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(fill, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .regular))
                    Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let link {
                        Button(link.title, action: link.action).buttonStyle(.link)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// A row that opens a sub-page: a title, a secondary line and a chevron.
struct SettingsPageRow: View {
    let title: String
    let subtitle: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The 28 pt icon of an agent or model provider.
struct ProviderIcon: View {
    let presetID: String
    var size: CGFloat = 28

    var body: some View {
        if ["acp-claude", "anthropic"].contains(presetID), let icon = Self.claudeIcon {
            Image(nsImage: icon).resizable().frame(width: size, height: size).accessibilityHidden(true)
        } else {
            symbolIcon
        }
    }

    /// The installed Claude app's own icon, read at run time rather than shipped; nil without the app.
    private static let claudeIcon: NSImage? = ["com.anthropic.claudefordesktop", "com.anthropic.claude-code"].lazy
        .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        .first.map { NSWorkspace.shared.icon(forFile: $0.path) }

    private var symbolIcon: some View {
        let (symbol, fill, ink) = Self.look(presetID)
        return Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.24))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(.separator, lineWidth: ink == .primary ? 0.5 : 0))
            .accessibilityHidden(true)
    }

    private static func look(_ id: String) -> (String, AnyShapeStyle, Color) {
        switch id {
        case "acp-claude", "anthropic": ("asterisk", AnyShapeStyle(Color(red: 0.85, green: 0.47, blue: 0.34).gradient), .white)
        case "acp-codex", "openai": ("hexagon", AnyShapeStyle(Color(nsColor: .textBackgroundColor)), .primary)
        case "acp-gemini": ("sparkle", AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .bottomLeading, endPoint: .topTrailing)), .white)
        case "acp-goose": ("bird.fill", AnyShapeStyle(Color.black.gradient), .white)
        case "acp-opencode", "opencode-zen", "opencode-go": ("chevron.left.forwardslash.chevron.right", AnyShapeStyle(Color(white: 0.2).gradient), .white)
        case "acp-custom": ("puzzlepiece.extension.fill", AnyShapeStyle(Color.blue.gradient), .white)
        case "on-device": ("apple.intelligence", AnyShapeStyle(Color.purple.gradient), .white)
        case "ollama", "lmstudio", "custom-local": ("desktopcomputer", AnyShapeStyle(Color.green.gradient), .white)
        default: ("cloud.fill", AnyShapeStyle(Color.blue.gradient), .white)
        }
    }
}

extension AssistantPreset {
    /// The agent's name without the "(ACP)" the provider menu needs: the Agents section says it already.
    var shortName: String { name.replacingOccurrences(of: " (ACP)", with: "") }
}

extension AssistantProvider {
    var shortName: String { name.replacingOccurrences(of: " (ACP)", with: "") }
}

/// The links of an agent's vendor, for its Account footer; nil where Typo knows none.
enum VendorPolicy {
    static func links(_ organization: String) -> (privacy: String, terms: String)? {
        switch organization {
        case "Anthropic": ("https://www.anthropic.com/legal/privacy", "https://www.anthropic.com/legal/consumer-terms")
        case "OpenAI": ("https://openai.com/policies/privacy-policy/", "https://openai.com/policies/terms-of-use/")
        case "Google": ("https://policies.google.com/privacy", "https://policies.google.com/terms")
        default: nil
        }
    }
}

/// "About Intelligence in Typo & Privacy…": what leaves the Mac, and when.
struct IntelligencePrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Intelligence in Typo & Privacy").font(.system(size: 22, weight: .bold)).padding(.bottom, 6)
                    Text("Typo sends nothing anywhere until you set up a model provider or an agent in Settings › Intelligence. You choose which one a conversation uses.")
                    Text("Apple Intelligence runs on this Mac. What you ask it, and the passage it reads, stay on the Mac.")
                    Text("Using Third-Party Models")
                    Text("A model provider you add with an API key receives your messages, the conversation so far and the files you attach or allow it to read. It handles them under its own terms. The key is kept in your Keychain.")
                    Text("An agent such as Claude Code runs on this Mac in the project folder. It reads and changes the project's files itself and sends what it reads to its own provider, under that provider's terms and with your login there.")
                    Text("Typo collects no analytics or usage data.")
                    Text("Conversations are stored on this Mac with Typo's data and can be deleted at any time. You can remove a provider or an agent in Settings › Intelligence; removing a provider also removes its key.")
                }
                .font(.system(size: 15))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40).padding(.top, 40).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The buttons sit in a bar of their own, so the text never runs under them.
            Divider()
            HStack {
                Button("See how your data is managed…") { openURL(URL(string: "https://github.com/scholzdev/typo#privacy")!) }
                    .buttonBorderShape(.capsule)
                    .focusable(false)
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction).buttonBorderShape(.capsule)
            }
            .controlSize(.large)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.bar)
        }
        .frame(width: 520, height: 460)
    }
}

/// "Add an Agent…": any agent that speaks ACP, from its executable, an optional interpreter and arguments.
struct AddAgentSheet: View {
    let add: (AssistantProvider) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var executable = ""
    @State private var interpreter = ""
    @State private var arguments: [String] = []
    @State private var selected: Int?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                SettingsHeaderCard(symbol: "puzzlepiece.extension.fill", title: "Add an ACP Agent",
                                   text: "Register a coding agent that speaks the Agent Client Protocol. Agents work in the project folder and can read and change its files.",
                                   link: ("Learn more about ACP…", { NSWorkspace.shared.open(URL(string: "https://agentclientprotocol.com")!) }))
                Section { TextField("Name", text: $name, prompt: Text("My Agent")) }
                Section {
                    LabeledContent("Executable") {
                        HStack {
                            TextField("Executable", text: $executable, prompt: Text("/absolute/path/to/agent")).labelsHidden().multilineTextAlignment(.trailing)
                            Button("Choose…") { choose { executable = $0 } }
                        }
                    }
                }
                Section {
                    TextField("Interpreter", text: $interpreter, prompt: Text("Optional"))
                } footer: {
                    Text("Specify an interpreter if the executable is a script. The interpreter runs the executable as its argument.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Arguments") {
                    if arguments.isEmpty {
                        Text("No Arguments").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    ForEach(arguments.indices, id: \.self) { i in
                        TextField("Argument \(i + 1)", text: $arguments[i], prompt: Text("--acp")).labelsHidden()
                            .onTapGesture { selected = i }
                    }
                    HStack(spacing: 0) {
                        Button { arguments.append(""); selected = arguments.count - 1 } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                            .accessibilityLabel("Add Argument")
                        Divider().frame(height: 14)
                        Button { arguments.remove(at: min(selected ?? arguments.count - 1, arguments.count - 1)); selected = nil } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                            .disabled(arguments.isEmpty)
                            .accessibilityLabel("Remove Argument")
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { save() }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 480, height: 500)
    }

    private var path: String { (executable.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath }

    /// A name and an absolute path to a file that runs (or is run by the interpreter).
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && path.hasPrefix("/")
            && (interpreter.isEmpty ? FileManager.default.isExecutableFile(atPath: path) : FileManager.default.fileExists(atPath: path))
    }

    private func save() {
        let words = (interpreter.isEmpty ? [] : [interpreter.trimmingCharacters(in: .whitespaces)]) + [path] + arguments.filter { !$0.isEmpty }
        var p = AssistantProvider(preset: AssistantPreset.named("acp-custom")!, name: name.trimmingCharacters(in: .whitespaces))
        // ACPProcess.words splits on spaces outside quotes.
        p.command = words.map { $0.contains(where: \.isWhitespace) ? "\"\($0)\"" : $0 }.joined(separator: " ")
        add(p)
        dismiss()
    }

    private func choose(_ picked: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        if panel.runModal() == .OK, let url = panel.url { picked(url.path) }
    }
}
