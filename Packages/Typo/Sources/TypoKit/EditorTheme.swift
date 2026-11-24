import Foundation
import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// One editor color scheme (design/14e): syntax colors plus the editor's own surfaces. A theme with a light and a
/// dark table follows the appearance through dynamic colors; a dark-only theme asks the app for a dark appearance.
/// The user's customization is a set of overrides per appearance on top of a built-in theme (`applying`).
public struct EditorTheme: Identifiable {
    /// One appearance's colors. The fills (current line, selections) carry their alpha: they are drawn over the text.
    public struct Palette {
        public var text, background, currentLine, selection, inactiveSelection, ruler, rulerCurrent: PlatformColor
        public var comment, keyword, string, number, function, label, raw, math, escape, interpolated, error: PlatformColor
        public var cursor = EditorTheme.insertionPoint, gitAdded = PlatformColor.systemGreen
        public var gitModified = PlatformColor.systemBlue, gitDeleted = PlatformColor.systemRed
    }

    /// One user-editable color: its override key, its row in Settings and where it lives in a palette.
    public struct ColorRole: Sendable, Identifiable {
        public let key: String, title: String, section: String
        let path: WritableKeyPath<Palette, PlatformColor> & Sendable
        public var id: String { key }
    }

    /// The one role table: it drives the palette merge, the overrides, the Settings rows and the tests.
    public static let roles: [ColorRole] = [
        .init(key: "comment", title: String(localized: "Comments", bundle: .module), section: "Text", path: \.comment),
        .init(key: "keyword", title: String(localized: "Keywords", bundle: .module), section: "Text", path: \.keyword),
        .init(key: "string", title: String(localized: "Strings", bundle: .module), section: "Text", path: \.string),
        .init(key: "number", title: String(localized: "Numbers", bundle: .module), section: "Text", path: \.number),
        .init(key: "function", title: String(localized: "Functions", bundle: .module), section: "Text", path: \.function),
        .init(key: "label", title: String(localized: "Labels and References", bundle: .module), section: "Text", path: \.label),
        .init(key: "raw", title: String(localized: "Raw", bundle: .module), section: "Text", path: \.raw),
        .init(key: "math", title: String(localized: "Math", bundle: .module), section: "Text", path: \.math),
        .init(key: "escape", title: String(localized: "Escapes", bundle: .module), section: "Text", path: \.escape),
        .init(key: "interpolated", title: String(localized: "Interpolation", bundle: .module), section: "Text", path: \.interpolated),
        .init(key: "error", title: String(localized: "Errors", bundle: .module), section: "Text", path: \.error),
        .init(key: "text", title: String(localized: "Text", bundle: .module), section: "Editor", path: \.text),
        .init(key: "background", title: String(localized: "Background", bundle: .module), section: "Editor", path: \.background),
        .init(key: "currentLine", title: String(localized: "Current line", bundle: .module), section: "Editor", path: \.currentLine),
        .init(key: "selection", title: String(localized: "Selection", bundle: .module), section: "Editor", path: \.selection),
        .init(key: "inactiveSelection", title: String(localized: "Inactive selection", bundle: .module), section: "Editor", path: \.inactiveSelection),
        .init(key: "cursor", title: String(localized: "Cursor", bundle: .module), section: "Editor", path: \.cursor),
        .init(key: "ruler", title: String(localized: "Line numbers", bundle: .module), section: "Editor", path: \.ruler),
        .init(key: "rulerCurrent", title: String(localized: "Current line number", bundle: .module), section: "Editor", path: \.rulerCurrent),
        .init(key: "gitAdded", title: String(localized: "Additions", bundle: .module), section: "Source Control", path: \.gitAdded),
        .init(key: "gitModified", title: String(localized: "Modifications", bundle: .module), section: "Source Control", path: \.gitModified),
        .init(key: "gitDeleted", title: String(localized: "Deletions", bundle: .module), section: "Source Control", path: \.gitDeleted),
    ]
    public static let sections = ["Text", "Editor", "Source Control"]

