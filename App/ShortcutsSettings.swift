import AppKit
import SwiftUI
import TypoKit
import TypstEngine

extension SettingsKey {
    static let shortcutOverrides = "shortcutOverrides"   // before sets: read once, to migrate
    static let shortcutSets = "shortcutSets"
    static let adaptShortcuts = "adaptShortcutsToKeyboard"
}

private let namedKeys: [(ShortcutSpec.Named, KeyEquivalent)] = [
    (.leftArrow, .leftArrow), (.rightArrow, .rightArrow), (.upArrow, .upArrow), (.downArrow, .downArrow),
    (.return, .return), (.tab, .tab), (.space, .space), (.delete, .delete), (.forwardDelete, .deleteForward), (.escape, .escape),
    (.home, .home), (.end, .end), (.pageUp, .pageUp), (.pageDown, .pageDown),
] + ShortcutSpec.Named.allCases.filter(\.isFunctionKey).enumerated().map { i, n in   // F1 is U+F704, as in NSF1FunctionKey
    (n, KeyEquivalent(Character(UnicodeScalar(0xF704 + UInt32(i))!)))
}

extension ShortcutSpec {
    init?(_ s: KeyboardShortcut) {
        var m: Modifiers = []
        for (a, b) in [(EventModifiers.shift, Modifiers.shift), (.control, .control), (.option, .option), (.command, .command)] where s.modifiers.contains(a) { m.insert(b) }
        if let n = namedKeys.first(where: { $0.1 == s.key })?.0 { self.init(.named(n), m) } else { self.init(s.key.character, m) }
    }

    var keyboardShortcut: KeyboardShortcut {
        var m: EventModifiers = []
        for (a, b) in [(EventModifiers.shift, Modifiers.shift), (.control, .control), (.option, .option), (.command, .command)] where modifiers.contains(b) { m.insert(a) }
        switch key {
        case .named(let n): return KeyboardShortcut(namedKeys.first { $0.0 == n }!.1, modifiers: m)
        case .character(let c): return KeyboardShortcut(KeyEquivalent(c.first ?? " "), modifiers: m)
        }
    }

    /// The shortcut a key press makes (named keys by key code); nil for a bare modifier or a key without a character.
    @MainActor static func from(_ event: NSEvent) -> ShortcutSpec? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        let codes: [UInt16: Named] = [123: .leftArrow, 124: .rightArrow, 125: .downArrow, 126: .upArrow, 36: .return, 76: .return, 48: .tab, 49: .space,
                                      51: .delete, 117: .forwardDelete, 115: .home, 119: .end, 116: .pageUp, 121: .pageDown,
                                      122: .f1, 120: .f2, 99: .f3, 118: .f4, 96: .f5, 97: .f6, 98: .f7, 100: .f8, 101: .f9, 109: .f10, 103: .f11, 111: .f12]
        if let n = codes[event.keyCode] { return ShortcutSpec(.named(n), m) }
        // Unshifted, so ⇧⌘[ records "[" with Shift, which is what SwiftUI matches.
        guard let c = event.characters(byApplyingModifiers: [])?.lowercased().first, !c.isNewline else { return nil }
        return ShortcutSpec(c, m)
    }
}

