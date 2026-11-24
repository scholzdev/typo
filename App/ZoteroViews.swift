import SwiftUI
import TypoKit
import TypstEngine

extension Project {
    /// One sync with the key from the Keychain (read only for the web API: the local app needs none).
    func syncZoteroNow() async {
        guard let link = zoteroLink else { return }
        await syncZotero(key: link.source == .web ? ZoteroKeychain.key(for: link.userID) : nil)
    }

    /// While the window is open: a sync now (the project just opened or was linked), then every five minutes.
    /// Cheap when nothing changed: the web API answers 304, and an unchanged library writes nothing.
    func runZoteroSync() async {
        while zoteroLink != nil, !Task.isCancelled {
            await syncZoteroNow()
            try? await Task.sleep(for: .seconds(300))
        }
    }
}

/// Above a `.bib` file that Zotero fills, in the form and the source view alike; the editors show it read-only.
struct ZoteroBanner: View {
    let project: Project
    let buffer: Buffer

    var body: some View {
        if buffer.isZoteroManaged, let link = project.zoteroLink {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Managed by Zotero", systemImage: "books.vertical.fill").fontWeight(.medium)
                    Text(details(link)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if project.zoteroSyncing { ProgressView().controlSize(.small) }
                    Button("Sync Now") { Task { await project.syncZoteroNow() } }.buttonStyle(.glass).disabled(project.zoteroSyncing)
                    Button("Disconnect") { project.disconnectZotero() }.buttonStyle(.glass)
                        .help("Stop syncing; the file stays as ordinary BibTeX")
                }
                if let error = project.zoteroError {
                    Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .padding(.horizontal, 8).padding(.top, 8)
        }
    }

    private func details(_ link: ZoteroLink) -> String {
        let synced = link.lastSynced.map { String(localized: "Last synced \($0.formatted(.relative(presentation: .named)))") } ?? String(localized: "Not synced yet")
        return ([link.libraryName, synced] + [link.entryCount.map { String(localized: "\($0) entries") }].compactMap { $0 }).joined(separator: " \u{00B7} ")
    }
}

/// Connect Zotero: the source, the library or collection, and the `.bib` file it fills.
struct ZoteroConnectSheet: View {
    let project: Project
    /// The file to suggest as the target, e.g. the one the BibTeX editor shows.
    var suggested: RelPath?
    @Environment(\.dismiss) private var dismiss
    @State private var source = ZoteroSource.local
    @State private var userID = UserDefaults.standard.string(forKey: ZoteroKeychain.userIDKey) ?? ""
    @State private var apiKey = ""
    @State private var collections: [ZoteroCollection]?
    @State private var collection: ZoteroCollection?
    @State private var target = ""
    @State private var error: String?
    @State private var busy = false