    /// How each syntax tag is drawn: its color role (nil: a color derived below) and its default font style.
    public struct TagRow: Sendable, Identifiable {
        public let tag: SyntaxTag, title: String, font: FontStyle
        let color: (KeyPath<Palette, PlatformColor> & Sendable)?
        public var id: String { key }
        /// The tag's name, the key of a font style override.
        public var key: String { "\(tag)" }
    }

    public static let tags: [TagRow] = [
        .init(tag: .heading, title: String(localized: "Headings", bundle: .module), font: .bold, color: \Palette.text),
        .init(tag: .strong, title: String(localized: "Strong", bundle: .module), font: .bold, color: \Palette.text),
        .init(tag: .emph, title: String(localized: "Emphasis", bundle: .module), font: .italic, color: \Palette.text),
        .init(tag: .listMarker, title: String(localized: "List markers", bundle: .module), font: .regular, color: \Palette.keyword),
        .init(tag: .listTerm, title: String(localized: "Term list terms", bundle: .module), font: .bold, color: \Palette.text),
        .init(tag: .link, title: String(localized: "Links", bundle: .module), font: .regular, color: \Palette.function),
        .init(tag: .comment, title: String(localized: "Comments", bundle: .module), font: .regular, color: \Palette.comment),
        .init(tag: .todo, title: String(localized: "TODO markers", bundle: .module), font: .bold, color: nil),
        .init(tag: .punctuation, title: String(localized: "Punctuation", bundle: .module), font: .regular, color: \Palette.comment),
        .init(tag: .escape, title: String(localized: "Escapes", bundle: .module), font: .regular, color: \Palette.escape),
        .init(tag: .keyword, title: String(localized: "Keywords", bundle: .module), font: .regular, color: \Palette.keyword),
        .init(tag: .operator, title: String(localized: "Operators", bundle: .module), font: .regular, color: \Palette.keyword),
        .init(tag: .function, title: String(localized: "Functions", bundle: .module), font: .regular, color: \Palette.function),
        .init(tag: .string, title: String(localized: "Strings", bundle: .module), font: .regular, color: \Palette.string),
        .init(tag: .number, title: String(localized: "Numbers", bundle: .module), font: .regular, color: \Palette.number),
        .init(tag: .unit, title: String(localized: "Units", bundle: .module), font: .regular, color: nil),
        .init(tag: .label, title: String(localized: "Labels", bundle: .module), font: .regular, color: \Palette.label),
        .init(tag: .ref, title: String(localized: "References", bundle: .module), font: .regular, color: \Palette.label),
        .init(tag: .raw, title: String(localized: "Raw", bundle: .module), font: .regular, color: \Palette.raw),
        .init(tag: .mathDelimiter, title: String(localized: "Math delimiters", bundle: .module), font: .regular, color: \Palette.math),
        .init(tag: .mathOperator, title: String(localized: "Math operators", bundle: .module), font: .regular, color: \Palette.math),
        .init(tag: .mathGroupingParens, title: String(localized: "Math parentheses", bundle: .module), font: .regular, color: \Palette.math),
        .init(tag: .interpolated, title: String(localized: "Interpolation", bundle: .module), font: .regular, color: \Palette.interpolated),
        .init(tag: .error, title: String(localized: "Errors", bundle: .module), font: .regular, color: \Palette.error),
    ]

    public let id: String
    public let name: String
    public let isDarkOnly: Bool
    public let colors: Palette
    /// The highlighter's map, built once so a theme's colors keep their identity.
    public let syntax: [SyntaxTag: Style]
    /// The built-in tables and the overrides applied to them; a dark-only theme uses only `dark`.
    private(set) var lightPalette: Palette, darkPalette: Palette?
    public private(set) var lightOverrides = ThemeOverrides(), darkOverrides = ThemeOverrides()