/// The user's shortcut sets, persisted as JSON; menus and the palette resolve through the selected set.
@MainActor final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    @Published private(set) var sets: ShortcutSets
    /// Menu shortcuts follow the current input method (`KeyboardShortcut.Localization.automatic`).
    @Published var adaptsToKeyboard: Bool { didSet { UserDefaults.standard.set(adaptsToKeyboard, forKey: SettingsKey.adaptShortcuts) } }

    var overrides: ShortcutOverrides { sets.current }

    private init() {
        let d = UserDefaults.standard
        adaptsToKeyboard = d.object(forKey: SettingsKey.adaptShortcuts) as? Bool ?? true
        let decoder = JSONDecoder()
        sets = d.data(forKey: SettingsKey.shortcutSets).flatMap { try? decoder.decode(ShortcutSets.self, from: $0) }
            ?? ShortcutSets(migrating: d.data(forKey: SettingsKey.shortcutOverrides).flatMap { try? decoder.decode(ShortcutOverrides.self, from: $0) } ?? ShortcutOverrides())
        // The old single Jump to Definition setting is read once, then ignored.
        if let old = d.string(forKey: SettingsKey.jumpShortcut) {
            if let spec = ShortcutSpec(legacy: old), spec != JumpShortcut.defaultSpec, overrides.values[JumpShortcut.commandID] == nil {
                edit { $0.values[JumpShortcut.commandID] = .some(spec) }
            }
            d.removeObject(forKey: SettingsKey.jumpShortcut)
        }
    }

    func resolved(_ c: AppCommand) -> KeyboardShortcut? { effective(c.id, default: c.shortcut) }

    func effective(_ id: String, default fallback: KeyboardShortcut?) -> KeyboardShortcut? {
        guard let o = overrides.values[id] else { return fallback }
        return o?.keyboardShortcut
    }

    func spec(_ c: AppCommand) -> ShortcutSpec? { overrides.values[c.id] ?? c.shortcut.flatMap { ShortcutSpec($0) } }

    func isCustomized(_ id: String) -> Bool { overrides.values[id] != nil }

    /// Stores `spec` (nil removes the shortcut); a spec equal to the default drops the override.
    func set(_ spec: ShortcutSpec?, for c: AppCommand) {
        let isDefault = spec == c.shortcut.flatMap({ ShortcutSpec($0) })
        if isDefault && sets.isBuiltIn && sets.current.values[c.id] == nil { return }
        edit { $0.values[c.id] = isDefault ? nil : .some(spec) }
    }

    func reset(_ id: String) { edit { $0.values[id] = nil } }

    /// Clears the selected set's changes.
    func resetAll() { change { $0.resetCurrent() } }

    func change(_ body: (inout ShortcutSets) -> Void) {
        body(&sets)
        UserDefaults.standard.set(try? JSONEncoder().encode(sets), forKey: SettingsKey.shortcutSets)
    }

    private func edit(_ body: (inout ShortcutOverrides) -> Void) { change { $0.edit(body) } }
}

/// Jump to Definition's shortcut for the hover card; the setting itself now lives in the Shortcuts store.
@MainActor enum JumpShortcut {
    static let commandID = "Navigate/Jump to Definition"
    static let defaultShortcut = KeyboardShortcut("j", modifiers: [.command, .control])
    static let defaultSpec = ShortcutSpec(defaultShortcut)!

    /// Nil when the user removed the shortcut.
    static var current: KeyboardShortcut? { ShortcutStore.shared.effective(commandID, default: defaultShortcut) }
}


/// A shortcut shown as plain text; clicked, or while `recording` is set, it records the next key press (Esc cancels). Reserved or invalid combinations are refused with a reason.
struct ShortcutRecorder: View {
    let spec: ShortcutSpec?
    @Binding var recording: Bool
    let record: (ShortcutSpec) -> Void
    @State private var monitor: Any?
    @State private var refusal: String?

    var body: some View {
        Text(recording ? String(localized: "Press keys…") : spec?.display ?? "")
            .monospacedDigit()
            .contentShape(Rectangle())
            .onTapGesture { recording.toggle() }
            .popover(isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })) {
                Text(refusal ?? "").padding(10)
            }
            .onChange(of: recording) { if recording { start() } else { stop() } }
            .onDisappear { stop() }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { stop(); return nil }   // Esc
            guard let s = ShortcutSpec.from(event) else { NSSound.beep(); return nil }
            if let why = s.refusal {
                NSSound.beep()
                refusal = why
                stop()
                return nil
            }
            record(s)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

private enum ShortcutScope: Hashable { case all, menu, text, customized, conflicts }

/// A row of the list: a menu command (changeable), or a fixed key shown read-only.
private struct ShortcutEntry: Identifiable {
    let id: String
    let section: String
    let title: String
    let systemImage: String
    var command: AppCommand?
    var fixed: String?
    /// Fixed keys that are no menu item (the editor's own).
    var isEditorKey = false

    var isText: Bool { isEditorKey || command.map { Self.textMenus.contains($0.menuKey) || Self.textCommands.contains($0.id) } == true }

    // One place for the Text scope: these menus, plus the fold commands.
    private static let textMenus: Set = ["Edit", "Format"]
    private static let textCommands: Set = ["View/Fold Section", "View/Unfold Section", "View/Fold All Sections", "View/Unfold All Sections"]
}

/// Every menu command with its shortcut, changeable, as in Xcode's Key Bindings; the list comes from the registry built with a context without project or windows.
struct ShortcutsSettings: View {
    @ObservedObject private var store = ShortcutStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var filter = ""
    @State private var scope = ShortcutScope.all
    @State private var recordingID: String?
    private enum Naming { case duplicate, rename }
    private enum Confirm { case restore, delete }
    @State private var naming: Naming?
    @State private var name = ""
    @State private var confirm: Confirm?

    private static let sectionOrder = ["Typo", "File", "Edit", "Format", "View", "Navigate", "Git", "Window", "Editor"]

