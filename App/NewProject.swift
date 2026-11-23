import SwiftUI
import TypoKit
import TypstEngine

extension ProjectOpener {
    /// Asks where the new project folder goes; nil when cancelled.
    static func askForNewFolder(named name: String, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.message = message
        panel.prompt = "Create"
        panel.nameFieldLabel = "Project Name:"
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// A new folder with an empty main.typ. An existing folder (Save panel "Replace") is an error, never merged.
    @discardableResult func newProject() -> Bool {
        guard let folder = Self.askForNewFolder(named: "Untitled", message: "Choose a name and location for the new project.") else { return false }
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let paper = ["US", "CA", "MX"].contains(Locale.current.region?.identifier ?? "") ? "us-letter" : "a4"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try "#set page(paper: \"\(paper)\")\n#set text(lang: \"\(lang)\")\n\n"
                .write(to: folder.appending(path: "main.typ"), atomically: true, encoding: .utf8)
            openWindow(value: try recents.register(root: folder, main: RelPath("main.typ")!))
            return true
        } catch {
            showAlert("Could Not Create \"\(folder.lastPathComponent)\"", error.localizedDescription)
            return false
        }
    }
}

/// Xcode-style template chooser over all Typst Universe templates: categories, search, a page-preview grid.
struct TemplateChooser: View {
    @Environment(RecentProjects.self) private var recents
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [PackageTemplate]?    // nil while loading
    @State private var category = ""                     // "" is all templates
    @State private var query = ""
    @State private var selection: PackageTemplate.ID?
    @State private var creating: PackageTemplate?

    var body: some View {
        NavigationSplitView {
            List(selection: $category) {
                Label("All Templates", systemImage: "square.grid.2x2").tag("")
                Section("Categories") {
                    ForEach(categories, id: \.self) { c in
                        Label(Self.title(c), systemImage: Self.symbol(c)).tag(c)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            grid
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search Templates")
        .navigationTitle("Choose a Template")
        .task { await load() }
    }

    @ViewBuilder private var grid: some View {
        if let templates {
            if templates.isEmpty {
                ContentUnavailableView {
                    Label("Templates Unavailable", systemImage: "wifi.slash")
                } description: {
                    Text("The Typst Universe template list could not be loaded.")
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)], spacing: 20) {
                        ForEach(shown) { t in
                            TemplateCard(template: t, selected: selection == t.id)
                                .onTapGesture(count: 2) { selection = t.id; create(t) }
                                .onTapGesture { selection = t.id }
                        }
                    }
                    .padding(20)
                }
            }
        } else {
            ProgressView("Loading Templates…").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let creating {
                ProgressView().controlSize(.small)
                Text("Downloading \(creating.name)…").foregroundStyle(.secondary)
            } else if let t = selected {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(t.name) \(t.version)").fontWeight(.medium)
                    if !t.authors.isEmpty {
                        Text(t.authors.map(Self.plainAuthor).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            Spacer()
            SheetButtons(ok: "Create…", disabled: selected == nil || creating != nil, cancel: { dismiss() }) { if let selected { create(selected) } }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selected: PackageTemplate? { templates?.first { $0.id == selection } }

    private var categories: [String] {
        let present = Set((templates ?? []).flatMap(\.categories))
        return Self.order.filter(present.contains) + present.subtracting(Self.order).sorted()
    }

    private var shown: [PackageTemplate] {
        (templates ?? []).filter { t in
            (category.isEmpty || t.categories.contains(category))
                && (query.isEmpty || [t.name, t.description, t.authors.joined(separator: " ")]
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private func load() async {
        templates = nil
        templates = await TypstRuntime.shared.value.templates()
    }

    private func create(_ template: PackageTemplate) {
        guard creating == nil,
              let folder = ProjectOpener.askForNewFolder(named: template.name, message: "Choose a name and location for the new project from \(template.name).")
        else { return }
        creating = template
        Task {
            defer { creating = nil }
            do {
                let main = try await TypstRuntime.shared.value.createProject(from: template, at: folder)
                openWindow(value: try recents.register(root: folder, main: main))
                dismissWindow(id: "welcome")
                dismiss()
            } catch {
                showAlert("Could Not Create \"\(folder.lastPathComponent)\"", error.localizedDescription)
            }
        }
    }

    private static let order = ["paper", "thesis", "report", "book", "cv", "presentation", "poster", "flyer", "office", "fun"]

    private static func title(_ category: String) -> String {
        category == "cv" ? "CV" : category.prefix(1).uppercased() + category.dropFirst()
    }

    private static func symbol(_ category: String) -> String {
        switch category {
        case "paper": "doc.text"
        case "thesis": "graduationcap"
        case "report": "doc.richtext"
        case "book": "book.closed"
        case "cv": "person.text.rectangle"
        case "presentation": "play.rectangle"
        case "poster": "rectangle.portrait"
        case "flyer": "newspaper"
        case "office": "briefcase"
        case "fun": "face.smiling"
        default: "tag"
        }
    }

    /// Universe authors read "Name <https://…>"; the footer shows the name.
    private static func plainAuthor(_ author: String) -> String {
        author.split(separator: "<").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? author
    }
}

private struct TemplateCard: View {
    let template: PackageTemplate
    let selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            AsyncImage(url: template.thumbnailURL) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 3))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(.background.secondary)
                        .aspectRatio(210 / 297, contentMode: .fit)
                        .overlay {
                            if phase.error == nil { ProgressView().controlSize(.small) }
                            else { Image(systemName: "doc.text").font(.largeTitle).foregroundStyle(.tertiary) }
                        }
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
            }
            .frame(height: 190)
            .padding(6)
            .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 8))
            VStack(spacing: 2) {
                Text(template.name)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(selected ? .white : .primary)
                    .background(selected ? Color.accentColor : .clear, in: .capsule)
                Text(template.description).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .lineLimit(1)
        }
        .contentShape(.rect)
        .help(template.description)
    }
}