    init(id: String, name: String, light: Palette, dark: Palette?, darkOnly: Bool = false) {
        self.id = id
        self.name = name
        isDarkOnly = darkOnly
        lightPalette = light
        darkPalette = dark
        colors = dark.map { Self.merge(light, $0) } ?? light
        syntax = Self.syntax(colors)
    }

    /// Roles that are the same object in both tables stay that object, so an untouched system color keeps its identity.
    private static func merge(_ light: Palette, _ dark: Palette) -> Palette {
        var out = light
        for r in roles where light[keyPath: r.path] !== dark[keyPath: r.path] {
            out[keyPath: r.path] = .dynamic(light: light[keyPath: r.path], dark: dark[keyPath: r.path])
        }
        return out
    }

    /// Every theme assigns the same roles to the same tags.
    private static func syntax(_ c: Palette) -> [SyntaxTag: Style] {
        var out: [SyntaxTag: Style] = [:]
        for row in tags {
            let color: PlatformColor = switch row.tag {
            case .todo: .systemOrange
            case .unit: .blend(c.number, c.math)     // number pulled toward math, so `2cm` reads as one token with two parts
            default: c[keyPath: row.color!]
            }
            out[row.tag] = Style(color, bold: row.font.bold, italic: row.font.italic)
        }
        return out
    }

    /// This theme with the user's colors on top; overrides with no valid color are ignored.
    public func applying(light: ThemeOverrides, dark: ThemeOverrides) -> EditorTheme {
        var t: EditorTheme
        if isDarkOnly {
            t = EditorTheme(id: id, name: name, light: lightPalette.overridden(by: dark), dark: nil, darkOnly: true)
        } else {
            t = EditorTheme(id: id, name: name, light: lightPalette.overridden(by: light),
                            dark: (darkPalette ?? lightPalette).overridden(by: dark))
        }
        (t.lightPalette, t.darkPalette) = (lightPalette, darkPalette)   // overrides always apply to the built-in tables
        t.lightOverrides = isDarkOnly ? ThemeOverrides() : light
        t.darkOverrides = dark
        return t
    }

    /// The built-in color of `role`, before any override: what "reset" returns to.
    public func builtIn(_ role: ColorRole, dark: Bool) -> PlatformColor {
        (dark && !isDarkOnly ? darkPalette ?? lightPalette : lightPalette)[keyPath: role.path]
    }

    public func color(_ role: ColorRole) -> PlatformColor { colors[keyPath: role.path] }

    @MainActor public static let all: [EditorTheme] = [.standard, .solarized, .github, .dracula]
    @MainActor public static func named(_ id: String) -> EditorTheme { all.first { $0.id == id } ?? .standard }
}

/// A theme customization for one appearance: role key to `RRGGBBAA` sRGB hex.
public struct ThemeOverrides: Codable, Equatable, Sendable {
    public var colors: [String: String]
    public init(colors: [String: String] = [:]) { self.colors = colors }
}

/// The font face of a syntax tag (Settings, Fonts).
public enum FontStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case regular, bold, italic, boldItalic
    public var id: String { rawValue }
    public var bold: Bool { self == .bold || self == .boldItalic }
    public var italic: Bool { self == .italic || self == .boldItalic }
    public var title: String { switch self { case .regular: "Regular"; case .bold: "Bold"; case .italic: "Italic"; case .boldItalic: "Bold Italic" } }
    init(bold: Bool, italic: Bool) { self = bold ? (italic ? .boldItalic : .bold) : (italic ? .italic : .regular) }
}

extension EditorTheme.Palette {
    func overridden(by o: ThemeOverrides) -> Self {
        var p = self
        for r in EditorTheme.roles { if let hex = o.colors[r.key], let c = PlatformColor.hex(string: hex) { p[keyPath: r.path] = c } }
        return p
    }
}

