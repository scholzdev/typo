import AppKit
import SwiftUI
import TypoKit

/// Settings, Appearance (after Xcode's): the app appearance, a live preview, then the theme colors, fonts and caret.
struct AppearanceSettings: View {
    private enum Tab: String, CaseIterable {
        case theme = "Theme", fonts = "Fonts", editor = "Editor"
        var title: LocalizedStringKey { switch self { case .theme: "Theme"; case .fonts: "Fonts"; case .editor: "Editor" } }
    }

    @AppStorage(SettingsKey.appAppearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(SettingsKey.editorFontSize) private var fontSize = EditorStyle.defaultSize
    @AppStorage(SettingsKey.editorTheme) private var theme = "default"
    @AppStorage(SettingsKey.editorFontFamily) private var family = ""
    @AppStorage(SettingsKey.editorFontStyles) private var stylesJSON = ""
    @AppStorage(SettingsKey.editorCursorStyle) private var cursor = CaretShape.bar.rawValue
    @AppStorage(SettingsKey.dimUnfocusedPanes) private var dimPanes = true
    @ObservedObject private var defaults = EditorSettingsObserver.shared   // the override keys are dynamic, so no @AppStorage
    @Environment(\.colorScheme) private var scheme
    @State private var tab = Tab.theme
    @State private var allFonts = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Appearance") {
                    HStack(spacing: 14) { ForEach(AppAppearance.allCases) { card($0) } }
                }
            }
            Section {
                ThemePreview(revision: defaults.revision, size: fontSize, theme: theme)
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets())
            }
            CapsuleSegments(items: Tab.allCases.map { ($0, $0.title) }, selection: $tab)
                .frame(maxWidth: .infinity, alignment: .center)   // centred like Xcode's, not stretched across the pane
                .listRowBackground(Color.clear)
            switch tab {
            case .theme: themeTab
            case .fonts: fontsTab
            case .editor: editorTab
            }
        }
        .pane()
        .onChange(of: appearance) { AppAppearance.apply() }
    }

    private func card(_ a: AppAppearance) -> some View {
        let selected = appearance == a.rawValue
        return Button { appearance = a.rawValue } label: {
            VStack(spacing: 5) {
                AppearanceCard(kind: a)
                    .frame(width: 67, height: 44)
                    // As in System Settings: the chosen picture gets an accent ring with a small gap around it.
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(0.1), lineWidth: 0.5))
                    .padding(4)
                    .overlay { if selected { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3) } }
                Text(a.title).font(.system(size: 13, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Theme

    /// The appearance the color wells edit: the one Settings shows, or dark for a dark-only theme.
    private var editsDark: Bool { base.isDarkOnly || scheme == .dark }
    private var base: EditorTheme { EditorTheme.named(theme) }
    private var overrides: ThemeOverrides { EditorStyle.overrides(theme, dark: editsDark) }

    @ViewBuilder private var themeTab: some View {
        let _ = defaults.revision
        let current = overrides
        let effective = base.applying(light: EditorStyle.overrides(theme, dark: false), dark: EditorStyle.overrides(theme, dark: true))
        Section {
            Picker("Theme", selection: $theme) { ForEach(EditorTheme.all) { Text($0.name).tag($0.id) } }
            LabeledContent("Name", value: base.name)
            LabeledContent("Colors") {
                Button("Restore Defaults") { for dark in [false, true] { EditorStyle.setOverrides(ThemeOverrides(), theme, dark: dark) } }
                    .disabled(effective.lightOverrides.colors.isEmpty && effective.darkOverrides.colors.isEmpty)
            }
            Text(base.isDarkOnly ? "\(base.name) is always dark." : "The colors below are the \(editsDark ? "dark" : "light") variant; switch the appearance above to edit the other.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(EditorTheme.sections, id: \.self) { section in
            Section(LocalizedStringKey(section)) {
                ForEach(EditorTheme.roles.filter { $0.section == section }) { role in
                    LabeledContent(role.title) {
                        HStack {
                            if current.colors[role.key] != nil {
                                Button { set(role, nil) } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.borderless)
                                    .help("Use the theme's color")
                                    .accessibilityLabel("Reset \(role.title)")
                            }
                            ColorPicker(role.title, selection: colorBinding(role, effective), supportsOpacity: true)
                                .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    private func colorBinding(_ role: EditorTheme.ColorRole, _ t: EditorTheme) -> Binding<Color> {
        Binding(get: {
            var c = t.color(role)
            NSAppearance(named: editsDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance { c = c.usingColorSpace(.sRGB) ?? c }
            return Color(nsColor: c)
        }, set: { set(role, NSColor($0).hexString) })
    }

    private func set(_ role: EditorTheme.ColorRole, _ hex: String?) {
        var o = overrides
        o.colors[role.key] = hex
        EditorStyle.setOverrides(o, theme, dark: editsDark)
    }

    // MARK: Fonts

    private static let fixedPitch = Set((NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? [])
        .compactMap { NSFont(name: $0, size: 12)?.familyName }).sorted()
    private static let allFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    @ViewBuilder private var fontsTab: some View {
        let families = (allFonts ? Self.allFamilies : Self.fixedPitch)
        Section("Editor font") {
            Picker("Family", selection: $family) {
                Text("System Monospaced").tag("")
                Divider()
                ForEach(families.contains(family) || family.isEmpty ? families : [family] + families, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Show All Fonts", isOn: $allFonts)
            LabeledContent("Size") {
                Stepper("\(Int(fontSize)) pt", value: $fontSize, in: EditorStyle.sizes, step: 1).monospacedDigit()
            }
        }
        Section("Styles") {
            let styles = EditorStyle.decodeStyles(stylesJSON)
            ForEach(EditorTheme.tags) { row in
                Picker(row.title, selection: Binding(get: { styles[row.tag] ?? row.font }, set: { setStyle(row, $0) })) {
                    ForEach(FontStyle.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }

    private func setStyle(_ row: EditorTheme.TagRow, _ style: FontStyle) {
        var raw = (try? JSONDecoder().decode([String: FontStyle].self, from: Data(stylesJSON.utf8))) ?? [:]
        raw[row.key] = style == row.font ? nil : style
        stylesJSON = raw.isEmpty ? "" : String(decoding: try! JSONEncoder().encode(raw), as: UTF8.self)
    }

    // MARK: Editor

    @ViewBuilder private var editorTab: some View {
        Section("Cursor") {
            Picker("Cursor style", selection: $cursor) { ForEach(CaretShape.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) } }
        }
        Section("Split editor") {
            Toggle("Dim unfocused editor panes", isOn: $dimPanes)
        }
    }
}

/// The picture System Settings › Appearance shows for the same choice, or a small drawn window where macOS has none.
private struct AppearanceCard: View {
    let kind: AppAppearance

    // shortcut: reads a private System Settings bundle, so a macOS update may move it; the drawn card covers that.
    private static let system = Bundle(path: "/System/Library/ExtensionKit/Extensions/Appearance.appex")

    var body: some View {
        let name = switch kind { case .system: "AppearanceAuto"; case .light: "AppearanceLight"; case .dark: "AppearanceDark" }
        if let image = Self.system?.image(forResource: name) {
            Image(nsImage: image).resizable()
                .overlay {    // the bar in the picture takes the accent colour, through System Settings' own mask
                    if let mask = Self.system?.image(forResource: kind == .system ? "selectionColor_mask-auto" : "selectionColor_mask") {
                        Image(nsImage: mask).renderingMode(.template).resizable().foregroundStyle(Color.accentColor)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
        } else {
            drawn
        }
    }

    private var drawn: some View {
        let light = Color(white: 0.93), dark = Color(white: 0.2)
        return ZStack {
            light
            HStack(spacing: 0) { if kind == .system { light }; if kind != .light { dark } }
            RoundedRectangle(cornerRadius: 3)
                .fill(kind == .dark ? Color(white: 0.32) : .white)
                .shadow(radius: 0.5)
                .padding(EdgeInsets(top: 9, leading: 9, bottom: 0, trailing: 0))
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.8)).frame(width: 22, height: 5).padding(EdgeInsets(top: 15, leading: 15, bottom: 0, trailing: 0))
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityHidden(true)
    }
}

/// A read-only sample painted by the real highlighter with the current settings, line numbers in the theme's colors.
private struct ThemePreview: NSViewRepresentable {
    let revision: Int, size: Double, theme: String

    private static let sample = """
        = Appearance
        Some *strong* and _emphasized_ text, see @intro.

        == Introduction <intro>
        $ sum_(k=1)^n k = (n(n+1)) / 2 $
        #let total = calc.round(3.14159, digits: 2)
        #figure(image("plot.png", width: 80%), caption: [A plot])
        // TODO: tune the colors
        ```rust
        fn main() { println!("hi"); }
        ```
        """
    private static let currentLine = 6

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isRichText = false
        tv.textContainerInset = NSSize(width: 4, height: 8)
        tv.setAccessibilityLabel(String(localized: "Theme preview"))
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        EditorStyle.apply(size: size, theme: theme)   // also with no editor open, the highlighter follows Settings
        guard let tv = scroll.documentView as? NSTextView else { return }
        let colors = Highlighter.style.colors
        let code = Highlighter.highlighted(Self.sample)
        let out = NSMutableAttributedString()
        let digits = NSFont.monospacedDigitSystemFont(ofSize: Highlighter.fontSize - 3, weight: .regular)
        var n = 0
        (Self.sample as NSString).enumerateSubstrings(in: NSRange(location: 0, length: code.length), options: [.byLines, .substringNotRequired]) { _, _, line, _ in
            n += 1
            let current = n == Self.currentLine
            out.append(NSAttributedString(string: String(format: "%3d  ", n), attributes: [
                .font: current ? NSFont.monospacedDigitSystemFont(ofSize: digits.pointSize, weight: .semibold) : digits,
                .foregroundColor: current ? colors.rulerCurrent : colors.ruler]))
            let piece = NSMutableAttributedString(attributedString: code.attributedSubstring(from: line))
            if current { piece.addAttribute(.backgroundColor, value: colors.currentLine, range: NSRange(location: 0, length: piece.length)) }
            out.append(piece)
        }
        tv.textStorage?.setAttributedString(out)
        tv.backgroundColor = colors.background
        scroll.backgroundColor = colors.background
        scroll.appearance = Highlighter.style.isDarkOnly ? NSAppearance(named: .darkAqua) : nil
    }
}

/// Xcode's capsule-shaped segmented control: the system segmented picker only has rounded-rectangle corners.
struct CapsuleSegments<T: Hashable>: View {
    let items: [(value: T, title: LocalizedStringKey)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                let on = item.value == selection
                Button { selection = item.value } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .padding(.horizontal, 18)
                        .frame(height: 28)
                        .background { if on { Capsule().fill(Color.accentColor) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                if i < items.count - 1 {
                    // No divider next to the selected segment, as in the system control.
                    Divider().frame(height: 14).opacity(on || items[i + 1].value == selection ? 0 : 1)
                }
            }
        }
        .background(Capsule().fill(.quaternary))
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    AppearanceSettings()
}
