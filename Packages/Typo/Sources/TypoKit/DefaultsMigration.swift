import Foundation

/// One-time copy of the settings stored under the app's old bundle identifier into the current domain.
/// Copy only: the old domain stays, and existing keys are never overwritten.
public enum DefaultsMigration {
    public static let legacyBundleID = "com.example.Tympan"
    public static let marker = "Typo.migratedFromTympan"

    public static func run(from domain: String = legacyBundleID, into defaults: UserDefaults = .standard, marker: String = marker) {
        guard !defaults.bool(forKey: marker) else { return }
        for (k, v) in defaults.persistentDomain(forName: domain) ?? [:] where defaults.object(forKey: k) == nil { defaults.set(v, forKey: k) }
        defaults.set(true, forKey: marker)
    }
}
