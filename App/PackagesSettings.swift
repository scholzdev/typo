import AppKit
import SwiftUI
import TypoKit
import TypstEngine

struct PackagesSettings: View {
    @Environment(LocalPackagesFolder.self) private var packages
    let updates: PackageUpdateModel
    @State private var rows: [PackageRow] = []
    @State private var selection = Set<PackageRow.ID>()
    @State private var loaded = false
    @State private var failure: String?

    struct PackageRow: Identifiable {
        let package: InstalledPackage
        let isLocal: Bool
        var id: String { (isLocal ? "local|" : "dl|") + package.id }
        var title: String { "@\(package.namespace)/\(package.name)" }
        var source: String { isLocal ? "Local" : "Downloaded" }
    }

    private var chosen: [PackageRow] { rows.filter { selection.contains($0.id) } }

    private var installedVersions: [String: Set<String>] {
        rows.filter { !$0.isLocal && $0.package.namespace == "preview" }
            .reduce(into: [:]) { $0[$1.package.name, default: []].insert($1.package.version) }
    }

    var body: some View {
        Form {
            Section("Local Packages") { folder }
            updatesSection
            Section("Installed") {
            if loaded && rows.isEmpty {
                ContentUnavailableView("No Packages", systemImage: "shippingbox", description: Text("Packages Typst downloads and your local packages appear here."))
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Package", value: \.title)
                    TableColumn("Version") { Text($0.package.version) }.width(70)
                    TableColumn("Size") { Text($0.package.bytes.formatted(.byteCount(style: .file))).monospacedDigit() }.width(70)
                    TableColumn("Source", value: \.source).width(90)
                }
                .contextMenu(forSelectionType: PackageRow.ID.self) { ids in
                    actions(for: rows.filter { ids.contains($0.id) })
                }
                .frame(minHeight: 220)
            }
            HStack {
                Text("\(rows.count) packages, \(rows.reduce(0) { $0 + $1.package.bytes }.formatted(.byteCount(style: .file)))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh").accessibilityLabel("Refresh")
                actions(for: chosen)
            }
            }
            UniverseBrowser(installed: installedVersions) { await reload() }
        }
        .pane()
        .task(id: packages.url) { await reload() }
        .alert("Couldn\u{2019}t Move to Trash", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        } message: { Text(failure ?? "") }
    }

    private var updatesSection: some View {
        Section {
            if updates.installed.isEmpty {
                Text("No Typst Universe packages are downloaded yet.").foregroundStyle(.secondary)
            }
            ForEach(updates.installed.keys.sorted(), id: \.self) { name in
                let update = updates.updates.first { $0.name == name }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@preview/\(name)").fontWeight(.medium)
                        if let e = updates.errors[name] { Text(e).font(.caption).foregroundStyle(.red) }
                    }
                    Spacer()
                    let versions = (updates.installed[name] ?? []).sorted { $0.compare($1, options: .numeric) == .orderedAscending }
                    Text(update.map { "\($0.installed) \u{2192} \($0.newest)" } ?? versions.joined(separator: ", "))
                        .monospacedDigit().foregroundStyle(.secondary)
                    if let update {
                        if updates.installing.contains(name) {
                            ProgressView().controlSize(.small).frame(width: 70).accessibilityLabel("Updating \(name)")
                        } else {
                            Button("Update") { Task { await updates.update(update); await reload() } }.frame(minWidth: 70)
                        }
                    }
                }
            }
            Text("Documents keep the version they import; update their imports from the editor.")
                .font(.caption).foregroundStyle(.secondary)
        } header: {
            HStack {
                Text("Installed Packages")
                Spacer()
                if !updates.updates.isEmpty {
                    Button("Update All") { Task { await updates.updateAll(); await reload() } }
                        .disabled(!updates.installing.isEmpty)
                }
            }
        }
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Local packages folder") {
                HStack {
                    Text(packages.url?.path ?? "Not set")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Button("Choose…") { choose() }
                    Button("Clear") { Task { await packages.clear() } }.disabled(packages.url == nil)
                }
            }
            Text("Packages here resolve as @local/name:version, and any other namespace folder works too. Typst's own folder is Library/Application Support/typst/packages in your home folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func actions(for items: [PackageRow]) -> some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.package.url)) }
            .disabled(items.isEmpty)
        Button("Move to Trash") { Task { await trash(items) } }.disabled(items.isEmpty)
    }

    private func reload() async {
        let downloaded = TypstRuntime.packageDirectory
        let local = packages.url.flatMap { $0.standardizedFileURL == downloaded.standardizedFileURL ? nil : $0 }
        let found = await Task.detached {
            InstalledPackage.list(in: downloaded).map { PackageRow(package: $0, isLocal: false) }
                + (local.map { InstalledPackage.list(in: $0).map { PackageRow(package: $0, isLocal: true) } } ?? [])
        }.value
        rows = found
        selection.formIntersection(found.map(\.id))
        loaded = true
        await updates.refresh()
    }

    private func trash(_ items: [PackageRow]) async {
        do {
            for item in items {
                let version = item.package.url, name = version.deletingLastPathComponent(), ns = name.deletingLastPathComponent()
                try FileManager.default.trashItem(at: version, resultingItemURL: nil)
                for dir in [name, ns] where (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
        } catch { failure = error.localizedDescription }
        await reload()
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds your local packages (namespace/name/version). Typst's default is Library/Application Support/typst/packages."
        // The sandbox home is the app container, so ask the user database for the real one.
        if let pw = getpwuid(getuid()) {
            panel.directoryURL = URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
                .appending(path: "Library/Application Support/typst/packages")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { try? await packages.choose(url) }
    }
}