    /// Commands with dynamic titles (such as Git's "Switch to “branch”") are left out: the catalog context has no project, so they do not exist.
    private var commands: [AppCommand] {
        let ctx = AppCommandContext(project: nil, tables: nil, editor: nil, files: nil, fileListFocused: nil, layout: nil, recents: RecentProjects(), openWindow: openWindow, sidebar: nil, isCatalog: true)
        return AppCommands.all(ctx, forPalette: false)
    }

    /// The app menu's items are the system's; the editor's keys are not menu items. Both are read-only.
    private var entries: [ShortcutEntry] {
        func fixed(_ section: String, _ title: LocalizedStringResource, _ symbol: String, _ keys: String, editor: Bool) -> ShortcutEntry {
            ShortcutEntry(id: "\(section)/\(title.key)", section: section, title: String(localized: title), systemImage: symbol, fixed: keys, isEditorKey: editor)
        }
        let accept = switch CompletionPreferences.acceptKeys { case .both: "↩, ⇥"; case .returnOnly: "↩"; case .tabOnly: "⇥" }
        let app = [fixed("Typo", "About Typo", "info.circle", "", editor: false), fixed("Typo", "Settings…", "gearshape", "⌘,", editor: false),
                   fixed("Typo", "Hide Typo", "eye.slash", "⌘H", editor: false), fixed("Typo", "Hide Others", "eye.slash", "⌥⌘H", editor: false),
                   fixed("Typo", "Show All", "eye", "", editor: false), fixed("Typo", "Quit Typo", "power", "⌘Q", editor: false)]
        let keys = [fixed("Editor", "Complete", "text.badge.plus", "⎋, ⌥⎋, F5", editor: true), fixed("Editor", "Accept Completion", "checkmark.circle", accept, editor: true),
                    fixed("Editor", "Next Placeholder", "arrow.right.to.line", "⇥", editor: true), fixed("Editor", "Previous Placeholder", "arrow.left.to.line", "⇧⇥", editor: true),
                    fixed("Editor", "Indent", "increase.indent", "⇥", editor: true), fixed("Editor", "Outdent", "decrease.indent", "⇧⇥", editor: true)]
        // Export is File's submenu.
        let menu = commands.map { c in
            ShortcutEntry(id: c.id, section: c.menuKey == "Export" ? "File" : c.menuKey, title: c.menuKey == "Export" ? String(localized: "Export ▸ \(String(localized: c.title))") : String(localized: c.title), systemImage: c.systemImage, command: c)
        }
        return (app + menu + keys).enumerated().sorted { (Self.rank($0.element.section), $0.offset) < (Self.rank($1.element.section), $1.offset) }.map(\.element)
    }

    private static func rank(_ section: String) -> Int { sectionOrder.firstIndex(of: section) ?? sectionOrder.count - 1 }

