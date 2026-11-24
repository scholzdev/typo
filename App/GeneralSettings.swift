import AppKit
import SwiftUI

extension SettingsKey {
    static let restoreProjects = "generalRestoreProjects"
    static let fileExtensions = "generalFileExtensions"
    static let findDetail = "generalFindDetail"
    static let issueDetail = "generalIssueDetail"
    static let bookmarkDetail = "generalBookmarkDetail"
    static let inlineIssues = "generalInlineIssues"
    static let compileWhileTyping = "generalCompileWhileTyping"
    static let accessibilityChecks = "generalAccessibilityChecks"
}

/// When the PDF/UA pre-flight (TypoKit Accessibility) adds its hints to the Issues.
enum AccessibilityChecks: String {
    case off, whenUA, always

    /// `whenUA` follows the export target; unknown stored values count as the default.
    @MainActor static func enabled(_ stored: String, target: ExportTarget) -> Bool {
        switch AccessibilityChecks(rawValue: stored) ?? .whenUA {
        case .off: false
        case .whenUA: target == .pdfUA1
        case .always: true
        }
    }
}

enum FileExtensions: String { case hideTyp, showAll, hideAll }

extension View {
    /// 0 is unlimited.
    func lineLimit(lines: Int) -> some View { lineLimit(lines == 0 ? nil : lines) }
}

enum RestoreProjects: String {
    case system, always, never

    /// AppKit (and so SwiftUI's window restoration) reads the app-domain NSQuitAlwaysKeepsWindows at quit and launch.
    static func apply() {
        let d = UserDefaults.standard
        switch RestoreProjects(rawValue: d.string(forKey: SettingsKey.restoreProjects) ?? "") ?? .system {
        case .system: d.removeObject(forKey: "NSQuitAlwaysKeepsWindows")
        case .always: d.set(true, forKey: "NSQuitAlwaysKeepsWindows")
        case .never: d.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        }
    }
}

/// Which stored defaults are settings. Only plain values qualify (Data holds bookmarks, accounts, snippets and
/// other state), and the names below are state or secrets that happen to be plain values.
enum SettingsTransfer {
    private static let excluded: Set<String> = [
        SettingsKey.tab, SettingsKey.editedSnippet,
    ]
    private static let excludedPrefixes = ["NS", "Apple", "com.apple", "TypstCore."]

    static func isTransferable(_ key: String, _ value: Any) -> Bool {
        guard !excluded.contains(key), !excludedPrefixes.contains(where: key.hasPrefix), !key.localizedCaseInsensitiveContains("bookmark") else { return false }
        return value is String || value is NSNumber   // Bool is an NSNumber too
    }

    static func settings(_ all: [String: Any]) -> [String: Any] { all.filter { isTransferable($0.key, $0.value) } }

    static var stored: [String: Any] {
        settings(UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:])
    }

    /// Writes only the allowed keys of `plist`, so an edited file cannot touch the recents.
    static func importSettings(_ plist: [String: Any]) {
        for (k, v) in settings(plist) { UserDefaults.standard.set(v, forKey: k) }
        RestoreProjects.apply()
    }

    static func reset() {
        for k in stored.keys { UserDefaults.standard.removeObject(forKey: k) }
        RestoreProjects.apply()
    }
}

struct GeneralSettings: View {
    @AppStorage(SettingsKey.restoreProjects) private var restore = RestoreProjects.system.rawValue
    @AppStorage(SettingsKey.fileExtensions) private var extensions = FileExtensions.hideTyp.rawValue
    @AppStorage(SettingsKey.findDetail) private var findDetail = 1
    @AppStorage(SettingsKey.issueDetail) private var issueDetail = 0
    @AppStorage(SettingsKey.bookmarkDetail) private var bookmarkDetail = 1
    @AppStorage(SettingsKey.inlineIssues) private var inlineIssues = true
    @AppStorage(SettingsKey.compileWhileTyping) private var compileWhileTyping = true
    @AppStorage(SettingsKey.accessibilityChecks) private var accessibilityChecks = AccessibilityChecks.whenUA.rawValue
    @State private var confirmReset = false
    @State private var transferError: String?

