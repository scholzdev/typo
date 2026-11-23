import AppKit
import SwiftUI
import TypoKit

extension SettingsKey {
    static let sourceControl = "sourceControlEnabled"
    static let gitRefreshLocal = "gitRefreshLocalStatus"
    static let gitAutoFetch = "gitAutoFetch"
    static let gitAutoAddRemove = "gitAutoAddRemove"
    static let gitShowChanges = "gitShowChanges"
    static let gitIncludeUpstream = "gitIncludeUpstream"
    static let gitLocalOnLeft = "gitLocalRevisionOnLeft"
    static let gitNavigatorOrder = "gitNavigatorOrder"
    static let gitDefaultBranch = "gitDefaultBranch"
}

/// Settings › Source Control read outside SwiftUI views (the gutter, commands, file operations). The defaults
/// match the `@AppStorage` ones in `SourceControlSettings`.
enum SourceControl {
    private static func bool(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }

    static var isEnabled: Bool { bool(SettingsKey.sourceControl, true) }
    static var refreshesLocalStatus: Bool { isEnabled && bool(SettingsKey.gitRefreshLocal, true) }
    static var fetchesAutomatically: Bool { isEnabled && bool(SettingsKey.gitAutoFetch, true) }
    static var addsAndRemovesFiles: Bool { isEnabled && bool(SettingsKey.gitAutoAddRemove, false) }
    static var showsChanges: Bool { isEnabled && bool(SettingsKey.gitShowChanges, true) }
    static var includesUpstream: Bool { showsChanges && bool(SettingsKey.gitIncludeUpstream, false) }
    static var defaultBranch: String { UserDefaults.standard.string(forKey: SettingsKey.gitDefaultBranch) ?? "main" }
}

/// Like Xcode's Source Control pane: the master switch, hosting accounts, then the behaviours. "Git settings"
/// opens a second page in place, as Xcode pushes it.
struct SourceControlSettings: View {
    @AppStorage(SettingsKey.sourceControl) private var enabled = true
    @AppStorage(SettingsKey.gitRefreshLocal) private var refreshLocal = true
    @AppStorage(SettingsKey.gitAutoFetch) private var autoFetch = true
    @AppStorage(SettingsKey.gitAutoAddRemove) private var autoAddRemove = false
    @AppStorage(SettingsKey.gitShowChanges) private var showChanges = true
    @AppStorage(SettingsKey.gitIncludeUpstream) private var includeUpstream = false
    @AppStorage(SettingsKey.gitLocalOnLeft) private var localOnLeft = false
    @AppStorage(SettingsKey.gitNavigatorOrder) private var order = GitChangeOrder.name.rawValue
    @AppStorage(SettingsKey.gitDefaultBranch) private var defaultBranch = "main"
    @State private var branchText = ""
    @Environment(SettingsNavigation.self) private var nav
    @State private var addingAccount = false
    private let accounts = GitAccountStore.shared

    var body: some View {
        if nav.page?.tab == .sourceControl && nav.page?.id == "git" {
            GitGlobalSettings()
        } else {
            main
        }
    }

