import Foundation

/// A server-side capability a request may switch on; the provider runs it.
public enum AssistantTool: String, Sendable, Equatable { case webSearch }

public enum PermissionPolicy: String, Codable, CaseIterable, Sendable {
    case allow, ask, never
    public var title: String {
        switch self { case .allow: "Allow"; case .ask: "Ask"; case .never: "Never" }
    }
}

public enum EditMode: Sendable { case hidden, ask, apply }

/// Everything the assistant may do that the app can enforce.
public enum AssistantPermission: String, Codable, CaseIterable, Identifiable, Sendable {
    case webSearch, readFiles, diagnostics, changeFiles, createFiles, projectFiles, searchProject, viewPreview
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .webSearch: "Search the web"
        case .readFiles: "Read the attached files"
        case .diagnostics: "Include compiler errors"
        case .changeFiles: "Change files"
        case .createFiles: "Create new files"
        case .projectFiles: "Read project files"
        case .searchProject: "Search the project"
        case .viewPreview: "View the preview"
        }
    }

    public var detail: String {
        switch self {
        case .webSearch: "The provider runs web searches for the answer. Your search queries go to the provider."
        case .readFiles: "Files go to the provider only when you attach them. This cannot be turned off."
        case .diagnostics: "“Fix the compile errors” sends the current errors with your message."
        case .changeFiles: "Allow: changes are applied right away and can be reverted. Ask: they are shown and applied when you press Accept. Never: the assistant does not change files."
        case .createFiles: "Allow: new files are created right away and can be reverted. Ask: they are created when you press Accept. Never: the assistant does not create files."
        case .projectFiles: "The assistant may read any file of the project, and its outline, to answer. The text goes to the provider."
        case .searchProject: "The assistant may list the project's files and search them. Matching lines go to the provider."
        case .viewPreview: "The assistant may render a page of the preview as an image to check the layout. The image goes to the provider."
        }
    }

    /// The policies the user can pick; one entry means the permission is fixed.
    public var choices: [PermissionPolicy] {
        switch self {
        case .webSearch, .projectFiles, .searchProject, .viewPreview: [.allow, .ask, .never]
        case .readFiles: [.allow]
        case .diagnostics: [.allow, .never]
        case .changeFiles, .createFiles: [.allow, .ask, .never]
        }
    }

    public var defaultPolicy: PermissionPolicy { [.webSearch, .createFiles, .projectFiles, .viewPreview].contains(self) ? .ask : .allow }
    /// The policy of a conversation toggle that is switched on.
    public var onPolicy: PermissionPolicy { [.webSearch, .projectFiles, .viewPreview].contains(self) ? .allow : defaultPolicy }
}

/// Policies by permission, sparse: a missing entry is the permission's default. Global settings and a
/// conversation's overrides are both one of these.
public struct AssistantPermissions: Codable, Hashable, Sendable {
    var policies: [String: PermissionPolicy] = [:]
    public init() {}

    /// Files saved before "Change files" read "Propose file changes" (`proposeEdits`), whose Allow showed cards to accept:
    /// that is Ask now, since Allow applies right away.
    public init(from decoder: any Decoder) throws {
        policies = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([String: PermissionPolicy].self, forKey: .policies) ?? [:]
        if let old = policies.removeValue(forKey: "proposeEdits"), policies["changeFiles"] == nil { policies["changeFiles"] = old == .allow ? .ask : old }
    }

    public func policy(_ p: AssistantPermission) -> PermissionPolicy {
        policies[p.rawValue].flatMap { p.choices.contains($0) ? $0 : nil } ?? p.defaultPolicy
    }

    public func isSet(_ p: AssistantPermission) -> Bool { policies[p.rawValue] != nil }

    public mutating func set(_ p: AssistantPermission, _ policy: PermissionPolicy?) { policies[p.rawValue] = policy }

    /// These settings with `overrides` on top.
    public func overriding(with overrides: AssistantPermissions?) -> AssistantPermissions {
        var out = self
        for (k, v) in overrides?.policies ?? [:] { out.policies[k] = v }
        return out
    }

    /// What happens to a proposed edit: nothing (hidden), a card to accept, or applied right away. A new file needs
    /// both permissions, and the stricter one wins.
    public func mode(_ edit: ProposedEdit) -> EditMode {
        let policies = edit.search.isEmpty ? [policy(.changeFiles), policy(.createFiles)] : [policy(.changeFiles)]
        return policies.contains(.never) ? .hidden : policies.contains(.ask) ? .ask : .apply
    }

    /// Whether a proposed edit may be shown at all.
    public func shows(_ edit: ProposedEdit) -> Bool { mode(edit) != .hidden }

    /// Whether the model can call client-side functions (`ClientTool`) on this provider; the on-device model gets a few of them.
    public static func supportsTools(provider: AssistantProvider, model: String) -> Bool { true }

    /// Whether the model reads images (`view_preview`): Claude, the GPT-4o/5/6 families and Gemini.
    public static func supportsVision(provider: AssistantProvider, model: String) -> Bool {
        guard !provider.isOnDevice else { return false }
        let id = model.lowercased().split(separator: "/").last.map(String.init) ?? ""
        return ["claude-", "gpt-4o", "chatgpt-4o", "gpt-5", "gpt-6", "gemini"].contains(where: id.hasPrefix)
    }

    /// Whether the provider can run web searches for this model (what the server-side tool needs, not whether the user allows it).
    public static func supportsWebSearch(provider: AssistantProvider, model: String) -> Bool {
        switch provider.preset.wire {
        case .anthropic: model.hasPrefix("claude-")
        // The gateway serves Claude on Messages, GPT on Responses and Gemini on generate-content; the rest has no search.
        case .openCode: ["claude-", "gpt", "gemini"].contains(where: model.hasPrefix)
        case .openAI: provider.presetID == "openrouter"
        case .onDevice, .acp: false
        }
    }
}
