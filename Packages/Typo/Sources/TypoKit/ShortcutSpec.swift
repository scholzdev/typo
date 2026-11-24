import Foundation

/// A keyboard shortcut as data: a key plus modifiers. Independent of SwiftUI so it can be stored and tested here.
public struct ShortcutSpec: Codable, Hashable, Sendable {
    public enum Named: String, Codable, CaseIterable, Sendable {
        case leftArrow, rightArrow, upArrow, downArrow, `return`, tab, space, delete, forwardDelete, escape
        case home, end, pageUp, pageDown
        case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

        public var isFunctionKey: Bool { rawValue.count > 1 && rawValue.hasPrefix("f") && rawValue.dropFirst().allSatisfy(\.isNumber) }

        public var glyph: String {
            switch self {
            case .leftArrow: "←"
            case .rightArrow: "→"
            case .upArrow: "↑"
            case .downArrow: "↓"
            case .return: "↩"
            case .tab: "⇥"
            case .space: "␣"
            case .delete: "⌫"
            case .forwardDelete: "⌦"
            case .escape: "⎋"
            case .home: "↖"
            case .end: "↘"
            case .pageUp: "⇞"
            case .pageDown: "⇟"
            default: rawValue.uppercased()
            }
        }
    }

    public enum Key: Codable, Hashable, Sendable {
        case character(String)
        case named(Named)
    }

    /// Raw values equal SwiftUI's `EventModifiers` (control 4, option 8, shift 2, command 16).
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let option = Modifiers(rawValue: 1 << 3)
        public static let command = Modifiers(rawValue: 1 << 4)
    }

    public var key: Key
    public var modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    public init(_ character: Character, _ modifiers: Modifiers = []) {
        self.init(.character(String(character).lowercased()), modifiers)
    }

    /// The menu notation, e.g. "⌥⌘←": modifiers in the order ⌃⌥⇧⌘, then the key.
    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        switch key {
        case .character(let c): return s + c.uppercased()
        case .named(let n): return s + n.glyph
        }
    }

    /// A rebindable menu shortcut needs ⌘ or ⌃ (a plain key would swallow typing), or is a function key.
    public var isValid: Bool {
        if case .named(let n) = key, n.isFunctionKey { return true }
        return modifiers.contains(.command) || modifiers.contains(.control)
    }

    /// Combinations the editor or the system uses; the recorder refuses them. (⌘W is a command here, so not listed.)
    static let reserved: [ShortcutSpec: String] = [
        ShortcutSpec("q", [.command]): String(localized: "⌘Q quits the app.", bundle: .module),
        ShortcutSpec("h", [.command]): String(localized: "⌘H hides the app.", bundle: .module),
        ShortcutSpec("h", [.command, .option]): String(localized: "⌥⌘H hides the other apps.", bundle: .module),
        ShortcutSpec(",", [.command]): String(localized: "⌘, opens Settings.", bundle: .module),
        ShortcutSpec("c", [.command]): String(localized: "⌘C copies.", bundle: .module),
        ShortcutSpec("v", [.command]): String(localized: "⌘V pastes.", bundle: .module),
        ShortcutSpec("x", [.command]): String(localized: "⌘X cuts.", bundle: .module),
        ShortcutSpec("z", [.command]): String(localized: "⌘Z undoes.", bundle: .module),
        ShortcutSpec("z", [.command, .shift]): String(localized: "⇧⌘Z redoes.", bundle: .module),
        ShortcutSpec("a", [.command]): String(localized: "⌘A selects all.", bundle: .module),
        ShortcutSpec(.named(.f5)): String(localized: "F5 completes in the editor.", bundle: .module),
        ShortcutSpec(.named(.escape), [.option]): String(localized: "⌥Esc completes in the editor.", bundle: .module),
    ]

    /// Why the recorder refuses this combination, or nil when it is allowed.
    public var refusal: String? {
        if let why = Self.reserved[self] { return why }
        return isValid ? nil : String(localized: "Use ⌘ or ⌃ with the key, or a function key.", bundle: .module)
    }

    /// The old "<EventModifiers raw value>:<character>" format of the Jump to Definition setting.
    public init?(legacy: String) {
        let parts = legacy.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let raw = Int(parts[0]), let c = parts[1].first else { return nil }
        let mods = Modifiers(rawValue: raw).intersection([.shift, .control, .option, .command])
        self.init(c, mods)
    }

    /// For each spec bound to more than one command, the commands' ids.
    public static func conflicts(_ bindings: [(id: String, spec: ShortcutSpec)]) -> [ShortcutSpec: [String]] {
        Dictionary(grouping: bindings, by: \.spec).mapValues { $0.map(\.id) }.filter { $0.value.count > 1 }
    }
}

/// The user's changes to command shortcuts by command id; an explicit nil means "shortcut removed".
public struct ShortcutOverrides: Codable, Equatable, Sendable {
    public var values: [String: ShortcutSpec?] = [:]

    public init(_ values: [String: ShortcutSpec?] = [:]) { self.values = values }

    public init(from decoder: Decoder) throws { values = try decoder.singleValueContainer().decode([String: ShortcutSpec?].self) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }

    /// The override for `id`, or `fallback` when the command has none.
    public func effective(_ id: String, default fallback: ShortcutSpec?) -> ShortcutSpec? {
        values[id] ?? fallback
    }
}
