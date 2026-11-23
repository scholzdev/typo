import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// Browse and install `@preview` packages. `installed` maps a package name to its downloaded versions.
struct UniverseBrowser: View {
    let installed: [String: Set<String>]
    let onInstalled: () async -> Void

    enum Kind: String, CaseIterable { case all = "All", packages = "Packages only", templates = "Templates only" }

    @State private var all: [UniversePackage] = []
    @State private var loaded = false
    @State private var query = ""
    @State private var kind = Kind.all
    @State private var category = ""
    @State private var updated: Date?
    @State private var checking = false
    @State private var indexError: String?
    @State private var installing = Set<String>()   // "name:version"
    @State private var errors: [String: String] = [:]   // by package name
    @State private var detail: String?

    private var categories: [String] { Array(Set(all.flatMap(\.categories))).sorted() }

    private var results: [UniversePackage] {
        all.filter {
            (kind == .all || $0.isTemplate == (kind == .templates)) && (category.isEmpty || $0.categories.contains(category))
                && Universe.matches($0, query: query)
        }
    }

    var body: some View {
        Section("Typst Universe") {
            if loaded && all.isEmpty {
                Text("The package index has not been downloaded yet. Check now to browse the packages of Typst Universe.")
                    .foregroundStyle(.secondary)
            } else {
                TextField("Search packages", text: $query).textFieldStyle(.roundedBorder).accessibilityLabel("Search packages")
                HStack {
                    Picker("Show", selection: $kind) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) } }
                    Picker("Category", selection: $category) {
                        Text("All Categories").tag("")
                        ForEach(categories, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                let shown = results
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { row($0); Divider() }
                    }
                }
                .frame(height: 340)
                Text("\(shown.count) of \(all.count) packages").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(updated.map { "Updated " + $0.formatted(.relative(presentation: .named)) } ?? "Not downloaded yet")
                    .font(.caption).foregroundStyle(.secondary)
                if let indexError { Text(indexError).font(.caption).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                if checking { ProgressView().controlSize(.small) }
                Button("Check Now") { Task { await check() } }.disabled(checking)
            }
        }
        .task { await load() }
    }

    private func row(_ p: UniversePackage) -> some View {
        let state = Universe.state(of: p, installed: installed[p.name] ?? [])
        return HStack(alignment: .top, spacing: 10) {
            Button { detail = p.name } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.title).fontWeight(.medium)
                        Text(p.version).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Text(p.description).font(.callout).lineLimit(1)
                    if !p.authors.isEmpty { Text(p.authors.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    if let e = errors[p.name] { Text(e).font(.caption).foregroundStyle(.red) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { detail == p.name }, set: { if !$0 { detail = nil } }), arrowEdge: .trailing) { popover(p) }
            Button("Details", systemImage: "info.circle") { detail = p.name }
                .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Show details for \(p.title)")
            action(p, p.version, state)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func action(_ p: UniversePackage, _ version: String, _ state: PackageInstallState) -> some View {
        if installing.contains("\(p.name):\(version)") {
            ProgressView().controlSize(.small).frame(width: 70).accessibilityLabel("Installing \(p.title)")
        } else {
            switch state {
            case .installed: Button("Installed") {}.disabled(true).frame(minWidth: 70)
            case .update: Button("Update") { Task { await install(p, version) } }.frame(minWidth: 70)
            case .get: Button("Get") { Task { await install(p, version) } }.frame(minWidth: 70)
            }
        }
    }

    /// The package's detail: what the index knows about it, its actions, and every version.
    private func popover(_ p: UniversePackage) -> some View {
        let state = Universe.state(of: p, installed: installed[p.name] ?? [])
        let tooNew = Universe.needsNewerTypst(p, than: EngineVersions.typst)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                Text(p.version).foregroundStyle(.secondary).monospacedDigit()
                if p.isTemplate {
                    Text("Template").font(.caption.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule()).foregroundStyle(Color.accentColor)
                }
                Spacer()
                action(p, p.version, state)
            }
            if !p.description.isEmpty { Text(p.description).fixedSize(horizontal: false, vertical: true) }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                if !p.authors.isEmpty { detailRow("Authors", Text(p.authors.joined(separator: "\n"))) }
                if !p.license.isEmpty { detailRow("License", Text(p.license)) }
                if let c = p.compiler, !c.isEmpty {
                    detailRow("Requires", Label {
                        Text(tooNew ? "Typst \(c) (Typo has \(EngineVersions.typst))" : "Typst \(c) or newer")
                    } icon: {
                        Image(systemName: tooNew ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    }
                    .foregroundStyle(tooNew ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)))
                }
                if let d = p.updated { detailRow("Updated", Text(d.formatted(date: .abbreviated, time: .omitted))) }
                if !p.categories.isEmpty { detailRow("Categories", Text(p.categories.map(\.capitalized).joined(separator: ", "))) }
                if !p.keywords.isEmpty { detailRow("Keywords", Text(p.keywords.joined(separator: ", "))) }
            }
            .font(.callout)
            HStack(spacing: 8) {
                Button("Copy Import", systemImage: "doc.on.doc") { copy(p.importLine(p.version)) }
                    .help(p.importLine(p.version))
                Spacer()
                Link(destination: p.universeURL) { Label("Universe", systemImage: "safari") }
                if let url = p.repository { Link(destination: url) { Label("Repository", systemImage: "chevron.left.forwardslash.chevron.right") } }
                if let url = p.homepage, url != p.repository { Link(destination: url) { Label("Homepage", systemImage: "house") } }
            }
            .controlSize(.small)
            if p.allVersions.count > 1 {
                Divider()
                Text("All Versions").font(.headline)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(p.allVersions, id: \.self) { v in
                            HStack {
                                Text(v).monospacedDigit()
                                Spacer()
                                Button("Copy Import") { copy(p.importLine(v)) }.controlSize(.small)
                                action(p, v, (installed[p.name] ?? []).contains(v) ? .installed : .get)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .padding()
        .frame(width: 460)
    }

    private func detailRow(_ title: String, _ value: some View) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value.textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func load() async {
        all = await TypstRuntime.universePackages()
        updated = await TypstRuntime.shared.value.packageIndexUpdated
        loaded = true
    }

    private func check() async {
        checking = true
        indexError = nil
        do { _ = try await TypstRuntime.shared.value.refreshPackageIndex() }
        catch { indexError = "Couldn\u{2019}t check: \(error.localizedDescription)" }
        await load()
        checking = false
    }

    private func install(_ p: UniversePackage, _ version: String) async {
        let key = "\(p.name):\(version)"
        installing.insert(key)
        errors[p.name] = nil
        do { _ = try await TypstRuntime.shared.value.install(name: p.name, version: version) }
        catch { errors[p.name] = error.localizedDescription }
        await onInstalled()
        installing.remove(key)
    }
}

#Preview {
    UniverseBrowser(installed: [:]) {

    }
}