    var body: some View {
        Form {
            // As at the top of System Settings › General: a large tile, the name and what the area covers, centred.
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "gear")
                        .font(.system(size: 34, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.gray.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .padding(.bottom, 4)
                        .accessibilityHidden(true)
                    Text("General").font(.system(size: 22, weight: .bold))
                    Text("Choose what Typo restores at launch, how files and issues are shown, and when your document is checked.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14).padding(.horizontal, 24)
                .accessibilityElement(children: .combine)
            }
            AppLanguageSection()
            Section("Starting Points") {
                Picker("Restore open projects", selection: $restore) {
                    Text("Use System Setting").tag("system")
                    Text("Always").tag("always")
                    Text("Never").tag("never")
                }
                .onChange(of: restore) { RestoreProjects.apply() }
                if restore == "system" {
                    Text("Typo uses the value for \u{201C}Close windows when quitting an application\u{201D} set in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Navigation and Files") {
                Picker("File extensions", selection: $extensions) {
                    Text("Hide .typ").tag("hideTyp")
                    Text("Show All").tag("showAll")
                    Text("Hide All").tag("hideAll")
                }
                Picker("Find navigator detail", selection: $findDetail) { detailChoices }
                Picker("Issue navigator detail", selection: $issueDetail) { detailChoices }
                Picker("Bookmark navigator detail", selection: $bookmarkDetail) { detailChoices }
            }
            Section("Issues") {
                Picker("Issue presentation", selection: $inlineIssues) {
                    Text("Show Inline").tag(true)
                    Text("Hide Inline").tag(false)
                }
                Text("Errors and warnings stay in the Issue navigator. Lint hints follow Text Editing settings.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Accessibility checks", selection: $accessibilityChecks) {
                    Text("Off").tag(AccessibilityChecks.off.rawValue)
                    Text("When Exporting PDF/UA").tag(AccessibilityChecks.whenUA.rawValue)
                    Text("Always").tag(AccessibilityChecks.always.rawValue)
                }
                Text("Hints for missing alternative text, skipped heading levels, tables without a header, and a missing title or language.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Live preview", selection: $compileWhileTyping) {
                    Text("While Typing").tag(true)
                    Text("On Save").tag(false)
                }
                Text("On Save compiles when the file is saved, which includes autosave.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Settings Import & Export") {
                HStack {
                    Spacer()
                    Button("Export\u{2026}", action: export)
                    Button("Import\u{2026}", action: importFile)
                }
                if let transferError { Text(transferError).font(.caption).foregroundStyle(.red) }
                Text("Recent projects and window positions are not included.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Reset Typo") {
                LabeledContent {
                    Button("Reset\u{2026}") { confirmReset = true }
                } label: {
                    Text("Reset Settings")
                    Text("Resets all settings to their default values.")
                }
            }
        }
        .pane()
        .alert("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { SettingsTransfer.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your recent projects and snippets are kept.")
        }
    }

    @ViewBuilder private var detailChoices: some View {
        Text("1 Line").tag(1)
        Text("Up to 2 Lines").tag(2)
        Text("Up to 3 Lines").tag(3)
        Text("Unlimited").tag(0)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Typo Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PropertyListSerialization.data(fromPropertyList: SettingsTransfer.stored, format: .xml, options: 0).write(to: url)
            transferError = nil
        } catch { transferError = error.localizedDescription }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let object = url.pathExtension.lowercased() == "json"
                ? try JSONSerialization.jsonObject(with: data) : try PropertyListSerialization.propertyList(from: data, format: nil)
            guard let dict = object as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            SettingsTransfer.importSettings(dict)
            transferError = nil
        } catch { transferError = error.localizedDescription }
    }
}

/// The app's own language, as in System Settings › General › Language & Region › Applications: the choice is the
/// app's `AppleLanguages` default, which Foundation reads at launch, so it applies after a restart.
private struct AppLanguageSection: View {
    private static let key = "AppleLanguages"
    private static let launched = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[key] as? [String]
    @State private var choice = (launched?.first).map { String($0.prefix(2)) } ?? "system"

    var body: some View {
        Section {
            Picker("Language", selection: $choice) {
                Text("Use System Setting").tag("system")
                Divider()
                Text(verbatim: "English").tag("en")
                Text(verbatim: "Deutsch").tag("de")
            }
            .onChange(of: choice) { _, c in
                if c == "system" { UserDefaults.standard.removeObject(forKey: Self.key) } else { UserDefaults.standard.set([c], forKey: Self.key) }
            }
            if choice != ((Self.launched?.first).map { String($0.prefix(2)) } ?? "system") {
                HStack {
                    Text("The new language applies after Typo restarts.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Typo") { Self.restart() }
                }
            }
        }
    }

    /// Opens a second instance that waits for this one to quit, so the relaunch survives unsaved-changes prompts.
    private static func restart() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"$0\"", Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
