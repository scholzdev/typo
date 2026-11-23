import AppKit
import SwiftUI
import TypoKit
import TypstEngine

enum SettingsKey {
    static let animatedCaret = "animatedCaret"
    static let jumpShortcut = "jumpToDefinitionShortcut"
    static let hoverJumpHint = "hoverJumpHint"
    static let formatOnSave = "formatOnSave"
    static let formatWidth = "formatLineWidth"
    static let formatIndent = "formatIndentWidth"
    static let tab = "settingsTab"
    static let editedSnippet = "settingsEditedSnippet"
}

/// Raw values are the persisted SettingsKey.tab tags.
enum SettingsTab: String, CaseIterable {
    case general, appearance, intelligence, navigation, textEditing, shortcuts, snippets, packages, sourceControl, components, license

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .intelligence: "Intelligence"
        case .navigation: "Navigation"
        case .textEditing: "Editing"
        case .shortcuts: "Shortcuts"
        case .snippets: "Snippets"
        case .packages: "Packages"
        case .sourceControl: "Source Control"
        case .components: "Components"
        case .license: "License"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        // Xcode's Appearance icon; it ships in the system's private symbol set, so fall back where it doesn't resolve.
        case .appearance: NSImage(systemSymbolName: "appearance.lightmode", accessibilityDescription: nil) != nil ? "appearance.lightmode" : "circle.lefthalf.filled"
        case .intelligence: "sparkles"
        case .navigation: "arrow.triangle.turn.up.right.diamond"
        case .textEditing: "square.and.pencil"
        case .shortcuts: "keyboard"
        case .snippets: "curlybraces"
        case .packages: "shippingbox"
        case .sourceControl: "arrow.triangle.branch"
        case .components: "square.3.layers.3d"
        case .license: "key"
        }
    }

    @MainActor var isVisible: Bool { self != .license || LicenseStore.enforced }
}

/// An open sub-page of a settings area. Equality ignores the title so a rename does not count as a new visit.
struct SettingsSubpage: Equatable, Sendable {
    let tab: SettingsTab
    let id: String
    var title: String
    static func == (a: Self, b: Self) -> Bool { a.tab == b.tab && a.id == b.id }
}

/// The open sub-page (one level per area), shared by the window header and the areas.
@MainActor @Observable final class SettingsNavigation {
    var page: SettingsSubpage?
}

/// One entry of the window's Back/Forward history: a tab and its open sub-page, if any.
struct SettingsPlace: Equatable, Sendable {
    var tab: SettingsTab
    var page: SettingsSubpage?
}

struct SettingsView: View {
    @AppStorage(SettingsKey.tab) private var tab = "general"
    @State private var nav = SettingsNavigation()
    @State private var packageUpdates = PackageUpdateModel()
    @State private var history = VisitHistory(start: SettingsPlace(tab: .general, page: nil))
    @State private var licenseKey = ""
    @State private var licenseError: LicenseError?
    @State private var licenseBusy = false

    private var current: SettingsTab { SettingsTab(rawValue: tab).flatMap { $0.isVisible ? $0 : nil } ?? .general }   // also catches the removed "themes" tab

    private var place: SettingsPlace { SettingsPlace(tab: current, page: nav.page?.tab == current ? nav.page : nil) }

    private var selection: Binding<SettingsTab?> {
        Binding { current } set: { if let t = $0 { tab = t.rawValue } }
    }

