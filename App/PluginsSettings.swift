import SwiftUI
import TypoAssistant

/// Settings › Intelligence › Plug-ins: the plug-ins agents get (Typo's skills and the user's), and adding skills
/// from other tools.
struct PluginsSettings: View {
    @Environment(SettingsNavigation.self) private var nav
    private let store = SkillStore.shared
    @State private var query = ""
    @State private var adding = false

    var body: some View {
        Form {
            SettingsHeaderCard(symbol: "puzzlepiece.extension.fill", title: "Plug-ins",
                               text: "Plug-ins bring skills to agents: instructions for tasks such as Typst tables or accessible PDFs. Claude Code loads them when a conversation starts.")
            Section {
                if query.isEmpty {
                    if SkillStore.bundled != nil {
                        plugin("Typo", "Typo's Typst skills, \(count(store.bundledSkills))", symbol: "rosette")
                    }
                    plugin("My Skills", store.userSkills.isEmpty ? "Skills you write or import" : "Your own skills, \(count(store.userSkills))", symbol: "person.crop.circle")
                } else if matches.isEmpty {
                    Text("No Results for “\(query)”").foregroundStyle(.secondary).frame(maxWidth: .infinity)
                } else {
                    ForEach(matches, id: \.name) { s in
                        SettingsPageRow(title: s.name, subtitle: s.description, open: openSkills)
                    }
                }
            } header: {
                // In the page, not .searchable: a toolbar search field left the window title under the Back/Forward capsule after this page closed.
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search Plug-ins", text: $query).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.quaternary.opacity(0.6), in: Capsule())
                    .frame(width: 220)
                }
            } footer: {
                HStack { Spacer(); Button("Add Plug-in…") { adding = true } }
            }
        }
        .pane()
        .onAppear { store.reload() }
        .sheet(isPresented: $adding) { AddPluginSheet() }
    }

    private var matches: [Skill] {
        (store.bundledSkills + store.userSkills).filter { $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }

    private func count(_ skills: [Skill]) -> String { skills.count == 1 ? "1 skill" : "\(skills.count) skills" }

    private func openSkills() { nav.page = SettingsSubpage(tab: .intelligence, id: IntelligenceSettings.Page.skills.rawValue, title: "Skills") }

    private func plugin(_ title: String, _ subtitle: String, symbol: String) -> some View {
        Button(action: openSkills) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 7))
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

/// "Add Plug-in…": where to take skills from, then which of them to copy into My Skills.
struct AddPluginSheet: View {
    enum Source: String, CaseIterable, Identifiable {
        case claude = "Import from Claude Code", codex = "Import from Codex", gemini = "Import from Gemini", file = "Add from file", url = "Add from URL"
        var id: Self { self }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var source = Source.claude
    /// The skills found, once a source is chosen; nil on the first step.
    @State private var found: [ImportCandidate]?
    @State private var unavailable: String?

    var body: some View {
        if let found {
            SkillImportList(candidates: found, back: { self.found = nil }, done: { dismiss() })
        } else {
            choose
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30) }
                .buttonStyle(.bordered).buttonBorderShape(.circle).keyboardShortcut(.cancelAction).accessibilityLabel("Close")
                .padding(16)
            VStack(alignment: .leading, spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Add Plug-in").font(.system(size: 20, weight: .bold))
                Text("Plug-ins extend Typo's agents with skills. Bring the skills you already use with other coding tools, or add a skill folder.")
                    .font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup).labelsHidden()
                .padding(.leading, 20).padding(.top, 8)
                if let unavailable { Text(unavailable).font(.callout).foregroundStyle(.secondary).padding(.leading, 20) }
            }
            .padding(.horizontal, 48)
            Spacer()
            HStack {
                Spacer()
                Button("Continue") { next() }.keyboardShortcut(.defaultAction).controlSize(.large)
            }
            .padding(20)
        }
        .frame(width: 460, height: 480)
        .onChange(of: source) { unavailable = nil }
    }

    private func next() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch source {
        case .claude: found = ImportCandidate.scan([home.appending(path: ".claude/skills"), home.appending(path: ".claude/plugins")])
        case .codex: found = ImportCandidate.scan([home.appending(path: ".codex/skills")])
        case .gemini, .url: unavailable = "Not available yet."
        case .file:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.message = "Choose a skill folder (with a SKILL.md) or a folder of skills."
            if panel.runModal() == .OK, let url = panel.url { found = ImportCandidate.scan([url]) }
        }
    }
}

/// A skill folder found for import.
struct ImportCandidate: Identifiable {
    var id: URL { folder }
    let folder: URL
    let skill: Skill

    /// The skills under `roots`, one per name (the first found wins).
    static func scan(_ roots: [URL]) -> [ImportCandidate] {
        var seen = Set<String>()
        return roots.flatMap(SkillPlugin.skillFolders).compactMap { f in
            guard let text = try? String(contentsOf: f.appending(path: "SKILL.md"), encoding: .utf8) else { return nil }
            let skill = Skill.parse(text, fallbackName: f.lastPathComponent)
            return seen.insert(skill.name).inserted ? ImportCandidate(folder: f, skill: skill) : nil
        }
    }
}

/// The skills found, each with a checkbox; the checked ones are copied into My Skills.
struct SkillImportList: View {
    let candidates: [ImportCandidate]
    let back: () -> Void
    let done: () -> Void
    private let store = SkillStore.shared
    @State private var checked: Set<URL> = []
    @State private var error: String?

    /// The slug a candidate gets in My Skills.
    private func slug(_ c: ImportCandidate) -> String {
        Skill.isValidName(c.skill.name) ? c.skill.name : Skill.slug(c.skill.name)
    }
    private func added(_ c: ImportCandidate) -> Bool { store.names.contains(slug(c)) }
    private var open: [ImportCandidate] { candidates.filter { !added($0) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import Skills").font(.headline)
                Spacer()
                if !open.isEmpty {
                    Button(checked.count == open.count ? "Deselect All" : "Select All") {
                        checked = checked.count == open.count ? [] : Set(open.map(\.folder))
                    }
                }
            }
            .padding(16)
            Divider()
            if candidates.isEmpty {
                ContentUnavailableView("No Skills Found", systemImage: "rosette", description: Text("There are no skill folders with a SKILL.md there."))
            } else {
                List(candidates) { c in
                    let isAdded = added(c)
                    Toggle(isOn: Binding(get: { isAdded || checked.contains(c.folder) },
                                         set: { if $0 { checked.insert(c.folder) } else { checked.remove(c.folder) } })) {
                        HStack(spacing: 10) {
                            Image(systemName: "rosette").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 26, height: 26).background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(slug(c))
                                    if isAdded { Text("Already added").font(.callout).foregroundStyle(.tertiary) }
                                }
                                Text(c.skill.description.isEmpty ? c.folder.path : c.skill.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(isAdded)
                }
            }
            Divider()
            HStack {
                if let error { Text(error).font(.callout).foregroundStyle(.red).lineLimit(2) }
                Spacer()
                Button("Back", action: back)
                Button(checked.count == 1 ? "Import 1 Skill" : "Import \(checked.count) Skills") { importChecked() }
                    .keyboardShortcut(.defaultAction).disabled(checked.isEmpty)
            }
            .controlSize(.large)
            .padding(16)
        }
        .frame(width: 520, height: 480)
    }

    private func importChecked() {
        do {
            for c in candidates where checked.contains(c.folder) {
                try SkillStore.user.importSkill(from: c.folder, as: slug(c))
            }
            store.reload()
            done()
        } catch {
            self.error = error.localizedDescription
            store.reload()
        }
    }
}
