import Foundation
import SwiftUI
import TypoAssistant

extension SettingsKey {
    /// Skills switched off in Settings › Intelligence › Skills, as `plugin/name` keys; new skills start on.
    static let skillsDisabled = "skillsDisabled"
    /// Overrides the folder of My Skills (for tests); unset, it is ~/Library/Application Support/Typo/Skills.
    static let skillsDirectory = "skillsDirectory"
}

/// Typo's bundled skills and the user's own, as Claude plugins, and which of them are switched on.
@MainActor @Observable final class SkillStore {
    static let shared = SkillStore()

    /// The skills that ship in the app (the repository's `Skills` folder).
    nonisolated static var bundled: SkillPlugin? {
        Bundle.main.resourceURL.map { SkillPlugin(url: $0.appending(path: "Skills", directoryHint: .isDirectory), name: "typo") }
    }
    nonisolated static var user: SkillPlugin {
        let custom = UserDefaults.standard.string(forKey: SettingsKey.skillsDirectory).map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return SkillPlugin(url: custom ?? URL.applicationSupportDirectory.appending(path: "Typo/Skills", directoryHint: .isDirectory), name: "typo-user")
    }

    private(set) var bundledSkills: [Skill] = []
    private(set) var userSkills: [Skill] = []
    private(set) var disabled: Set<String> = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.skillsDisabled) ?? [])

    init() { reload() }

    func reload() {
        bundledSkills = Self.bundled?.list() ?? []
        userSkills = Self.user.list()
    }

    /// Every slug in use, bundled or own: a new skill must not take one.
    var names: Set<String> { Set((bundledSkills + userSkills).map(\.name)) }

    func isOn(_ skill: Skill, in plugin: SkillPlugin) -> Bool { !disabled.contains(plugin.key(skill.name)) }

    func set(_ skill: Skill, in plugin: SkillPlugin, on: Bool) {
        if on { disabled.remove(plugin.key(skill.name)) } else { disabled.insert(plugin.key(skill.name)) }
        persist()
    }

    private func persist() { UserDefaults.standard.set(disabled.sorted(), forKey: SettingsKey.skillsDisabled) }

    /// Saves one of My Skills; `old` is its name before a rename, which keeps its on/off state.
    func save(_ skill: Skill, replacing old: String?) throws {
        try Self.user.save(skill, replacing: old)
        if let old, old != skill.name, disabled.remove(Self.user.key(old)) != nil {
            disabled.insert(Self.user.key(skill.name))
            persist()
        }
        reload()
    }

    /// Moves one of My Skills to the Trash.
    func delete(_ skill: Skill) throws {
        try FileManager.default.trashItem(at: Self.user.folder(skill.name), resultingItemURL: nil)
        set(skill, in: Self.user, on: true)
        reload()
    }

    /// The plugin folders a Claude Code session loads: copies of both plugins with only the switched-on skills,
    /// under this app's caches. Called when an agent starts, off the main actor.
    nonisolated static func agentPlugins() -> [URL] {
        let disabled = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.skillsDisabled) ?? [])
        // The app is not sandboxed: the caches folder is shared, so it is namespaced by bundle id.
        let caches = URL.cachesDirectory.appending(path: "\(Bundle.main.bundleIdentifier ?? "Typo")/AgentPlugins", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        return [bundled, user].compactMap { plugin in
            plugin.flatMap { try? $0.assemble(into: caches.appending(path: $0.name, directoryHint: .isDirectory), disabled: disabled) }
        }
    }
}