extension EditorTheme {
    #if canImport(AppKit)
    private static let systemText = NSColor.textColor, systemSecondary = NSColor.secondaryLabelColor
    private static let systemBackground = NSColor.textBackgroundColor
    private static let systemSelection = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45)
    private static let systemInactive = NSColor.unemphasizedSelectedTextBackgroundColor.withAlphaComponent(0.6)
    private static let systemAccent = NSColor.controlAccentColor.withAlphaComponent(0.10)
    private static let systemLabel = NSColor.labelColor
    static let insertionPoint = NSColor.textInsertionPointColor
    #else
    private static let systemText = UIColor.label, systemSecondary = UIColor.secondaryLabel
    private static let systemBackground = UIColor.systemBackground
    private static let systemSelection = UIColor.tintColor.withAlphaComponent(0.3)
    private static let systemInactive = UIColor.systemGray.withAlphaComponent(0.3)
    private static let systemAccent = UIColor.tintColor.withAlphaComponent(0.10)
    private static let systemLabel = UIColor.label
    static let insertionPoint = UIColor.tintColor
    #endif

    /// Xcode-like system colors: the editor as it looked before themes.
    @MainActor static let standard = EditorTheme(id: "default", name: "Default", light: Palette(
        text: systemText, background: systemBackground, currentLine: systemAccent, selection: systemSelection,
        inactiveSelection: systemInactive, ruler: systemSecondary, rulerCurrent: systemLabel,
        comment: systemSecondary, keyword: .systemPink, string: .systemRed, number: .systemPurple, function: .systemBlue,
        label: .systemGreen, raw: .systemBrown, math: .systemTeal, escape: .systemOrange, interpolated: .systemIndigo, error: .systemRed),
        dark: nil)

    @MainActor static let solarized: EditorTheme = {
        func accents(_ p: inout Palette) {
            p.keyword = .hex(0x859900); p.string = .hex(0x2aa198); p.number = .hex(0xd33682); p.function = .hex(0x268bd2)
            p.label = .hex(0x6c71c4); p.raw = .hex(0xb58900); p.math = .hex(0xcb4b16); p.escape = .hex(0xdc322f)
            p.interpolated = .hex(0x6c71c4); p.error = .hex(0xdc322f)
        }
        var light = Palette.plain(text: 0x657b83, background: 0xfdf6e3, comment: 0x93a1a1, ruler: 0x93a1a1, rulerCurrent: 0x586e75,
                                  currentLine: (0x93a1a1, 0.12), selection: (0x268bd2, 0.22), inactive: (0x93a1a1, 0.25))
        var dark = Palette.plain(text: 0x839496, background: 0x002b36, comment: 0x586e75, ruler: 0x586e75, rulerCurrent: 0x93a1a1,
                                 currentLine: (0x93a1a1, 0.08), selection: (0x268bd2, 0.35), inactive: (0x93a1a1, 0.18))
        accents(&light)
        accents(&dark)
        return EditorTheme(id: "solarized", name: "Solarized", light: light, dark: dark)
    }()

    @MainActor static let github: EditorTheme = {
        var light = Palette.plain(text: 0x1f2328, background: 0xffffff, comment: 0x6e7781, ruler: 0x8c959f, rulerCurrent: 0x1f2328,
                                  currentLine: (0x8c959f, 0.12), selection: (0x0969da, 0.2), inactive: (0x8c959f, 0.2))
        light.keyword = .hex(0xcf222e); light.string = .hex(0x0a3069); light.number = .hex(0x0550ae); light.function = .hex(0x8250df)
        light.label = .hex(0x116329); light.raw = .hex(0x953800); light.math = .hex(0x0550ae); light.escape = .hex(0x0550ae)
        light.interpolated = .hex(0x953800); light.error = .hex(0x82071e)
        var dark = Palette.plain(text: 0xe6edf3, background: 0x0d1117, comment: 0x8b949e, ruler: 0x6e7681, rulerCurrent: 0xe6edf3,
                                 currentLine: (0x6e7681, 0.15), selection: (0x388bfd, 0.3), inactive: (0x6e7681, 0.25))
        dark.keyword = .hex(0xff7b72); dark.string = .hex(0xa5d6ff); dark.number = .hex(0x79c0ff); dark.function = .hex(0xd2a8ff)
        dark.label = .hex(0x7ee787); dark.raw = .hex(0xffa657); dark.math = .hex(0x79c0ff); dark.escape = .hex(0x79c0ff)
        dark.interpolated = .hex(0xffa657); dark.error = .hex(0xffa198)
        return EditorTheme(id: "github", name: "GitHub", light: light, dark: dark)
    }()

    @MainActor static let dracula: EditorTheme = {
        var p = Palette.plain(text: 0xf8f8f2, background: 0x282a36, comment: 0x6272a4, ruler: 0x6272a4, rulerCurrent: 0xf8f8f2,
                              currentLine: (0xf8f8f2, 0.06), selection: (0xbd93f9, 0.25), inactive: (0x6272a4, 0.3))
        p.keyword = .hex(0xff79c6); p.string = .hex(0xf1fa8c); p.number = .hex(0xbd93f9); p.function = .hex(0x50fa7b)
        p.label = .hex(0x8be9fd); p.raw = .hex(0xffb86c); p.math = .hex(0xbd93f9); p.escape = .hex(0xff79c6)
        p.interpolated = .hex(0xffb86c); p.error = .hex(0xff5555)
        return EditorTheme(id: "dracula", name: "Dracula", light: p, dark: nil, darkOnly: true)
    }()
}

