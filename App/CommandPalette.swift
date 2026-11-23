import AppKit
import CoreText
import ImageIO
import SwiftUI
import TypoKit
import TypstEngine

/// The library's kinds (⇧⌘L), the tabs at the top of its panel.
enum LibraryKind: String, CaseIterable, Identifiable {
    case snippets, images, symbols, commands, fonts

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .snippets: "curlybraces"
        case .images: "photo"
        case .symbols: "character"
        case .fonts: "textformat"
        case .commands: "command"
        }
    }
}

/// The panel's shared state: the shown kind, the search and the selection. The panel's key handling drives it,
/// since a focused text field's editor swallows the arrow keys before SwiftUI's key handlers see them.
@MainActor @Observable final class LibraryModel {
    var kind: LibraryKind
    var query = ""
    var selection: String?
    var fontCategory = FontCategory.all
    var fontSample = ""
    /// The families chosen for a `font:` fallback list, in order.
    var fontPicks: [String] = []
    /// Off: the panel shrinks to just the list, like Xcode's compact Library; remembered across openings.
    var showsDetail = UserDefaults.standard.object(forKey: "libraryShowsDetail") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsDetail, forKey: "libraryShowsDetail")
            onDetailChange?()
        }
    }
    /// The panel resizes its window here.
    @ObservationIgnored var onDetailChange: (() -> Void)?
    /// The visible rows' ids in order, published by the view.
    @ObservationIgnored var rowIDs: [String] = []
    /// Bumped by Return; the view activates the selected row.
    private(set) var activations = 0

    init(kind: LibraryKind) { self.kind = kind }

    func step(_ delta: Int) {
        guard !rowIDs.isEmpty else { return }
        let current = selection.flatMap { rowIDs.firstIndex(of: $0) } ?? 0    // no selection shows the first row
        selection = rowIDs[min(max(current + delta, 0), rowIDs.count - 1)]
    }

    func cycleKind(_ delta: Int) {
        let all = LibraryKind.allCases
        let i = all.firstIndex(of: kind) ?? 0
        kind = all[(i + delta + all.count) % all.count]
    }

    func activate() { activations += 1 }
}

/// A floating window like Xcode's Library: can become key although it has no real title bar. Arrow keys, Return,
/// Esc, Tab and ⌘1–⌘5 are handled here, before the search field's editor gets them.
private final class PalettePanel: NSPanel {
    weak var model: LibraryModel?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let model, handle(event, model) { return }
        super.sendEvent(event)
    }

    private func handle(_ event: NSEvent, _ model: LibraryModel) -> Bool {
        // Input methods compose with Return and the arrows: leave them to the field while text is marked.
        if (firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, let n = event.charactersIgnoringModifiers.flatMap(Int.init), LibraryKind.allCases.indices.contains(n - 1) {
            model.kind = LibraryKind.allCases[n - 1]
            return true
        }
        guard mods.isDisjoint(with: [.command, .control, .option]) else { return false }
        switch event.keyCode {
        case 125: model.step(1)                              // ↓
        case 126: model.step(-1)                             // ↑
        case 36, 76: model.activate()                        // Return, Enter
        case 53: onCancel?()                                 // Esc
        case 48: model.cycleKind(mods.contains(.shift) ? -1 : 1)    // Tab, ⇧Tab
        default: return false
        }
        return true
    }
}

