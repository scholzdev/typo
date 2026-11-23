import Foundation

/// Named shortcut sets. "Default" (no overrides) and "Vim" are built in and read-only; the others are the user's.
public struct ShortcutSets: Codable, Equatable, Sendable {
    public static let defaultName = "Default"
    public static let customName = "Custom"
    public static let vimName = "Vim"
    public static let vimDescription = "For Vim habits: moves Re-Indent from ⌃I (Vim's jump-forward key, also Tab) to ⌥⌘I. Every other app shortcut is a ⌘ or ⌃⇧ chord and stays."
    /// Overrides of the built-in sets by name; Default has none.
    public static let builtIns: [String: ShortcutOverrides] = [
        vimName: ShortcutOverrides(["Format/Re-Indent": .some(ShortcutSpec("i", [.command, .option]))]),
    ]

    public private(set) var sets: [String: ShortcutOverrides] = [:]
    public private(set) var selected = ShortcutSets.defaultName

    public init() {}

    /// The overrides saved before sets existed become the selected set "Custom"; none leaves Default selected.
    public init(migrating legacy: ShortcutOverrides) {
        guard !legacy.values.isEmpty else { return }
        sets[Self.customName] = legacy
        selected = Self.customName
    }

    public var names: [String] { [Self.defaultName] + Self.builtIns.keys.sorted() + sets.keys.sorted() }
    public var isDefault: Bool { selected == Self.defaultName }
    public var isBuiltIn: Bool { isDefault || Self.builtIns[selected] != nil }
    public var current: ShortcutOverrides { Self.builtIns[selected] ?? sets[selected] ?? ShortcutOverrides() }

    public mutating func select(_ name: String) { if names.contains(name) { selected = name } }

    /// Changes the selected set; on a built-in set that first creates a set copied from it (built-ins are never edited).
    public mutating func edit(_ change: (inout ShortcutOverrides) -> Void) {
        if isBuiltIn {
            let copy = current
            selected = uniqueName(isDefault ? Self.customName : "\(selected) Custom")
            sets[selected] = copy
        }
        change(&sets[selected]!)
    }

    /// Clears the selected user set's changes; built-in sets have none.
    public mutating func resetCurrent() { if !isBuiltIn { sets[selected] = ShortcutOverrides() } }

    /// Copies the selected set under `name` and selects the copy; false when the name is not usable.
    @discardableResult public mutating func duplicate(as name: String) -> Bool {
        guard let n = usable(name) else { return false }
        sets[n] = current
        selected = n
        return true
    }

    @discardableResult public mutating func rename(to name: String) -> Bool {
        guard !isBuiltIn, let n = usable(name, allowing: selected) else { return false }
        sets[n] = sets.removeValue(forKey: selected)
        selected = n
        return true
    }

    public mutating func deleteCurrent() {
        guard !isBuiltIn else { return }
        sets[selected] = nil
        selected = Self.defaultName
    }

    /// `base`, or "base 2", "base 3" … when taken.
    public func uniqueName(_ base: String) -> String {
        let taken = Set(names)
        if !taken.contains(base) { return base }
        return (2...).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) }!
    }

    private func usable(_ name: String, allowing own: String? = nil) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty || (n != own && names.contains(n)) ? nil : n
    }
}