    private var main: some View {
        Form {
            Section {
                Toggle("Enable source control", isOn: $enabled)
            }
            Section("Accounts") {
                ForEach(accounts.accounts) { AccountRow(account: $0) }
                HStack {
                    Spacer()
                    Button("Add Account…") { addingAccount = true }
                }
            }
            Section("Settings") {
                Button { nav.page = SettingsSubpage(tab: .sourceControl, id: "git", title: "Git Settings") } label: {
                    HStack {
                        Text("Git settings")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Group {
                Section {
                    Toggle("Refresh local status automatically", isOn: $refreshLocal)
                        .help("Updates the Changes list when you save and when you come back to Typo")
                    Toggle("Fetch and refresh server status automatically", isOn: $autoFetch)
                        .help("Fetches from the remote every few minutes, so ↑ and ↓ stay current")
                    Toggle("Add and remove files automatically", isOn: $autoAddRemove)
                        .help("Stages files you create, rename or move to the Trash in Typo")
                }
                Section {
                    Toggle("Show source control changes", isOn: $showChanges)
                        .help("Change bars and blame in the editor's gutter")
                    Toggle("Include upstream changes", isOn: $includeUpstream)
                        .disabled(!showChanges)
                        .help("The gutter compares with the upstream branch, so commits not yet pulled or pushed show too")
                }
                Section {
                    Picker("Comparison view", selection: $localOnLeft) {
                        Text("Local Revision on Left Side").tag(true)
                        Text("Local Revision on Right Side").tag(false)
                    }
                }
                Section {
                    Picker("Source control navigator", selection: $order) {
                        ForEach(GitChangeOrder.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    LabeledContent {
                        TextField("main", text: $branchText)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.plain)
                            .foregroundStyle(GitBranchName.isValid(branchText) ? .secondary : Color.red)
                            .onSubmit(commitBranch)
                            .onChange(of: branchText) { _, _ in commitBranch() }
                    } label: {
                        Text("Default branch name")
                        Text("Branch names cannot contain spaces, backslashes, or other symbols.")
                    }
                }
            }
            .disabled(!enabled)
        }
        .pane()
        .onAppear { branchText = defaultBranch }
        .sheet(isPresented: $addingAccount) { AddAccountSheet() }
    }

    /// Only a valid name is kept; an invalid one stays red in the field and new repositories go on using the last.
    private func commitBranch() {
        let name = branchText.trimmingCharacters(in: .whitespaces)
        if GitBranchName.isValid(name) { defaultBranch = name }
    }
}

private struct AccountRow: View {
    let account: GitAccount

    var body: some View {
        HStack(spacing: 10) {
            HostIcon(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(account.username)
                Text("\(account.host.name) · \(account.server.host() ?? account.server.absoluteString)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", systemImage: "minus.circle") {
                guard confirm("Remove the account “\(account.username)”?", "Its token is deleted from the Keychain. Pushing and pulling over HTTPS then uses your other git credentials.", ok: "Remove") else { return }
                GitAccountStore.shared.remove(account)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove this account")
        }
    }
}

/// The grey tile Xcode shows for every hosting service.
private struct HostIcon: View {
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(.gray.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

/// Xcode's two steps: pick the kind of account, then sign in with a token.
private struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host: GitHost? = .github
    @State private var signingIn: GitHost?

    var body: some View {
        if let signingIn {
            SignInForm(host: signingIn) { dismiss() } back: { self.signingIn = nil }
        } else {
            VStack(spacing: 14) {
                Text("Select the type of account you would like to add:")
                List(GitHost.allCases, selection: $host) { h in
                    HStack(spacing: 12) {
                        HostIcon()
                        Text(h.name)
                    }
                    .padding(.vertical, 4)
                    .tag(h)
                }
                .contextMenu(forSelectionType: GitHost.self) { _ in } primaryAction: { s in
                    if let h = s.first { signingIn = h }
                }
                .listStyle(.bordered)
                .frame(height: 280)
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Continue") { signingIn = host }.keyboardShortcut(.defaultAction).disabled(host == nil)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }
}

private struct SignInForm: View {
    let host: GitHost
    let done: () -> Void
    let back: () -> Void
    @State private var server = ""
    @State private var account = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?

    private var serverURL: URL? { host.fixedServer ?? GitAccount.normalizedServer(server) }
    private var complete: Bool { serverURL != nil && !account.trimmingCharacters(in: .whitespaces).isEmpty && !token.isEmpty }

    var body: some View {
        VStack(spacing: 16) {
            Text("Sign in to your \(host.name) account").font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                if host.needsServer {
                    GridRow {
                        Text("Server:").gridColumnAlignment(.trailing)
                        TextField("", text: $server, prompt: Text("https://example.com"))
                    }
                }
                GridRow {
                    Text("Account:").gridColumnAlignment(.trailing)
                    TextField("", text: $account)
                }
                GridRow {
                    Text("\(host.tokenLabel):").gridColumnAlignment(.trailing)
                    SecureField("", text: $token, prompt: Text("Enter your \(host.tokenLabel)"))
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(busy)
            VStack(spacing: 4) {
                Text("\(host.name) \(host == .bitbucketCloud ? "app passwords need these permissions" : "personal access tokens must have these scopes set"):")
                    .bold()
                ForEach(host.requiredScopes, id: \.self) { Text("✓ \($0)") }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            if let error {
                Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Create a \(host.tokenLabel) on \(host.name)") {
                    if let s = serverURL, let url = host.tokenPage(server: s) { NSWorkspace.shared.open(url) }
                }
                .disabled(serverURL == nil)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Cancel") { back() }.keyboardShortcut(.cancelAction)
                Button("Sign In") { signIn() }.keyboardShortcut(.defaultAction).disabled(!complete || busy)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    /// The token is checked against the service before it is stored; the user name it belongs to is kept.
    private func signIn() {
        guard let s = serverURL else { return }
        let name = account.trimmingCharacters(in: .whitespaces)
        busy = true
        error = nil
        Task {
            do {
                let login = try await GitAccountStore.verify(host: host, server: s, account: name, token: token)
                try GitAccountStore.shared.add(GitAccount(host: host, server: s, username: login), token: token)
                done()
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

/// The page behind "Git settings": the author of new commits, from the global git configuration.
private struct GitGlobalSettings: View {
    @State private var name = ""
    @State private var email = ""
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Author") {
                    TextField("Name", text: $name, prompt: Text("Your Name"))
                    TextField("Email", text: $email, prompt: Text("you@example.com"))
                }
                Text("Written to your global git configuration (~/.gitconfig), so commits made in Terminal and other apps use them too.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .disabled(!loaded)
            .onSubmit(save)
            .pane()
        }
        .task {
            name = await GitGlobalConfig.value("user.name")
            email = await GitGlobalConfig.value("user.email")
            loaded = true
        }
        .onDisappear(perform: save)
    }

    private func save() {
        guard loaded else { return }
        let n = name, e = email
        Task {
            do {
                if n != (await GitGlobalConfig.value("user.name")) { try await GitGlobalConfig.set("user.name", n) }
                if e != (await GitGlobalConfig.value("user.email")) { try await GitGlobalConfig.set("user.email", e) }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