/// Owns the library's panel (⇧⌘L, ⇧⌘P): shown centered near the top of a project window, closed on Esc, on running an item or when it loses key.
@MainActor final class LibraryPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var parent: NSWindow?
    private var onClose: (() -> Void)?
    private var model: LibraryModel?
    static let size = CGSize(width: 720, height: 520)
    /// The list's width, and the whole panel's when the detail pane is hidden.
    static let listWidth: CGFloat = 302

    static func width(showsDetail: Bool) -> CGFloat { showsDetail ? size.width : listWidth }

    var isOpen: Bool { panel != nil }

    /// Shows the panel on `kind`; `onKind` hears tab switches made inside it.
    func show(_ kind: LibraryKind, commands: [AppCommand], project: Project, editor: EditorActions, over parent: NSWindow, onKind: @escaping (LibraryKind) -> Void, onClose: @escaping () -> Void) {
        close()
        self.parent = parent
        self.onClose = onClose
        let model = LibraryModel(kind: kind)
        self.model = model
        // Borderless and clear: the whole panel is one sheet of Liquid Glass, like the hover popup.
        let panel = PalettePanel(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.styleAsGlass()
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.delegate = self
        panel.model = model
        panel.onCancel = { [weak self] in self?.close() }
        let glass = NSGlassEffectView()
        glass.cornerRadius = 26
        glass.contentView = NSHostingView(rootView: LibraryView(model: model, commands: commands, project: project, editor: editor, onKind: onKind,
                                                                perform: { [weak self] in self?.run($0) }, cancel: { [weak self] in self?.close() }))
        panel.contentView = glass
        // Centered as if full width, so toggling the detail pane grows and shrinks to the right from a fixed left edge.
        let frame = parent.frame
        panel.setFrame(NSRect(x: frame.midX - Self.size.width / 2, y: frame.maxY - 70 - Self.size.height,
                              width: Self.width(showsDetail: model.showsDetail), height: Self.size.height), display: false)
        model.onDetailChange = { [weak panel, weak model] in
            guard let panel, let model else { return }
            var f = panel.frame
            f.size.width = Self.width(showsDetail: model.showsDetail)
            panel.setFrame(f, display: true, animate: true)
        }
        // Not a child window: AppKit drags child windows itself to keep their offset to the parent, which lags. It closes
        // when it loses key, so the parent never moves under it anyway.
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    /// Switches the open panel to another tab.
    func setKind(_ kind: LibraryKind) { model?.kind = kind }

    /// Removes the panel and tells the owner; safe to call when nothing is shown.
    func close() {
        guard let panel else { return }
        self.panel = nil
        self.model = nil
        panel.delegate = nil
        panel.orderOut(nil)
        let done = onClose
        onClose = nil
        done?()
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    /// Closes, and performs `action` once the parent window is key again, so its own sheets and the editor find a sane responder chain.
    private func run(_ action: @escaping @MainActor () -> Void) {
        let parent = parent
        close()
        parent?.makeKeyAndOrderFront(nil)
        Task { @MainActor in action() }
    }
}

/// One row of any kind's list.
private struct LibraryRow: Identifiable {
    enum Tile { case symbol(String), character(String), thumbnail(URL) }
    let id: String
    let title: String
    var subtitle: String? = nil
    let tile: Tile
    /// The outlined tag at the row's end, like Xcode's "User": a shortcut or a category.
    var badge: String? = nil
    var checked = false
    /// Set the title in this family.
    var font: FontFamily? = nil
}

private typealias LibrarySection = (title: String, rows: [LibraryRow])

/// The library's content: search field, kind tabs, grouped list and a detail pane.
struct LibraryView: View {
    let model: LibraryModel
    let commands: [AppCommand]
    let project: Project
    let editor: EditorActions
    let onKind: (LibraryKind) -> Void
    /// Closes the panel, then runs the action on the parent window.
    let perform: (@escaping @MainActor () -> Void) -> Void
    let cancel: () -> Void
    /// Recently run command ids, newest first, newline-joined.
    @AppStorage("commandPaletteRecent") private var recentStorage = ""
    @AppStorage("librarySnippetRecent") private var snippetRecentStorage = ""
    @State private var recentSymbols = RecentSymbols()
    @State private var fonts: [FontFamily] = []
    @State private var projectFontFiles: [String: CTFontDescriptor] = [:]
    @FocusState private var searchFocused: Bool

    private static let menus = ["File", "Format", "View", "Navigate", "Export", "Window"]
    private static let symbolLimit = 500

    private var kind: LibraryKind { model.kind }
    private var query: String { model.query }
    private var selection: String? {
        get { model.selection }
        nonmutating set { model.selection = newValue }
    }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private func recent(_ storage: String) -> [String] { storage.split(separator: "\n").map(String.init) }

    /// The editor to insert into: the focused one, if it shows a Typst file.
    private var target: EditorView.Coordinator? {
        guard let c = editor.editor, c.buffer?.isTypst == true else { return nil }
        return c
    }

    private var sections: [LibrarySection] {
        switch kind {
        case .commands: commandSections
        case .snippets: snippetSections
        case .images: imageSections
        case .symbols: symbolSections
        case .fonts: fontSections
        }
    }

    private var fontSections: [LibrarySection] {
        let found = FontCatalog.filter(fonts, query: query, category: model.fontCategory)
        let rows = found.map { f in
            let tags = [f.source == .project ? "Project" : f.source == .builtin ? "Built-in" : nil, f.isMonospaced ? "Mono" : nil].compactMap { $0 }
            return LibraryRow(id: f.name, title: f.name, subtitle: (f.weights.map(FontCatalog.weightName) + (f.hasItalic ? ["Italic"] : [])).joined(separator: " · "),
                       tile: .character("Aa"), badge: tags.isEmpty ? nil : tags.joined(separator: " · "),
                       checked: model.fontPicks.contains(f.name), font: f)
        }
        return rows.isEmpty ? [] : [(isSearching ? "Results" : "Fonts", rows)]
    }

    private var commandSections: [LibrarySection] {
        func row(_ c: AppCommand) -> LibraryRow { LibraryRow(id: c.id, title: c.title, tile: .symbol(c.systemImage), badge: c.shortcut?.display, checked: c.isOn == true) }
        let pool = commands.filter(\.isEnabled)
        let recent = recent(recentStorage)
        if !isSearching {
            var result: [LibrarySection] = []
            let recents = recent.compactMap { id in pool.first { $0.id == id } }.prefix(5)
            if !recents.isEmpty { result.append(("Recently Used", recents.map(row))) }
            for menu in Self.menus {
                let items = pool.filter { $0.menu == menu }
                if !items.isEmpty { result.append((menu, items.map(row))) }
            }
            return result
        }
        let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ranked = CommandPalette.filter(pool.map(\.entry), query: query, recent: recent).compactMap { byID[$0.id] }
        return ranked.isEmpty ? [] : [("Results", ranked.map(row))]
    }

    private var snippetSections: [LibrarySection] {
        func row(_ s: LibrarySnippet) -> LibraryRow { LibraryRow(id: s.id, title: s.title, tile: .symbol(s.symbol), badge: s.category == UserSnippetStore.category ? "User" : s.isBlock ? "Block" : "Inline") }
        let recent = recent(snippetRecentStorage)
        let user = userSnippets
        if isSearching {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            let mine = user.filter { $0.title.lowercased().contains(q) || $0.summary.lowercased().contains(q) || $0.plainText.lowercased().contains(q) }
            let found = mine + LibrarySnippets.filter(query, recent: recent)
            return found.isEmpty ? [] : [("Results", found.map(row))]
        }
        var result: [LibrarySection] = []
        if !user.isEmpty { result.append((UserSnippetStore.category, user.map(row))) }
        let recents = recent.compactMap { id in snippet(id) }.prefix(5)
        if !recents.isEmpty { result.append(("Recently Used", recents.map(row))) }
        for category in LibrarySnippets.categories {
            result.append((category, LibrarySnippets.all.filter { $0.category == category }.map(row)))
        }
        return result
    }

    private var userSnippets: [LibrarySnippet] { UserSnippetStore.shared.snippets.map(\.librarySnippet) }
    private func snippet(_ id: String) -> LibrarySnippet? { userSnippets.first { $0.id == id } ?? LibrarySnippets.all.first { $0.id == id } }

    private var imageSections: [LibrarySection] {
        let images = project.allFiles.filter { FileKind(path: $0.raw) == .image || ImageInsert.isImage($0.raw) }
        let found = QuickOpen.filter(paths: images, query: query)
        let rows = found.map { path in
            let folder = (path.raw as NSString).deletingLastPathComponent
            return LibraryRow(id: path.raw, title: (path.raw as NSString).lastPathComponent, subtitle: folder.isEmpty ? nil : folder, tile: .thumbnail(project.url(for: path)))
        }
        return rows.isEmpty ? [] : [(isSearching ? "Results" : "Images", rows)]
    }

    private var symbolSections: [LibrarySection] {
        let found = SymbolCatalog.filter(SymbolCatalog.all, query: query, recent: recentSymbols.ids)
        let shown = isSearching ? found : Array(found.prefix(Self.symbolLimit))
        let rows = shown.map { LibraryRow(id: $0.id, title: $0.name, subtitle: $0.id, tile: .character($0.text)) }
        return rows.isEmpty ? [] : [(isSearching ? "Results" : "Symbols", rows)]
    }

    /// Rows in display order; a row may appear twice (Recently Used and its group), selection follows the first.
    private func flat(_ sections: [LibrarySection]) -> [LibraryRow] {
        var seen = Set<String>()
        return sections.flatMap(\.rows).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        let sections = sections
        let rows = flat(sections)
        let selected = rows.first { $0.id == selection } ?? rows.first
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            if kind == .fonts { fontFilter }
            Divider()
            HStack(spacing: 0) {
                list(sections, selected: selected).frame(width: LibraryPanel.listWidth)
                if model.showsDetail {
                    Divider()
                    detail(selected)
                }
            }
            // Only the lists give way: taller content (the Fonts filter row, a long detail) used to push the header out the top.
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(width: LibraryPanel.width(showsDetail: model.showsDetail), height: LibraryPanel.size.height, alignment: .top)    // no background: the panel's glass shows through
        // The panel's window is not key yet on the first pass: focus on the next turn.
        .task { searchFocused = true }
        .onChange(of: rows.map(\.id), initial: true) { _, ids in model.rowIDs = ids }
        .onChange(of: model.activations) { if let selected = flat(self.sections).first(where: { $0.id == selection }) ?? flat(self.sections).first { activate(selected.id) } }
        .task(id: kind) {
            guard kind == .fonts, fonts.isEmpty else { return }
            (fonts, projectFontFiles) = await FontScanner.load(project: project)
        }
        .onChange(of: query) { selection = nil }
        .onChange(of: kind) { _, new in
            model.query = ""
            selection = nil
            onKind(new)
            searchFocused = true
        }
    }

    /// Xcode's Library header: filter glyph, a large borderless search field, the detail toggle.
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 18, weight: .light)).foregroundStyle(.secondary)
            TextField(kind.title, text: Bindable(model).query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($searchFocused)
            Button("Details", systemImage: model.showsDetail ? "rectangle.righthalf.inset.filled" : "rectangle") { model.showsDetail.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                .help(model.showsDetail ? "Hide Details" : "Show Details")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Icon-only kind tabs as glass capsules; the active one is tinted with the accent color.
    private var tabBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Array(LibraryKind.allCases.enumerated()), id: \.element) { i, k in
                    let on = kind == k
                    Button { model.kind = k } label: {
                        Image(systemName: k.systemImage).font(.system(size: 14, weight: .medium))
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .frame(width: 40, height: 28)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .selectableGlassCapsule(on)
                    .help("\(k.title) (⌘\(i + 1))")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var fontFilter: some View {
        Picker("Category", selection: Bindable(model).fontCategory) {
            ForEach(FontCategory.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.bottom, 8)
        .onChange(of: model.fontCategory) { selection = nil }
    }

    private func list(_ sections: [LibrarySection], selected: LibraryRow?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if sections.isEmpty {
                    Text(kind == .images && !isSearching ? "No Images in This Project" : "No Matching \(kind.title)").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    // One flat ForEach: a lazy stack resolves `scrollTo` only through its ForEach's identities, so rows
                    // nested in per-section ForEaches that are not on screen yet could not be scrolled to.
                    // Headers scroll with their rows: pinned ones would need an opaque bar over the glass.
                    LazyVStack(spacing: 0) {
                        ForEach(Self.items(sections), id: \.id) { item in
                            if let row = item.row {
                                rowView(row, isSelected: row.id == selected?.id)
                            } else {
                                Text(item.header).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .onChange(of: selection) { _, id in
                guard let id, let section = sections.first(where: { $0.rows.contains { $0.id == id } }) else { return }
                // No animation: with a held arrow key each step restarted it, so the list lagged behind the selection.
                proxy.scrollTo(section.title + "/" + id)
            }
        }
    }

    /// The list's lines in order: each section's header ("#title") followed by its rows ("title/rowID").
    private static func items(_ sections: [LibrarySection]) -> [(id: String, header: String, row: LibraryRow?)] {
        sections.flatMap { s in [("#" + s.title, s.title, nil)] + s.rows.map { (s.title + "/" + $0.id, s.title, $0) } }
    }

    private func rowView(_ row: LibraryRow, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            tile(row.tile)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(row.font.map { fontSwiftUI($0, descriptors: projectFontFiles, size: 14) } ?? .system(size: 13)).lineLimit(1)
                if let subtitle = row.subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
            }
            if row.checked { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            if let badge = row.badge {
                Text(badge).font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.7), lineWidth: 1))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .glassEffect(isSelected ? .regular.tint(.accentColor.opacity(0.35)) : .identity, in: .rect(cornerRadius: 12))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { activate(row.id) }
        .onTapGesture {
            if kind == .fonts, NSEvent.modifierFlags.contains(.command) { toggleFontPick(row.id) }
            selection = row.id
        }
        .onDrag { dragProvider(row.id) ?? NSItemProvider() }
    }

    @ViewBuilder private func tile(_ tile: LibraryRow.Tile) -> some View {
        switch tile {
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .systemGray)))
        case .character(let text):
            Text(text).font(.system(size: 19)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .systemGray)))
        case .thumbnail(let url):
            LibraryImage(url: url, fill: true).frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 7))
        }
    }

    // MARK: Detail

    @ViewBuilder private func detail(_ selected: LibraryRow?) -> some View {
        if let selected, let content = detailContent(selected) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
        } else if kind == .images, !isSearching, selected == nil {
            VStack(spacing: 12) {
                Text("No Images in This Project").font(.title3).foregroundStyle(.secondary)
                Button("Add Image…") { addImages() }.buttonStyle(.glass).disabled(target == nil)
                if target == nil { notTypst }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }

    private var notTypst: some View { Text("Open a Typst file to insert.").font(.callout).foregroundStyle(.secondary) }

    private func insertBar(_ title: String, id: String, extra: AnyView? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if kind != .commands, target == nil { notTypst }
            HStack {
                extra
                Spacer()
                Button(title) { activate(id) }.buttonStyle(.glassProminent).controlSize(.large).disabled(kind != .commands && target == nil)
            }
        }
    }

    @ViewBuilder private func detailHeader(_ title: String, _ summary: String) -> some View {
        Text(title).font(.system(size: 17, weight: .bold))
        Text(summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func detailContent(_ row: LibraryRow) -> AnyView? {
        switch kind {
        case .commands:
            guard let command = commands.first(where: { $0.id == row.id }) else { return nil }
            return AnyView(VStack(alignment: .leading, spacing: 12) {
                detailHeader(command.title, command.help)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow { label("Menu"); Text(command.menu) }
                    GridRow { label("Shortcut"); Text(command.shortcut?.display ?? "None") }
                    if let isOn = command.isOn { GridRow { label("State"); Text(isOn ? "On" : "Off") } }
                }
                Spacer()
                insertBar("Run", id: row.id)
            })
        case .snippets:
            guard let s = snippet(row.id) else { return nil }
            let lines = s.plainText.split(separator: "\n", omittingEmptySubsequences: false).count
            return AnyView(VStack(alignment: .leading, spacing: 12) {
                detailHeader(s.title, s.summary)
                ScrollView([.vertical, .horizontal]) {
                    Text(s.plainText).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(180, CGFloat(lines) * 17 + 18))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                    GridRow { label("Category"); Text(s.category) }
                    GridRow { label("Placement"); Text(s.isBlock ? "Own line" : "Inline") }
                }
                Spacer()
                insertBar("Insert", id: row.id, extra: s.category == UserSnippetStore.category ? AnyView(Button("Edit…") { editUserSnippet(s.id) }.buttonStyle(.glass)) : nil)
            })
        case .images:
            guard case .thumbnail(let url) = row.tile else { return nil }
            let size = LibraryImage.pixelSize(url)
            return AnyView(VStack(alignment: .leading, spacing: 12) {
                LibraryImage(url: url, fill: false).frame(maxWidth: .infinity, maxHeight: 220)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                Text(row.id).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                if let size { Text("\(Int(size.width)) × \(Int(size.height)) px").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                insertBar("Insert", id: row.id, extra: AnyView(Button("Add Image…") { addImages() }.buttonStyle(.glass).disabled(target == nil)))
            })
        case .fonts:
            guard let family = row.font else { return nil }
            let names = fontNames(selected: row.id)
            return AnyView(FontDetail(family: family, descriptors: projectFontFiles, sample: Bindable(model).fontSample, picks: model.fontPicks, names: names,
                                      togglePick: { toggleFontPick(row.id) },
                                      insertBar: AnyView(insertBar(names.count > 1 ? "Insert List" : "Insert", id: row.id))))
        case .symbols:
            guard let s = SymbolCatalog.all.first(where: { $0.id == row.id }) else { return nil }
            let mode = target?.buffer?.mode(at: target?.textView?.selectedRange().location ?? 0) ?? .markup
            return AnyView(VStack(alignment: .leading, spacing: 12) {
                Text(s.text).font(.system(size: 64)).frame(maxWidth: .infinity, minHeight: 90).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                Text(s.name).font(.system(size: 17, weight: .bold))
                Text(SymbolCatalog.insertion(for: s, mode: mode)).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                insertBar("Insert", id: row.id)
            })
        }
    }

    /// The picked fallback list, or just the selected family.
    private func fontNames(selected: String) -> [String] { model.fontPicks.isEmpty ? [selected] : model.fontPicks }

    private func toggleFontPick(_ name: String) {
        if let i = model.fontPicks.firstIndex(of: name) { model.fontPicks.remove(at: i) } else { model.fontPicks.append(name) }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    // MARK: Actions

    /// Remembers the item, closes the panel and runs or inserts it.
    private func activate(_ id: String) {
        switch kind {
        case .commands:
            guard let command = commands.first(where: { $0.id == id }) else { return }
            recentStorage = CommandPalette.remember(id, in: recent(recentStorage)).joined(separator: "\n")
            perform(command.action)
        case .snippets:
            guard let s = snippet(id), let target else { return }
            snippetRecentStorage = CommandPalette.remember(id, in: recent(snippetRecentStorage)).joined(separator: "\n")
            perform { target.insertLibrary(s) }
        case .images:
            guard let path = RelPath(id), let target else { return }
            let url = project.url(for: path)
            perform { target.insertLibraryImage(url) }
        case .fonts:
            guard let target else { return }
            let names = fontNames(selected: id)
            perform { target.insertFonts(names) }
        case .symbols:
            guard let s = SymbolCatalog.all.first(where: { $0.id == id }), let target else { return }
            recentSymbols.use(s)
            perform { target.insertText { SymbolCatalog.insertion(for: s, mode: $0) } }
        }
    }

    /// Opens the Settings on the Snippets pane with the snippet selected.
    private func editUserSnippet(_ id: String) {
        UserDefaults.standard.set("snippets", forKey: SettingsKey.tab)
        UserDefaults.standard.set(id, forKey: SettingsKey.editedSnippet)
        perform { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
    }

    private func addImages() {
        guard let target else { return }
        perform {
            let open = NSOpenPanel()
            open.allowedContentTypes = [.image, .pdf]
            open.allowsMultipleSelection = true
            open.prompt = "Add"
            guard open.runModal() == .OK, !open.urls.isEmpty else { return }
            target.insertImages(.files(open.urls), replacing: target.textView?.selectedRange() ?? NSRange(location: 0, length: 0))
        }
    }

    /// What dragging a row carries: snippet text, an image's file URL (the editor's image drop handles it), a symbol's markup code.
    private func dragProvider(_ id: String) -> NSItemProvider? {
        switch kind {
        case .commands: nil
        case .fonts: NSItemProvider(object: FontCatalog.setRule([id]) as NSString)
        case .snippets: snippet(id).map { NSItemProvider(object: $0.plainText as NSString) }
        case .images: RelPath(id).flatMap { NSItemProvider(contentsOf: project.url(for: $0)) }
        case .symbols: SymbolCatalog.all.first { $0.id == id }.map { NSItemProvider(object: SymbolCatalog.insertion(for: $0, mode: .markup) as NSString) }
        }
    }
}

/// An image file's picture, loaded off the first render: aspect fill for tiles, aspect fit for previews.
private struct LibraryImage: View {
    let url: URL
    let fill: Bool
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .task(id: url) { image = NSImage(contentsOf: url) }
    }

    /// Pixel size from the file header; nil when unreadable (PDF and SVG have none).
    static func pixelSize(_ url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }
}

extension KeyboardShortcut {
    /// The menu notation, e.g. "⇧⌘P": modifiers in the order ⌃⌥⇧⌘, then the key.
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        let special: [KeyEquivalent: String] = [.return: "↩", .delete: "⌫", .leftArrow: "←", .rightArrow: "→", .upArrow: "↑", .downArrow: "↓",
                                                .escape: "⎋", .tab: "⇥", .space: "␣"]
        return s + (special[key] ?? String(key.character).uppercased())
    }
}
