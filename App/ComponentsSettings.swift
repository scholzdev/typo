import AppKit
import SwiftUI
import TypoKit
import TypstEngine
import ACPProtocol
import MCPProtocol
import TypoACP
import TypoMCP

/// One row of the pane. Adding a row is adding an item in `ComponentsLoader.load`.
struct ComponentItem: Identifiable {
    enum Action: Hashable { case showInFinder, refreshIndex, rebuildFontIndex, managePackages }
    let id: String
    var title: String
    var symbol: String
    var status: String
    var caption: String?
    var path: URL?
    var sizeBytes: Int64?
    var actions: [Action] = []
}

struct ComponentSection: Identifiable {
    let title: String
    var items: [ComponentItem]
    var id: String { title }
}

enum ComponentsLoader {
    static func load() async -> [ComponentSection] {
        let runtime = await TypstRuntime.shared.value
        // Sizes walk the disk, so they run off the main actor.
        return await Task.detached { build(runtime) }.value
    }

    private static func build(_ rt: TypstRuntime) -> [ComponentSection] {
        let packageDir = TypstRuntime.packageDirectory
        let fontIndex = TypstRuntime.defaultIndexURL
        let installed = InstalledPackage.list(in: packageDir)
        let fonts = EngineVersions.embeddedFonts
        let snapshots = LocalHistory.rootFolder
        let fontCacheSize = DiskUsage.bytes(of: fontIndex)
        let updated = rt.packageIndexUpdated.map { "Updated " + $0.formatted(.relative(presentation: .named)) } ?? "Not downloaded yet"
        let indexCount = rt.packageIndexCount
        return [
            ComponentSection(title: "Typesetting Engine", items: [
                ComponentItem(id: "typst", title: "Typst \(EngineVersions.typst)", symbol: "doc.text", status: "Built into Typo",
                              caption: "The compiler ships with the app and updates with it."),
                ComponentItem(id: "typstyle", title: "typstyle \(EngineVersions.typstyle)", symbol: "text.alignleft", status: "Built in",
                              caption: "The code formatter."),
            ]),
            ComponentSection(title: "Modules", items: [
                ComponentItem(id: "module-engine", title: "Typesetting engine", symbol: "gearshape.2",
                              status: "TypstEngine \(TypstEngineInfo.version) \u{2014} speaks Typst \(TypstEngineInfo.typstVersion)"),
                ComponentItem(id: "module-acp", title: "Agent client", symbol: "person.2.wave.2",
                              status: "TypoACP \(TypoACPInfo.version), ACPProtocol \(ACPProtocolInfo.version) \u{2014} speaks ACP v\(ACPProtocolInfo.protocolVersion)"),
                ComponentItem(id: "module-mcp", title: "MCP server", symbol: "server.rack",
                              status: "TypoMCP \(TypoMCPInfo.version), MCPProtocol \(MCPProtocolInfo.version) \u{2014} speaks MCP "
                                  + MCPProtocolInfo.protocolVersions.joined(separator: ", ")),
            ]),
            ComponentSection(title: "Fonts", items: [
                ComponentItem(id: "embedded", title: "Embedded Typst Fonts", symbol: "textformat",
                              status: "\(fonts.files) files: \(fonts.families)"),
                ComponentItem(id: "system", title: "System Fonts", symbol: "character.book.closed",
                              status: "\(rt.fontFileCount) font files handed to the engine",
                              caption: "Font index cache. Rebuilding deletes it and Typo recreates it on the next launch.",
                              path: fontIndex, sizeBytes: fontCacheSize, actions: [.showInFinder, .rebuildFontIndex]),
            ]),
            ComponentSection(title: "Packages", items: [
                ComponentItem(id: "packages", title: "Downloaded Packages", symbol: "shippingbox",
                              status: "\(installed.count) packages", path: packageDir,
                              sizeBytes: installed.reduce(0) { $0 + $1.bytes }, actions: [.showInFinder, .managePackages]),
                ComponentItem(id: "index", title: "Package Index", symbol: "list.bullet.rectangle",
                              status: indexCount > 0 ? "\(updated), \(indexCount) packages" : updated,
                              caption: "The list of @preview packages behind completion and templates.",
                              actions: [.refreshIndex]),
            ]),
            ComponentSection(title: "Local History", items: [
                ComponentItem(id: "snapshots", title: "Snapshots", symbol: "clock.arrow.circlepath",
                              status: "All projects", caption: LocalHistory.retentionDescription, path: snapshots,
                              sizeBytes: DiskUsage.bytes(of: snapshots), actions: [.showInFinder]),
            ]),
        ]
    }
}

struct ComponentsSettings: View {
    @State private var sections: [ComponentSection] = []
    @State private var busy = false
    @State private var indexMessage: String?
    @State private var confirmRebuild = false

    var body: some View {
        Form {
            ForEach(sections) { section in
                Section(section.title) { ForEach(section.items) { row($0) } }
            }
            ZoteroSettingsSection()
        }
        .pane()
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in Task { await reload() } }
        .confirmationDialog("Rebuild the font index?", isPresented: $confirmRebuild) {
            Button("Delete Index", role: .destructive) {
                try? FileManager.default.removeItem(at: TypstRuntime.defaultIndexURL)
                Task { await reload() }
            }
        } message: { Text("This deletes the font index cache. Typo rebuilds it on the next launch, which then starts a little slower.") }
    }

    private func row(_ item: ComponentItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol).font(.title2).frame(width: 28).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                Text(item.sizeBytes.map { "\(item.status) \u{00B7} \($0.formatted(.byteCount(style: .file)))" } ?? item.status)
                    .font(.callout).foregroundStyle(.secondary)
                if let path = item.path {
                    Text(path.path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                if let caption = item.caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
                if item.id == "index", let indexMessage { Text(indexMessage).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            HStack {
                ForEach(item.actions, id: \.self) { button($0, item) }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func button(_ action: ComponentItem.Action, _ item: ComponentItem) -> some View {
        switch action {
        case .showInFinder:
            Button("Show in Finder") {
                // Select the item when it exists, else open its parent so the button never does nothing.
                guard let url = item.path else { return }
                if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                else { NSWorkspace.shared.open(url.deletingLastPathComponent()) }
            }
        case .managePackages:
            Button("Manage\u{2026}") { UserDefaults.standard.set("packages", forKey: SettingsKey.tab) }
        case .rebuildFontIndex:
            Button("Rebuild Index") { confirmRebuild = true }
                .help("Deletes the font index cache; it is rebuilt on the next launch.")
        case .refreshIndex:
            Button(busy ? "Checking\u{2026}" : "Check Now") { Task { await checkIndex() } }.disabled(busy)
                .help("Downloads the package index again")
        }
    }

    private func reload() async { sections = await ComponentsLoader.load() }

    private func checkIndex() async {
        busy = true
        indexMessage = nil
        do { _ = try await TypstRuntime.shared.value.refreshPackageIndex() }
        catch { indexMessage = "Check failed: \(error.localizedDescription)" }
        busy = false
        await reload()
    }
}
