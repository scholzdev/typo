import Foundation

/// One-time copy of the sandboxed build's prefs and app data into the real home, for the unsandboxed build.
/// Copy only: the container stays intact so a sandboxed build keeps working.
public enum SandboxMigration {
    static let marker = "TypstCore.sandboxMigrated"
    /// Folders under Library/Application Support that are merged, item by item, without overwriting.
    // persisted folder name, kept from the app's old name so saved data survives
    static let folders = ["Tympan", "typst/packages"]

    /// `container` is ~/Library/Containers/<bundle id>/Data; `home` the real home directory.
    public static func run(container: URL, home: URL, defaults: UserDefaults = .standard, fileManager fm: FileManager = .default) {
        let prefs = container.appending(path: "Library/Preferences/\(Bundle.main.bundleIdentifier ?? "").plist")
        run(container: container, home: home, prefs: prefs, defaults: defaults, fileManager: fm)
    }

    static func run(container: URL, home: URL, prefs: URL, defaults: UserDefaults, fileManager fm: FileManager) {
        guard !defaults.bool(forKey: marker) else { return }
        if let data = try? Data(contentsOf: prefs),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for (k, v) in dict where defaults.object(forKey: k) == nil { defaults.set(v, forKey: k) }
        }
        let support = "Library/Application Support/"
        for f in folders { merge(container.appending(path: support + f), into: home.appending(path: support + f), fm) }
        defaults.set(true, forKey: marker)
    }

    private static func merge(_ src: URL, into dst: URL, _ fm: FileManager) {
        guard let items = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for item in items {
            let target = dst.appending(path: item.lastPathComponent)
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                merge(item, into: target, fm)
            } else if !fm.fileExists(atPath: target.path) {
                try? fm.copyItem(at: item, to: target)
            }
        }
    }
}