extension EditorTheme.Palette {
    /// Surfaces set, every syntax role the text color until the theme assigns it.
    static func plain(text: Int, background: Int, comment: Int, ruler: Int, rulerCurrent: Int,
                      currentLine: (Int, CGFloat), selection: (Int, CGFloat), inactive: (Int, CGFloat)) -> Self {
        let t = PlatformColor.hex(text)
        return Self(text: t, background: .hex(background), currentLine: .hex(currentLine.0, alpha: currentLine.1),
                    selection: .hex(selection.0, alpha: selection.1), inactiveSelection: .hex(inactive.0, alpha: inactive.1),
                    ruler: .hex(ruler), rulerCurrent: .hex(rulerCurrent), comment: .hex(comment), keyword: t, string: t, number: t,
                    function: t, label: t, raw: t, math: t, escape: t, interpolated: t, error: t)
    }
}

extension PlatformColor {
    public static func hex(_ rgb: Int, alpha: CGFloat = 1) -> PlatformColor {
        let r = CGFloat((rgb >> 16) & 0xff) / 255, g = CGFloat((rgb >> 8) & 0xff) / 255, b = CGFloat(rgb & 0xff) / 255
        #if canImport(AppKit)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
        #else
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
        #endif
    }

    /// `RRGGBB` or `RRGGBBAA`, with or without a leading `#`.
    public static func hex(string: String) -> PlatformColor? {
        let s = string.hasPrefix("#") ? String(string.dropFirst()) : string
        guard s.count == 6 || s.count == 8, let v = Int(s, radix: 16) else { return nil }
        return s.count == 6 ? hex(v) : hex(v >> 8, alpha: CGFloat(v & 0xff) / 255)
    }

