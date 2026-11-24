import AppKit
import TypoKit

/// The caret's shape (Settings, Appearance, Editor).
enum CaretShape: String, CaseIterable, Identifiable {
    case bar, block, underline
    var id: String { rawValue }
    var title: String { switch self { case .bar: String(localized: "Vertical Bar"); case .block: String(localized: "Block"); case .underline: String(localized: "Underline") } }
    var symbol: String { switch self { case .bar: "character.cursor.ibeam"; case .block: "square.fill"; case .underline: "underline" } }
}

/// The app-wide light or dark appearance (Settings, Appearance).
enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark, system    // in System Settings' order
    var id: String { rawValue }
    var title: String { switch self { case .system: String(localized: "Auto"); case .light: String(localized: "Light"); case .dark: String(localized: "Dark") } }

    @MainActor static func apply() {
        let a = AppAppearance(rawValue: UserDefaults.standard.string(forKey: SettingsKey.appAppearance) ?? "") ?? .system
        NSApp.appearance = switch a { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
    }
}

extension EditorView.Coordinator {
    // Runs on every defaults change, so it must be idempotent and cheap.
    func applyAppearanceSettings(_ tv: NSTextView, _ scroll: NSScrollView) {
        let d = UserDefaults.standard
        let base = CaretShape(rawValue: d.string(forKey: SettingsKey.editorCursorStyle) ?? "") ?? .bar
        let vim = (tv as? EditorTextView)?.vim
        let shape = vim?.caretShape(base) ?? base        // Vim's Normal and Visual modes draw a block
        decor?.caretShape = shape
        // Runs after setAnimatedCaret: the caret layer replaces the system caret also for a non-bar shape.
        let color = decor?.animatedCaret == true || shape != .bar ? NSColor.clear : Highlighter.style.colors.cursor
        if tv.insertionPointColor != color { tv.insertionPointColor = color }
        if isPrimary { layout?.firstText = tv } else { layout?.secondText = tv }
        layout?.updateDimming()
        vim?.settingsChanged()
    }
}

extension EditorLayout {
    /// With both panes showing, the one without keyboard focus is drawn dimmed (Settings, Appearance).
    func updateDimming() {
        let on = split && !focus && (UserDefaults.standard.object(forKey: SettingsKey.dimUnfocusedPanes) as? Bool ?? true)
        let first: CGFloat = on && secondFocused ? 0.7 : 1, second: CGFloat = on && !secondFocused ? 0.7 : 1
        if firstText?.alphaValue != first { firstText?.alphaValue = first }
        if secondText?.alphaValue != second { secondText?.alphaValue = second }
    }
}
