import Foundation
import SwiftUI
import TypoAssistant

extension SettingsKey {
    /// Names of the built-in workflows switched off in Settings › Intelligence › Workflows; every one starts on.
    static let workflowsDisabled = "workflowsDisabled"
    /// Claude skills from ~/.claude/skills switched on for the Claude agent, as `claude-user/name` keys; every skill starts off.
    static let claudeSkillsEnabled = "claudeSkillsEnabled"
    /// Whether Claude Code in Typo also loads the user's own setup from ~/.claude; off, only the project's.
    static let claudeUserSetup = "claudeUserSetup"
    /// Overrides the folder of My Workflows (for tests); unset, it is ~/Library/Application Support/Typo/Workflows.
    static let workflowsDirectory = "workflowsDirectory"
}

/// Typo's built-in workflows and the user's own, and which built-ins are switched on.
@MainActor @Observable final class WorkflowStore {
    static let shared = WorkflowStore()

    /// The workflows that ship in the app (the repository's `Workflows` folder).
    nonisolated static var bundled: WorkflowFolder? {
        Bundle.main.resourceURL.map { WorkflowFolder(url: $0.appending(path: "Workflows", directoryHint: .isDirectory), source: .builtIn) }
    }
    nonisolated static var user: WorkflowFolder {
        let custom = UserDefaults.standard.string(forKey: SettingsKey.workflowsDirectory).map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        return WorkflowFolder(url: custom ?? URL.applicationSupportDirectory.appending(path: "Typo/Workflows", directoryHint: .isDirectory), source: .mine)
    }

    private(set) var builtIns: [Workflow] = []
    private(set) var mine: [Workflow] = []
    private(set) var disabled: Set<String> = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.workflowsDisabled) ?? [])

    init() { reload() }

    func reload() {
        builtIns = Self.bundled?.list() ?? []
        mine = Self.user.list()
    }

    /// The names of My Workflows: a new one must not take one. A built-in's name may be reused, which overrides it.
    var names: Set<String> { Set(mine.map(\.name)) }

    func isOn(_ workflow: Workflow) -> Bool { !disabled.contains(workflow.name) }

    func set(_ workflow: Workflow, on: Bool) {
        if on { disabled.remove(workflow.name) } else { disabled.insert(workflow.name) }
        UserDefaults.standard.set(disabled.sorted(), forKey: SettingsKey.workflowsDisabled)
    }

    /// What `/` offers: My Workflows, then the built-ins that are on and not overridden by one of mine.
    var available: [Workflow] { mine + builtIns.filter { isOn($0) && !names.contains($0.name) } }

    /// The workflow a sent message starts, with the text typed after its name.
    func resolve(_ text: String) -> (workflow: Workflow, arguments: String)? {
        Workflow.resolve(text, builtIns: builtIns.filter(isOn), mine: mine)
    }

    /// Saves one of My Workflows; `old` is its name before a rename.
    func save(_ workflow: Workflow, replacing old: String?) throws {
        try Self.user.save(workflow, replacing: old)
        reload()
    }

    /// Moves one of My Workflows to the Trash.
    func delete(_ workflow: Workflow) throws {
        try FileManager.default.trashItem(at: Self.user.file(workflow.name), resultingItemURL: nil)
        reload()
    }
}

/// The Claude skills of the user's ~/.claude/skills, which Typo hands to the Claude agent when they are switched on.
@MainActor @Observable final class ClaudeSkillStore {
    static let shared = ClaudeSkillStore()

    nonisolated static var plugin: SkillPlugin {
        SkillPlugin(url: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude", directoryHint: .isDirectory), name: "claude-user")
    }

    private(set) var skills: [Skill] = []
    private(set) var enabled: Set<String> = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.claudeSkillsEnabled) ?? [])

    init() { reload() }

    func reload() { skills = Self.plugin.list() }

    func isOn(_ skill: Skill) -> Bool { enabled.contains(Self.plugin.key(skill.name)) }

    func set(_ skill: Skill, on: Bool) {
        if on { enabled.insert(Self.plugin.key(skill.name)) } else { enabled.remove(Self.plugin.key(skill.name)) }
        UserDefaults.standard.set(enabled.sorted(), forKey: SettingsKey.claudeSkillsEnabled)
    }

    /// The plugin folders a Claude Code session loads: a copy of ~/.claude/skills with only the switched-on skills,
    /// under this app's caches. Called when an agent starts, off the main actor.
    nonisolated static func agentPlugins() -> [URL] {
        let enabled = Set(UserDefaults.standard.stringArray(forKey: SettingsKey.claudeSkillsEnabled) ?? [])
        // The app is not sandboxed: the caches folder is shared, so it is namespaced by bundle id.
        let caches = URL.cachesDirectory.appending(path: "\(Bundle.main.bundleIdentifier ?? "Typo")/AgentPlugins", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let plugin = Self.plugin
        return (try? plugin.assemble(into: caches.appending(path: plugin.name, directoryHint: .isDirectory), enabled: enabled)).map { [$0] } ?? []
    }
}
