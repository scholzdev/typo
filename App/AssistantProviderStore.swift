import Foundation
import SwiftUI
import TypoKit
import TypoAssistant

extension SettingsKey {
    /// JSON of the configured providers, without keys (those are in the Keychain).
    static let assistantProviders = "assistantProviders"
    static let assistantDefaultProvider = "assistantDefaultProvider"
    static let assistantDefaultModel = "assistantDefaultModel"
    /// Provider ids whose first-use notice the user accepted.
    static let assistantConsented = "assistantConsented"
}

/// The model providers of Settings › Intelligence, shared by every window.
@MainActor @Observable final class AssistantProviderStore {
    static let shared = AssistantProviderStore()

    private let keys: any AssistantKeyStoring
    private let defaults: UserDefaults
    /// The user's providers; the on-device one is built in and never stored.
    private(set) var configured: [AssistantProvider]
    /// Providers with a key in the Keychain; cached so rows do not query the Keychain on every render.
    private(set) var keyed: Set<UUID>
    private(set) var onDevice: OnDeviceAvailability = AppleOnDeviceModel.availability

    init(keys: any AssistantKeyStoring = KeychainAssistantKeys(), defaults: UserDefaults = .standard) {
        self.keys = keys
        self.defaults = defaults
        let stored = defaults.data(forKey: SettingsKey.assistantProviders).flatMap { try? JSONDecoder().decode([AssistantProvider].self, from: $0) } ?? []
        configured = stored
        keyed = Set(stored.filter { keys.hasKey(for: $0.id) }.map(\.id))
    }

    /// The on-device provider first, then the configured ones.
    var providers: [AssistantProvider] { [.onDevice] + configured }

    func provider(_ id: UUID?) -> AssistantProvider? { providers.first { $0.id == id } }

    func refreshAvailability() { onDevice = AppleOnDeviceModel.availability }

    func isReady(_ p: AssistantProvider) -> Bool {
        if p.isOnDevice { return onDevice.isAvailable }
        if p.isAgent { return !(p.command ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        return !p.baseURL.trimmingCharacters(in: .whitespaces).isEmpty && (!p.preset.needsKey || keyed.contains(p.id)) && !p.model.isEmpty
    }

    func status(_ p: AssistantProvider) -> String {
        if p.isOnDevice { return onDevice.status }
        if p.isAgent { return isReady(p) ? String(localized: "Ready") : String(localized: "Enter the command") }
        if p.baseURL.trimmingCharacters(in: .whitespaces).isEmpty { return String(localized: "Add base URL") }
        if p.preset.needsKey && !keyed.contains(p.id) { return String(localized: "Add API key") }
        if p.model.isEmpty { return String(localized: "Choose a model") }
        return String(localized: "Ready")
    }

    var hasReadyProvider: Bool { providers.contains(where: isReady) }

    // MARK: Defaults for new conversations

    var defaultProviderID: UUID? {
        get { defaults.string(forKey: SettingsKey.assistantDefaultProvider).flatMap(UUID.init) }
        set { defaults.set(newValue?.uuidString, forKey: SettingsKey.assistantDefaultProvider) }
    }

    /// The chosen default if it is ready, else the first ready configured provider, else on-device.
    var defaultProvider: AssistantProvider? {
        if let p = provider(defaultProviderID), isReady(p) { return p }
        return configured.first(where: isReady) ?? (isReady(.onDevice) ? .onDevice : nil)
    }

    /// The default provider unless it is an agent, else the first ready model: for Explain with AI and table assist,
    /// which ask about a passage rather than give a task.
    var defaultModelProvider: AssistantProvider? {
        if let p = defaultProvider, !p.isAgent { return p }
        return providers.first { !$0.isAgent && isReady($0) }
    }

    func defaultModel(for p: AssistantProvider) -> String {
        if p.id == defaultProviderID, let m = defaults.string(forKey: SettingsKey.assistantDefaultModel), !m.isEmpty { return m }
        return p.model
    }

    // MARK: Editing

    func add(_ p: AssistantProvider) {
        configured.append(p)
        save()
    }

    func update(_ p: AssistantProvider) {
        guard let i = configured.firstIndex(where: { $0.id == p.id }) else { return }
        configured[i] = p
        save()
    }

    /// Removes the provider and its key.
    func remove(_ id: UUID) {
        configured.removeAll { $0.id == id }
        keys.removeKey(for: id)
        keyed.remove(id)
        if defaultProviderID == id { defaultProviderID = nil }
        consented.remove(id)
        save()
    }

    func setKey(_ key: String, for p: AssistantProvider) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return removeKey(for: p) }
        try keys.setKey(trimmed, for: p.id, label: "Typo: \(p.name)")
        keyed.insert(p.id)
    }

    func removeKey(for p: AssistantProvider) {
        keys.removeKey(for: p.id)
        keyed.remove(p.id)
    }

    func client(for p: AssistantProvider) -> any AssistantClient {
        AssistantClients.make(p, key: p.isOnDevice ? nil : keys.key(for: p.id))
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(configured), forKey: SettingsKey.assistantProviders)
    }

    // MARK: First-use notice

    private var consented: Set<UUID> {
        get { Set((defaults.stringArray(forKey: SettingsKey.assistantConsented) ?? []).compactMap(UUID.init)) }
        set { defaults.set(newValue.map(\.uuidString), forKey: SettingsKey.assistantConsented) }
    }

    /// True until the user accepted that files go to this provider; never for on-device.
    func needsConsent(_ p: AssistantProvider) -> Bool { !p.isOnDevice && !consented.contains(p.id) }
    func consent(_ p: AssistantProvider) { consented.insert(p.id) }
}