    var body: some View {
        let all = entries
        let conflicts = ShortcutSpec.conflicts(all.compactMap { e in e.command.flatMap { store.spec($0) }.map { (e.id, $0) } })
        let conflicted = Set(conflicts.values.flatMap { $0 })
        let shown = all.filter { e in
            (filter.isEmpty || e.title.localizedCaseInsensitiveContains(filter) || e.section.localizedCaseInsensitiveContains(filter) || display(e).contains(filter.uppercased()))
                && (scope == .all || (scope == .menu && !e.isEditorKey) || (scope == .text && e.isText)
                    || (scope == .customized && store.isCustomized(e.id)) || (scope == .conflicts && conflicted.contains(e.id)))
        }
        let titles = Dictionary(uniqueKeysWithValues: all.map { ($0.id, "\($0.section) ▸ \($0.title)") })
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Shortcut Set") { setMenu }
                    if store.sets.selected == ShortcutSets.vimName {
                        Text(ShortcutSets.vimDescription).font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Adapt to current keyboard", isOn: $store.adaptsToKeyboard)
                        Text("Automatically adapts unmodified key bindings to the current input method.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .pane()
            .scrollDisabled(true)
            .frame(height: store.sets.selected == ShortcutSets.vimName ? 170 : 130)
            VStack(spacing: 0) {
                header(conflicted: conflicted.count)
                Divider()
                list(shown, conflicts: conflicts, titles: titles)
            }
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
            .padding([.horizontal, .bottom], 20)
        }
        .onChange(of: conflicted.isEmpty) { if conflicted.isEmpty && scope == .conflicts { scope = .all } }
        .confirmationDialog(confirm == .delete ? "Delete “\(store.sets.selected)”?" : "Restore “\(store.sets.selected)” to the defaults?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            if confirm == .delete {
                Button("Delete", role: .destructive) { store.change { $0.deleteCurrent() } }
            } else {
                Button("Restore Defaults", role: .destructive) { store.resetAll() }
            }
        } message: { Text(confirm == .delete ? "The set and every change in it are discarded." : "Every change you made to a shortcut in this set is discarded.") }
        .alert(naming == .rename ? "Rename “\(store.sets.selected)”" : "Duplicate “\(store.sets.selected)”", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button(naming == .rename ? "Rename" : "Duplicate") {
                if naming == .rename { store.change { $0.rename(to: name) } } else { store.change { $0.duplicate(as: name) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var setMenu: some View {
        Menu(store.sets.selected) {
            Picker("Shortcut Set", selection: Binding(get: { store.sets.selected }, set: { n in store.change { $0.select(n) } })) {
                ForEach(store.sets.names, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Duplicate “\(store.sets.selected)”…") { name = store.sets.uniqueName("\(store.sets.selected) copy"); naming = .duplicate }
            if !store.sets.isBuiltIn {
                Button("Rename “\(store.sets.selected)”…") { name = store.sets.selected; naming = .rename }
                Button("Delete “\(store.sets.selected)”…") { confirm = .delete }
                Divider()
                Button("Restore Defaults…") { confirm = .restore }.disabled(store.overrides.values.isEmpty)
            }
        }
        .fixedSize()
    }

    private func header(conflicted: Int) -> some View {
        func segments(_ choices: [(ShortcutScope, LocalizedStringKey)]) -> some View {
            Picker("Show", selection: Binding<ShortcutScope?>(get: { choices.contains { $0.0 == scope } ? scope : nil }, set: { if let s = $0 { scope = s } })) {
                ForEach(choices, id: \.0) { Text($0.1).tag(Optional($0.0)) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        return HStack(spacing: 10) {
            segments([(.all, "All"), (.menu, "Menu"), (.text, "Text")])
            segments([(.customized, "Customized")] + (conflicted > 0 ? [(.conflicts, "Conflicts \(conflicted)")] : []))
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle").foregroundStyle(.secondary)
                TextField("Filter", text: $filter).textFieldStyle(.plain).accessibilityLabel("Filter shortcuts")
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 6))
        }
        .padding(10)
    }

    private func list(_ shown: [ShortcutEntry], conflicts: [ShortcutSpec: [String]], titles: [String: String]) -> some View {
        let sections = Self.sectionOrder.filter { s in shown.contains { $0.section == s } }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element) { i, section in
                    if i > 0 { Divider().padding(.vertical, 6) }
                    Text(section == "Editor" ? "Editor Keys" : "\(section) Menu").fontWeight(.bold).padding(.horizontal, 18).padding(.vertical, 4)
                    ForEach(Array(shown.filter { $0.section == section }.enumerated()), id: \.element.id) { n, e in
                        row(e, conflicts: conflicts, titles: titles).background(n % 2 == 1 ? Color.primary.opacity(0.05) : .clear, in: .rect(cornerRadius: 8)).padding(.horizontal, 8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
        .background(.background)
    }

    private func display(_ e: ShortcutEntry) -> String { e.command.map { store.spec($0)?.display ?? "" } ?? e.fixed ?? "" }

    private func row(_ e: ShortcutEntry, conflicts: [ShortcutSpec: [String]], titles: [String: String]) -> some View {
        let c = e.command
        let spec = c.flatMap { store.spec($0) }
        let others = spec.flatMap { conflicts[$0] }?.filter { $0 != e.id }.compactMap { titles[$0] } ?? []
        let customized = store.isCustomized(e.id)
        return HStack(spacing: 8) {
            Image(systemName: e.systemImage).foregroundStyle(.secondary).frame(width: 20)
            Text(e.title).fontWeight(customized ? .semibold : .regular)
            Spacer()
            if !others.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    .help("Also used by \(others.joined(separator: ", "))")
                    .accessibilityLabel("Conflicts with \(others.joined(separator: ", "))")
            }
            Group {
                if let c {
                    ShortcutRecorder(spec: spec, recording: Binding(get: { recordingID == e.id }, set: { recordingID = $0 ? e.id : (recordingID == e.id ? nil : recordingID) })) { store.set($0, for: c) }
                        .accessibilityLabel("Shortcut for \(e.title)")
                } else {
                    Text(e.fixed ?? "")
                }
            }
            .frame(width: 130, alignment: .trailing)
        }
        .foregroundStyle(c == nil ? .secondary : .primary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if c != nil { recordingID = e.id } }
        .contextMenu {
            if let c {
                Button("Remove Shortcut") { store.set(nil, for: c) }.disabled(spec == nil)
                if customized { Button("Restore Default") { store.reset(e.id) } }
            }
        }
    }
}

#Preview {
    ShortcutsSettings().frame(width: 640, height: 640)
}