    private var bibFiles: [RelPath] { project.allFiles.filter { $0.raw.lowercased().hasSuffix(".bib") } }
    private var targetPath: RelPath? {
        let t = target.trimmingCharacters(in: .whitespaces)
        return t.lowercased().hasSuffix(".bib") ? RelPath(t) : nil
    }
    private var hasSavedKey: Bool { !userID.isEmpty && ZoteroKeychain.hasKey(for: userID) }
    private var key: String? { apiKey.isEmpty ? (hasSavedKey ? ZoteroKeychain.key(for: userID) : nil) : apiKey }
    private var webReady: Bool { source == .local || (Int(userID) != nil && (!apiKey.isEmpty || hasSavedKey)) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Library Source", selection: $source) {
                        Text("Local Zotero App").tag(ZoteroSource.local)
                        Text("Zotero Account").tag(ZoteroSource.web)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(source == .local
                         ? "Reads the library of the Zotero app on this Mac. Zotero must be running, with \u{201C}Allow other applications on this computer to communicate with Zotero\u{201D} on in Zotero \u{203A} Settings \u{203A} Advanced."
                         : "Reads your online library. The key is kept in your Keychain; Typo only reads, never uploads.")
                }
                if source == .web {
                    Section {
                        TextField("User ID", text: $userID, prompt: Text("123456"))
                        SecureField("API Key", text: $apiKey, prompt: Text(hasSavedKey ? "Saved in Keychain" : "Read-only key"))
                    } footer: {
                        Link("Find your user ID and create a key at zotero.org/settings/keys", destination: URL(string: "https://www.zotero.org/settings/keys")!)
                    }
                }
                Section {
                    HStack {
                        Picker("Library", selection: $collection) {
                            Text("My Library").tag(ZoteroCollection?.none)
                            ForEach(collections ?? []) { Text($0.name).tag(Optional($0)) }
                        }
                        Button("Load Collections") { Task { await loadCollections() } }.disabled(busy || !webReady)
                    }
                    TextField("BibTeX File", text: $target, prompt: Text("refs.bib"))
                    if !bibFiles.isEmpty {
                        Picker("Existing File", selection: Binding(get: { targetPath }, set: { if let p = $0 { target = p.raw } })) {
                            Text("New File").tag(RelPath?.none)
                            ForEach(bibFiles, id: \.self) { Text($0.raw).tag(Optional($0)) }
                        }
                    }
                } footer: {
                    Text("Every sync overwrites this file with the library\u{2019}s entries. No other file is changed.")
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                SheetButtons(ok: "Connect", disabled: busy || !webReady || targetPath == nil, cancel: { dismiss() }, action: { Task { await connect() } })
            }
            .padding(14)
        }
        .frame(width: 500)
        .onAppear {
            if let link = project.zoteroLink {
                source = link.source
                if link.source == .web { userID = link.userID }
                collection = link.collection
                collections = link.collection.map { [$0] }
                target = link.target.raw
            } else {
                target = (suggested ?? bibFiles.first)?.raw ?? "refs.bib"
            }
        }
        .onChange(of: source) { collections = nil; collection = nil; error = nil }
    }

    private var client: ZoteroClient { ZoteroClient(source: source, userID: userID, key: key) }

    private func loadCollections() async {
        busy = true
        defer { busy = false }
        do {
            collections = try await client.collections()
            error = nil
        } catch let e { error = e.localizedDescription }
    }

    private func connect() async {
        guard let targetPath else { return }
        if source == .web {
            if !apiKey.isEmpty, !ZoteroKeychain.setKey(apiKey, for: userID) { error = String(localized: "The key could not be saved in the Keychain."); return }
            UserDefaults.standard.set(userID, forKey: ZoteroKeychain.userIDKey)
        }
        if project.allFiles.contains(targetPath), project.zoteroLink?.target != targetPath,
           !confirm("Replace \u{201C}\(targetPath.name)\u{201D} with your Zotero library?", "Its current entries are overwritten by every sync. To get them back, disconnect Zotero, then use Edit \u{203A} Undo.", ok: "Replace") {
            return
        }
        busy = true
        defer { busy = false }
        await project.connectZotero(ZoteroLink(source: source, userID: userID, collection: collection, target: targetPath))
        await project.syncZoteroNow()
        if let e = project.zoteroError { error = e } else { dismiss() }
    }
}

/// Settings › Components: the saved web API key, which stays after a project disconnects.
struct ZoteroSettingsSection: View {
    @State private var userID = UserDefaults.standard.string(forKey: ZoteroKeychain.userIDKey) ?? ""
    @State private var hasKey = false

    var body: some View {
        Section("Zotero") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "books.vertical").font(.title2).frame(width: 28).foregroundStyle(.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Zotero Account")
                    Text(hasKey ? "User \(userID) \u{00B7} API key saved in the Keychain" : "No API key saved. The local Zotero app needs none.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if hasKey {
                    Button("Remove Key", role: .destructive) {
                        ZoteroKeychain.removeKey(for: userID)
                        hasKey = false
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .onAppear { hasKey = !userID.isEmpty && ZoteroKeychain.hasKey(for: userID) }
    }
}