    /// `RRGGBBAA` in sRGB, as stored in `ThemeOverrides`.
    public var hexString: String {
        var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
        #if canImport(AppKit)
        (usingColorSpace(.sRGB) ?? self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        func h(_ x: CGFloat) -> String { String(format: "%02X", Int((min(max(x, 0), 1) * 255).rounded())) }
        return h(r) + h(g) + h(b) + h(a)
    }

    static func dynamic(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(AppKit)
        return NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
        #else
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        #endif
    }

    /// `a` pulled 45 % toward `b`, resolved per appearance.
    static func blend(_ a: PlatformColor, _ b: PlatformColor) -> PlatformColor {
        #if canImport(AppKit)
        return NSColor(name: nil) { appearance in
            var out = a
            appearance.performAsCurrentDrawingAppearance { out = a.blended(withFraction: 0.45, of: b) ?? a }
            return out
        }
        #else
        return UIColor { trait in
            var (r, g, bl, al) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            var (r2, g2, b2) = (CGFloat(0), CGFloat(0), CGFloat(0))
            a.resolvedColor(with: trait).getRed(&r, green: &g, blue: &bl, alpha: &al)
            b.resolvedColor(with: trait).getRed(&r2, green: &g2, blue: &b2, alpha: nil)
            return UIColor(red: r * 0.55 + r2 * 0.45, green: g * 0.55 + g2 * 0.45, blue: bl * 0.55 + b2 * 0.45, alpha: al)
        }
        #endif
    }
}

#if canImport(AppKit)
extension EditorTheme.Palette {
    /// The tab bar's fill (design/14h): the editor background, darker in a dark theme and a little greyer in a light one.
    public var tabBar: NSColor {
        let bg = background
        return NSColor(name: nil) { appearance in
            var out = bg
            appearance.performAsCurrentDrawingAppearance {
                let c = bg.usingColorSpace(.sRGB) ?? bg
                out = c.blended(withFraction: c.brightnessComponent < 0.5 ? 0.3 : 0.06, of: .black) ?? c
            }
            return out
        }
    }
}
#endif

extension Highlighter {
    /// The editor font: `family` (nil: the system monospaced font) in the regular or bold face. A family without a
    /// bold face falls back to the bold system font.
    public static func font(size: CGFloat, bold: Bool = false, family: String? = nil) -> PlatformFont {
        #if canImport(AppKit)
        if let family, let f = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size),
           !bold || f.fontDescriptor.symbolicTraits.contains(.bold) { return f }
        #endif
        return .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    /// The face of a font style: the family's real italic when it has one, else the upright face with a synthetic slant.
    static func face(_ s: FontStyle, size: CGFloat, family: String?) -> (font: PlatformFont, oblique: Bool) {
        let upright = font(size: size, bold: s.bold, family: family)
        guard s.italic else { return (upright, false) }
        #if canImport(AppKit)
        let d = upright.fontDescriptor
        if let f = NSFont(descriptor: d.withSymbolicTraits(d.symbolicTraits.union(.italic)), size: size),
           f.fontDescriptor.symbolicTraits.contains(.italic), f.familyName == upright.familyName { return (f, false) }
        #endif
        return (upright, true)
    }

    /// The app's settings, passed in. True when something changed: the app then restyles the open buffers.
    /// `styles` overrides the font style of single tags over the theme's defaults.
    public static func configure(_ t: EditorTheme, fontSize size: CGFloat, family: String? = nil, styles: [SyntaxTag: FontStyle] = [:]) -> Bool {
        guard t.id != style.id || t.lightOverrides != style.lightOverrides || t.darkOverrides != style.darkOverrides
                || size != fontSize || family != fontFamily || styles != fontStyles else { return false }
        style = t
        theme = t.syntax
        for (tag, f) in styles { theme[tag]?.bold = f.bold; theme[tag]?.italic = f.italic }
        fontSize = size
        fontFamily = family
        fontStyles = styles
        baseFont = font(size: size, family: family)
        faces = Dictionary(uniqueKeysWithValues: FontStyle.allCases.map { ($0, face($0, size: size, family: family)) })
        revision += 1
        return true
    }

    /// Detached Typst source painted with the configured theme and font exactly as an open file would be (no Project).
    public static func highlighted(_ text: String) -> NSAttributedString {
        let s = NSTextStorage(string: text)
        recolor(s, SyntaxMirror(text), NSRange(location: 0, length: s.length))
        return s
    }
}

extension Buffer {
    /// Repaints the whole file with the current theme and font, as one attribute-only edit (no undo, no engine).
    public func restyle() {
        storage.beginEditing()
        recolor(NSRange(location: 0, length: storage.length))
        syncKerns()
        storage.endEditing()
    }
}

extension Project {
    public func restyleBuffers() { for b in buffers.values { b.restyle() } }
}