    private var updateBadge: some View {
        let n = packageUpdates.updates.count
        return Text("\(n)").font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 1).background(Color.accentColor, in: Capsule())
            .accessibilityLabel("\(n) \(n == 1 ? "update" : "updates")")
    }

    private func go(to p: SettingsPlace) {
        tab = p.tab.rawValue
        nav.page = p.page
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            let tabs = SettingsTab.allCases.filter(\.isVisible)
            // Own rows: the sidebar List always paints the accent-colour selection.
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tabs, id: \.self) { t in
                        let on = t == current
                        Button { tab = t.rawValue } label: {
                            Label {
                                HStack {
                                    Text(t.title).fontWeight(on ? .semibold : .regular)
                                    if t == .packages, !packageUpdates.updates.isEmpty { Spacer(); updateBadge }
                                }
                            } icon: {
                                Image(systemName: t.symbol).font(.system(size: 17)).foregroundStyle(Color.accentColor).frame(width: 22)
                            }
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .background(on ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .task { await packageUpdates.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: TypstRuntime.packageIndexDidChange)) { _ in Task { await packageUpdates.refresh() } }
            .focusable()
            .focusEffectDisabled()   // the row highlight shows focus, as in Xcode; no ring around the column
            .onMoveCommand { d in
                guard let i = tabs.firstIndex(of: current) else { return }
                let j = d == .down ? i + 1 : d == .up ? i - 1 : i
                if tabs.indices.contains(j) { tab = tabs[j].rawValue }
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 210)   // SwiftUI's default (~270) took a third of the window
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch current {
                    case .general: GeneralSettings()
                    case .appearance: AppearanceSettings()
                    case .intelligence: IntelligenceSettings()
                    case .navigation: NavigationSettingsView()
                    case .textEditing: TextEditingSettings()
                    case .shortcuts: ShortcutsSettings()
                    case .snippets: SnippetSettings()
                    case .packages: PackagesSettings(updates: packageUpdates)
                    case .sourceControl: SourceControlSettings()
                    case .components: ComponentsSettings()
                    case .license: license
                    }
                }
            }
            .navigationTitle(place.page?.title ?? current.title)   // the window title; the visible one is drawn in `header`
            .toolbar(removing: .title)
            .toolbar {   // in the title bar, level with the traffic lights, as in Xcode: glass only around the arrows
                ToolbarItem(placement: .navigation) { arrows }
                ToolbarItem(placement: .navigation) {
                    Text(place.page?.title ?? current.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, 4)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .frame(minWidth: 680, minHeight: 420)
        .background(WindowStyler())
        .environment(nav)
        .onAppear { history = VisitHistory(start: place) }
        .onChange(of: tab) { if nav.page?.tab != current { nav.page = nil } }   // sidebar clicks and deep links leave the sub-page
        // Back/Forward land here too; they already moved the history, so the visit is a no-op.
        .onChange(of: place) { history.visit(place) }
    }

    /// Xcode-style back/forward pair; the toolbar draws its glass capsule.
    private var arrows: some View {
            HStack(spacing: 0) {
                Button { if let p = history.back() { go(to: p) } } label: {
                    Image(systemName: "chevron.left").frame(width: 32, height: 28).contentShape(Rectangle())
                }
                .disabled(!history.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel("Back")
                Divider().frame(height: 18)
                Button { if let p = history.forward() { go(to: p) } } label: {
                    Image(systemName: "chevron.right").frame(width: 32, height: 28).contentShape(Rectangle())
                }
                .disabled(!history.canGoForward)
                .keyboardShortcut("]", modifiers: .command)
                .accessibilityLabel("Forward")
            }
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.primary)
    }

    private var license: some View {
        let store = LicenseStore.shared
        return Form {
            switch store.state {
            case .licensed(let license):
                Text("Licensed to \(license.email)")
                Text("Activated on this Mac.").font(.caption).foregroundStyle(.secondary)
                Button("Deactivate This Mac") {
                    licenseBusy = true
                    Task {
                        licenseError = await store.deactivate()
                        licenseBusy = false
                    }
                }
                .disabled(licenseBusy)
                if let licenseError {
                    Text(licenseError.message).font(.caption).foregroundStyle(.red)
                }
            case .trial(let days):
                Text("Trial: \(days) \(days == 1 ? "day" : "days") left")
                licenseEntry
            case .expired:
                Text("Your trial has ended. Documents are read-only; exporting still works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                licenseEntry
            }
        }
        .pane()
    }

    @ViewBuilder private var licenseEntry: some View {
        if LicenseStore.shared.license != nil {
            Text("This license isn\u{2019}t activated on this Mac.").font(.caption).foregroundStyle(.secondary)
        }
        TextField("License key", text: $licenseKey).disabled(licenseBusy)
        HStack {
            Button("Activate") {
                licenseBusy = true
                Task {
                    licenseError = await LicenseStore.shared.activate(licenseKey)
                    if licenseError == nil { licenseKey = "" }
                    licenseBusy = false
                }
            }
            .disabled(licenseKey.isEmpty || licenseBusy)
            if licenseBusy { ProgressView().controlSize(.small) }
        }
        if let licenseError {
            Text(licenseError.message).font(.caption).foregroundStyle(.red)
        }
    }
}

extension View {
    func pane() -> some View {
        formStyle(.grouped)
    }
}

/// Reports the hosting window so the Settings window can be minimized and zoomed (SwiftUI's Settings scene turns both off).
private struct WindowStyler: NSViewRepresentable {
    final class V: NSView {
        private var closing: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            style()
            if let closing { NotificationCenter.default.removeObserver(closing) }
            // Settings always open on General: reset on close, so a deep link that sets the tab before opening still wins.
            closing = window.map { NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: $0, queue: .main) { _ in
                UserDefaults.standard.set(SettingsTab.general.rawValue, forKey: SettingsKey.tab)
            } }
        }
        func style() {
            guard let w = window else { return }
            w.styleMask.formUnion([.miniaturizable, .resizable])
            w.toolbarStyle = .unified   // the Settings scene picks .preference, which centers the toolbar items
            w.standardWindowButton(.miniaturizeButton)?.isEnabled = true
            w.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }
    func makeNSView(context: Context) -> V { V() }
    func updateNSView(_ v: V, context: Context) { v.style() }
}
