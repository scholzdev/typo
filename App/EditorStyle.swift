import AppKit
import SwiftUI
import TypoKit
import TypstEngine

extension SettingsKey {
    static let editorFontSize = "editorFontSize"
    static let editorTheme = "editorTheme"
    static let editorFontFamily = "editorFontFamily"     // "" is the system monospaced font
    static let editorFontStyles = "editorFontStyles"     // JSON: tag name to FontStyle, only the changed tags
    static let appAppearance = "appAppearance"
    static let editorCursorStyle = "editorCursorStyle"
    static let dimUnfocusedPanes = "dimUnfocusedPanes"
    /// JSON `ThemeOverrides` of one built-in theme in one appearance.
    static func themeOverrides(_ theme: String, dark: Bool) -> String { "editorThemeOverrides.\(theme).\(dark ? "dark" : "light")" }
}

/// The editor's font size and theme settings (design/14e): pushed into the highlighter, which repaints every open file.
@MainActor enum EditorStyle {
    static let sizes: ClosedRange<Double> = 10...24
    static let defaultSize = Double(NSFont.systemFontSize)

    /// Idempotent: every editor calls it on update; only a real change repaints. The one place the highlighter is
    /// configured, so the overrides, font family and styles from Settings always come along.
    static func apply(size: Double, theme: String) {
        let size = min(max(size, sizes.lowerBound), sizes.upperBound)
        let family = UserDefaults.standard.string(forKey: SettingsKey.editorFontFamily).flatMap { $0.isEmpty ? nil : $0 }
        let t = EditorTheme.named(theme).applying(light: overrides(theme, dark: false), dark: overrides(theme, dark: true))
        guard Highlighter.configure(t, fontSize: CGFloat(size), family: family, styles: fontStyles) else { return }
        for p in OpenProjects.shared.projects { p.restyleBuffers() }
    }

    static func overrides(_ theme: String, dark: Bool) -> ThemeOverrides {
        UserDefaults.standard.string(forKey: SettingsKey.themeOverrides(theme, dark: dark))
            .flatMap { try? JSONDecoder().decode(ThemeOverrides.self, from: Data($0.utf8)) } ?? ThemeOverrides()
    }

    static func setOverrides(_ o: ThemeOverrides, _ theme: String, dark: Bool) {
        let key = SettingsKey.themeOverrides(theme, dark: dark)
        if o.colors.isEmpty { UserDefaults.standard.removeObject(forKey: key); return }
        UserDefaults.standard.set(String(decoding: try! JSONEncoder().encode(o), as: UTF8.self), forKey: key)
    }

    /// The font style overrides from Settings, by tag; unknown names (a renamed tag) are dropped.
    static var fontStyles: [SyntaxTag: FontStyle] { decodeStyles(UserDefaults.standard.string(forKey: SettingsKey.editorFontStyles) ?? "") }

    static func decodeStyles(_ json: String) -> [SyntaxTag: FontStyle] {
        let raw = (try? JSONDecoder().decode([String: FontStyle].self, from: Data(json.utf8))) ?? [:]
        return Dictionary(uniqueKeysWithValues: EditorTheme.tags.compactMap { row in raw[row.key].map { (row.tag, $0) } })
    }

    /// The `Highlighter.revision` each text view last refreshed its own surfaces for.
    static let refreshed = NSMapTable<NSView, NSNumber>.weakToStrongObjects()
}

extension EditorView.Coordinator {
    /// The surfaces a theme or size change reaches outside the text's own attributes.
    func applyStyle(size: Double, theme: String, to tv: NSTextView, in scroll: NSScrollView) {
        EditorStyle.apply(size: size, theme: theme)
        let style = Highlighter.style
        if EditorStyle.refreshed.object(forKey: tv)?.intValue != Highlighter.revision {
            EditorStyle.refreshed.setObject(Highlighter.revision as NSNumber, forKey: tv)
            tv.typingAttributes = Highlighter.base
            tv.backgroundColor = style.colors.background
            scroll.backgroundColor = style.colors.background
            scroll.appearance = style.isDarkOnly ? NSAppearance(named: .darkAqua) : nil
            let digits = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            // Four digits plus the fold triangles' column.
            scroll.verticalRulerView?.ruleThickness = max(40, ceil(("8888" as NSString).size(withAttributes: [.font: digits]).width) + 14) + 10
            scroll.verticalRulerView?.needsDisplay = true
            decor?.refresh()
        }
    }
}

/// View-menu commands of the editor; the preview keeps ⌘+, ⌘− and ⌘0.
struct EditorComfortCommands: Commands {
    @AppStorage(SettingsKey.editorFontSize) private var fontSize = EditorStyle.defaultSize
    let recents: RecentProjects
    private let focus = FocusedCommandContext()

    private var context: AppCommandContext { focus.context(recents: recents) }

    var body: some Commands {
        let ctx = context
        CommandGroup(after: .toolbar) {
            let _ = fontSize    // observed: the text size items' enabled state reads UserDefaults
            Divider()
            AppCommands.items(AppCommands.library(ctx))
            Divider()
            AppCommands.items(AppCommands.editorView(ctx))
        }
    }
}
