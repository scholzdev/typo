import SwiftUI
import TypoKit
import TypoAssistant

extension SettingsKey {
    /// JSON of the global `AssistantPermissions`.
    static let assistantPermissions = "assistantPermissions"
}

extension AssistantPermissions {
    /// The global defaults from Settings › Intelligence.
    static var stored: AssistantPermissions {
        get { UserDefaults.standard.data(forKey: SettingsKey.assistantPermissions).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self() }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: SettingsKey.assistantPermissions) }
    }
}

/// Settings › Intelligence › Permissions: what the assistant may do by default.
struct AssistantPermissionsSection: View {
    @State private var permissions = AssistantPermissions.stored

    var body: some View {
        Section("Permissions") {
            ForEach(AssistantPermission.allCases) { p in
                VStack(alignment: .leading, spacing: 2) {
                    if p.choices.count > 1 {
                        Picker(p.title, selection: Binding(get: { permissions.policy(p) }, set: { permissions.set(p, $0) })) {
                            ForEach(p.choices, id: \.self) { Text($0.title).tag($0) }
                        }
                    } else {
                        LabeledContent(p.title, value: "Always on")
                    }
                    Text(p.detail).font(.caption).foregroundStyle(.secondary)
                    if p == .webSearch {
                        Text("Works with Claude, GPT and Gemini models (also through OpenCode) and with OpenRouter.").font(.caption).foregroundStyle(.secondary)
                    }
                    if p == .viewPreview {
                        Text("Works with Claude, GPT-4o/5/6 and Gemini models.").font(.caption).foregroundStyle(.secondary)
                    }
                    if p == .projectFiles || p == .searchProject {
                        Text("Works with Claude, GPT, Gemini and other models that call functions. The on-device model can only read outlines.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("The defaults of every conversation. The shield button above a conversation changes them for that conversation only.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: permissions) { AssistantPermissions.stored = permissions }
    }
}

/// "This conversation may:" in the sidebar header: the permissions as toggles over the defaults.
struct AssistantPermissionsPopover: View {
    @Bindable var model: AssistantModel

    var body: some View {
        let effective = model.permissions
        VStack(alignment: .leading, spacing: 10) {
            Text("This conversation may:").font(.headline)
            ForEach(AssistantPermission.allCases) { p in row(p, effective.policy(p)) }
            Divider()
            HStack {
                Text("Defaults are set in Settings › Intelligence.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { model.resetPermissions() }.controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private func row(_ p: AssistantPermission, _ policy: PermissionPolicy) -> some View {
        let searchMissing = (p == .webSearch && !model.canSearch) || ((p == .projectFiles || p == .searchProject) && !model.canUseTools) || (p == .viewPreview && !model.canSeeImages)
        VStack(alignment: .leading, spacing: 2) {
            if p.choices.count == 1 {
                Toggle(p.title, isOn: .constant(true)).disabled(true)
            } else {
                Toggle(p.title, isOn: Binding(get: { p == .changeFiles || p == .createFiles ? policy != .never : policy == p.onPolicy },
                                              set: { model.setPermission(p, $0 ? p.onPolicy : .never) }))
                    .disabled(searchMissing)
            }
            Text(searchMissing ? "Not available with \(model.provider?.name ?? "this provider")" : policy == .ask && p == .webSearch ? "Asks before each message" : policy == .ask && p == .projectFiles ? "Asks before reading a file" : policy == .ask && p == .viewPreview ? "Asks before looking at the preview" : policy == .ask && (p == .changeFiles || p == .createFiles) ? "Shows a card to accept first" : policy == .allow && p == .changeFiles ? "Applies changes right away" : policy == .allow && p == .createFiles ? "Creates files right away" : p.detail)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
