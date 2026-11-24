import SwiftUI
import TypoAssistant

/// Settings › Intelligence › Claude › Skills: which of the user's Claude Code skills (~/.claude/skills) Claude loads in Typo.
struct ClaudeSkillsSettings: View {
    private let store = ClaudeSkillStore.shared
    @AppStorage(SettingsKey.claudeUserSetup) private var userSetup = false

    var body: some View {
        Form {
            Section {
                ForEach(store.skills) { skill in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(skill.name, isOn: Binding(get: { userSetup || store.isOn(skill) }, set: { store.set(skill, on: $0) }))
                            .toggleStyle(.switch)
                        if !skill.description.isEmpty {
                            Text(skill.description).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                if store.skills.isEmpty {
                    Text("No skills in ~/.claude/skills.").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Claude loads the skills you turn on here. With “Use my Claude Code setup” on, it loads all of them anyway.")
            }
            .disabled(userSetup)
        }
        .pane()
        .onAppear { store.reload() }
    }
}
