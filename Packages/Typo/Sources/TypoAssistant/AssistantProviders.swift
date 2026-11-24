import Foundation
import Security

/// The protocols providers speak; `acp` is an agent on this Mac (Agent Client Protocol over stdio).
public enum AssistantWire: String, Codable, Sendable { case anthropic, openAI, onDevice, openCode, acp }

/// One row of the provider table; the settings UI and the clients are driven by it.
public struct AssistantPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let organization: String
    public let wire: AssistantWire
    /// nil: the user enters the base URL (it holds an account-specific host).
    public let baseURL: String?
    public let chatPath: String
    /// nil: no model list; the user types the model id.
    public let modelsPath: String?
    public let needsKey: Bool
    public let isLocal: Bool
    public let caption: String
    /// Offered in the model picker before a refresh; empty where ids change too often to hard-code.
    public let models: [String]
    /// Agents: the command line that starts the agent, and what to tell the user when it asks for a login.
    public var command: String? = nil
    public var loginHint: String? = nil
    public var symbol: String { wire == .acp ? "terminal" : isLocal ? "desktopcomputer" : "cloud" }

    public static let anthropic = AssistantPreset(id: "anthropic", name: "Claude", organization: "Anthropic", wire: .anthropic, baseURL: "https://api.anthropic.com/v1",
                                                  chatPath: "/messages", modelsPath: "/models", needsKey: true, isLocal: false,
                                                  caption: String(localized: "Uses the Anthropic API with your API key.", bundle: .module),
                                                  models: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"])
    /// Apple's model on this Mac: no key, no host, nothing leaves the Mac. Always listed, never stored.
    public static let onDevice = AssistantPreset(id: "on-device", name: "On-Device (Apple Intelligence)", organization: "Apple", wire: .onDevice, baseURL: "",
                                                 chatPath: "", modelsPath: nil, needsKey: false, isLocal: true,
                                                 caption: String(localized: "Apple's model on this Mac. Nothing leaves the Mac; it sees a passage, not whole files.", bundle: .module),
                                                 models: ["Apple Foundation Model"])
    public static let customInternet = AssistantPreset(id: "custom-internet", name: "Internet Hosted", organization: "Custom", wire: .openAI, baseURL: nil,
                                                       chatPath: "/chat/completions", modelsPath: "/models", needsKey: false, isLocal: false,
                                                       caption: String(localized: "Any server with an OpenAI-compatible chat completions API.", bundle: .module), models: [])
    public static let customLocal = AssistantPreset(id: "custom-local", name: "Locally Hosted", organization: "Custom", wire: .openAI, baseURL: nil,
                                                    chatPath: "/chat/completions", modelsPath: "/models", needsKey: false, isLocal: true,
                                                    caption: String(localized: "A model server on this Mac with an OpenAI-compatible API.", bundle: .module), models: [])

    /// The presets of "Add a Provider…", in menu order; the two custom ones come from "Add a Model Provider…".
    public static let all: [AssistantPreset] = [
        anthropic,
        AssistantPreset(id: "openai", name: "OpenAI", organization: "OpenAI", wire: .openAI, baseURL: "https://api.openai.com/v1",
                        chatPath: "/chat/completions", modelsPath: "/models", needsKey: true, isLocal: false, caption: String(localized: "Uses the OpenAI API with your API key.", bundle: .module), models: []),
        AssistantPreset(id: "openrouter", name: "OpenRouter", organization: "OpenRouter", wire: .openAI, baseURL: "https://openrouter.ai/api/v1",
                        chatPath: "/chat/completions", modelsPath: "/models", needsKey: true, isLocal: false,
                        caption: String(localized: "Many models from many providers with one OpenRouter API key. Model ids look like anthropic/claude-sonnet-5.5.", bundle: .module), models: []),
        // Both serve each model on its own protocol; OpenCodeClient picks it from the public model list.
        AssistantPreset(id: "opencode-zen", name: "OpenCode Zen", organization: "OpenCode", wire: .openCode, baseURL: "https://opencode.ai/inference",
                        chatPath: "", modelsPath: "/v1/models", needsKey: true, isLocal: false,
                        caption: String(localized: "Pay-as-you-go access to Claude, GPT, Gemini, DeepSeek, Kimi, GLM, Qwen and more with your OpenCode Zen API key.", bundle: .module),
                        models: []),
        AssistantPreset(id: "opencode-go", name: "OpenCode Go", organization: "OpenCode", wire: .openCode, baseURL: "https://opencode.ai/inference/go",
                        chatPath: "", modelsPath: "/v1/models", needsKey: true, isLocal: false,
                        caption: String(localized: "The OpenCode Go subscription's models (Kimi, GLM, DeepSeek, Qwen, MiniMax, GPT Luna, Claude Haiku and more) with your OpenCode API key.", bundle: .module),
                        models: []),
        AssistantPreset(id: "deepseek", name: "DeepSeek", organization: "DeepSeek", wire: .openAI, baseURL: "https://api.deepseek.com",
                        chatPath: "/chat/completions", modelsPath: "/models", needsKey: true, isLocal: false, caption: String(localized: "Uses the DeepSeek API with your API key.", bundle: .module), models: []),
        AssistantPreset(id: "moonshot", name: "Kimi", organization: "Moonshot AI", wire: .openAI, baseURL: "https://api.moonshot.ai/v1",
                        chatPath: "/chat/completions", modelsPath: "/models", needsKey: true, isLocal: false,
                        caption: String(localized: "The international platform. Keys of the China platform (moonshot.cn) do not work here.", bundle: .module), models: []),
        AssistantPreset(id: "zhipu", name: "GLM (Z.ai)", organization: "Zhipu AI", wire: .openAI, baseURL: "https://api.z.ai/api/paas/v4",
                        chatPath: "/chat/completions", modelsPath: nil, needsKey: true, isLocal: false,
                        caption: String(localized: "The international platform. Type the model id, such as one listed in the Z.ai documentation.", bundle: .module), models: []),
        AssistantPreset(id: "zhipu-cn", name: "GLM (BigModel, China)", organization: "Zhipu AI", wire: .openAI, baseURL: "https://open.bigmodel.cn/api/paas/v4",
                        chatPath: "/chat/completions", modelsPath: nil, needsKey: true, isLocal: false,
                        caption: String(localized: "The mainland China platform. Type the model id.", bundle: .module), models: []),
        AssistantPreset(id: "qwen", name: "Qwen", organization: "Alibaba Cloud Model Studio", wire: .openAI, baseURL: nil,
                        chatPath: "/chat/completions", modelsPath: nil, needsKey: true, isLocal: false,
                        caption: String(localized: "Enter your workspace's base URL, such as https://<workspace>.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1 (cn-beijing in mainland China). Keys only work in their own region. Type the model id.", bundle: .module),
                        models: []),
        AssistantPreset(id: "ollama", name: "Ollama", organization: "Ollama", wire: .openAI, baseURL: "http://localhost:11434/v1",
                        chatPath: "/chat/completions", modelsPath: "/models", needsKey: false, isLocal: true, caption: String(localized: "Runs models on this Mac. No API key needed.", bundle: .module), models: []),
        AssistantPreset(id: "lmstudio", name: "LM Studio", organization: "LM Studio", wire: .openAI, baseURL: "http://localhost:1234/v1",
                        chatPath: "/chat/completions", modelsPath: "/models", needsKey: false, isLocal: true, caption: String(localized: "Runs models on this Mac. No API key needed by default.", bundle: .module), models: []),
    ]

    static func agent(_ id: String, _ name: String, _ organization: String, _ command: String, caption: String, login: String?) -> AssistantPreset {
        AssistantPreset(id: id, name: name, organization: organization, wire: .acp, baseURL: "", chatPath: "", modelsPath: nil, needsKey: false,
                        isLocal: false, caption: caption, models: [], command: command, loginHint: login)
    }

    /// The agents of "Add a Provider…"; the last one takes any command line.
    public static let agents: [AssistantPreset] = [
        agent("acp-claude", "Claude Code (ACP)", "Anthropic", "npx -y @agentclientprotocol/claude-agent-acp",
              caption: String(localized: "Claude Code as an agent on this Mac, with your Claude Code login. It reads and changes the project's files itself. Needs Node.js.", bundle: .module),
              login: String(localized: "Log in first: run `claude` in Terminal and use /login, then try again.", bundle: .module)),
        agent("acp-codex", "Codex (ACP)", "OpenAI", "npx -y @agentclientprotocol/codex-acp",
              caption: String(localized: "OpenAI's Codex as an agent on this Mac, with your Codex login. It reads and changes the project's files itself. Needs Node.js.", bundle: .module),
              login: String(localized: "Log in first: run `codex` in Terminal and sign in, then try again.", bundle: .module)),
        agent("acp-gemini", "Gemini CLI (ACP)", "Google", "gemini --acp",
              caption: String(localized: "Google's Gemini CLI as an agent on this Mac. Install it first, for example with Homebrew.", bundle: .module),
              login: String(localized: "Log in first: run `gemini` in Terminal and sign in, then try again.", bundle: .module)),
        agent("acp-goose", "Goose (ACP)", "Block", "goose acp",
              caption: String(localized: "The Goose agent on this Mac. Install it and set up its model provider first.", bundle: .module),
              login: String(localized: "Set up Goose first: run `goose configure` in Terminal, then try again.", bundle: .module)),
        agent("acp-opencode", "OpenCode (ACP)", "OpenCode", "opencode acp",
              caption: String(localized: "The OpenCode agent on this Mac. Install it first.", bundle: .module),
              login: String(localized: "Log in first: run `opencode auth login` in Terminal, then try again.", bundle: .module)),
        agent("acp-custom", "Custom Agent (ACP)", "Custom", "",
              caption: String(localized: "Any agent that speaks the Agent Client Protocol over stdio. Enter the command line that starts it.", bundle: .module), login: nil),
    ]

    public static func named(_ id: String) -> AssistantPreset? { (all + agents + [onDevice, customInternet, customLocal]).first { $0.id == id } }
}

/// A configured provider. Stored in UserDefaults; its API key lives only in the Keychain under `id`.
public struct AssistantProvider: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var presetID: String
    /// The preset's name, or the user's description for a custom provider.
    public var name: String
    public var baseURL: String
    /// The header that carries the key: `Authorization` sends "Bearer <key>", any other name the bare key.
    public var keyHeader = "Authorization"
    /// The default model for this provider.
    public var model: String
    /// Agents: the command line that starts it; nil for model providers.
    public var command: String?

    public init(preset: AssistantPreset, name: String? = nil, baseURL: String? = nil, keyHeader: String = "Authorization") {
        presetID = preset.id
        self.name = name ?? preset.name
        self.baseURL = baseURL ?? preset.baseURL ?? ""
        self.keyHeader = keyHeader
        model = preset.models.first ?? ""
        command = preset.command
    }

    /// A custom provider on this Mac at `port`.
    /// The built-in on-device provider; its id is fixed so conversations keep pointing at it.
    public static let onDevice: AssistantProvider = {
        var p = AssistantProvider(preset: .onDevice)
        p.id = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        return p
    }()

    public var isOnDevice: Bool { presetID == AssistantPreset.onDevice.id }
    /// An agent on this Mac rather than a model: it has no model choice and changes files itself.
    public var isAgent: Bool { preset.wire == .acp }

    public static func local(port: Int, description: String) -> AssistantProvider {
        AssistantProvider(preset: .customLocal, name: description, baseURL: "http://localhost:\(port)/v1")
    }

    public var preset: AssistantPreset { AssistantPreset.named(presetID) ?? .customInternet }
    public var organization: String { preset.organization }
    /// Host shown in the first-use notice.
    public var host: String { URL(string: baseURL)?.host() ?? baseURL }
}

/// Where API keys are kept: the Keychain in the app, a dictionary in tests.
public protocol AssistantKeyStoring: Sendable {
    func key(for id: UUID) -> String?
    /// Whether a key is stored, without reading it: no Keychain password prompt.
    func hasKey(for id: UUID) -> Bool
    func setKey(_ key: String, for id: UUID, label: String) throws
    func removeKey(for id: UUID)
}

/// Generic passwords in the login Keychain, one per provider.
public struct KeychainAssistantKeys: AssistantKeyStoring {
    // persisted keychain service, kept from the app's old name so saved data survives
    static let service = "Tympan Model Provider"
    public init() {}

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: id.uuidString]
    }

    public func key(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Attributes only: reading the secret needs the item's access rule, which an unsigned or rebuilt app fails, so
    /// macOS asks for the login password. The launch only needs to know a key exists.
    public func hasKey(for id: UUID) -> Bool {
        var q = query(id)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
    }

    public func setKey(_ key: String, for id: UUID, label: String) throws {
        SecItemDelete(query(id) as CFDictionary)
        var q = query(id)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrLabel as String] = label
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw AssistantError.keychain(reason)
        }
    }

    public func removeKey(for id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}

/// The key store of tests and previews.
public final class InMemoryAssistantKeys: AssistantKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [UUID: String] = [:]
    public init() {}
    public func key(for id: UUID) -> String? { lock.withLock { keys[id] } }
    public func hasKey(for id: UUID) -> Bool { key(for: id) != nil }
    public func setKey(_ key: String, for id: UUID, label: String) throws { lock.withLock { keys[id] = key } }
    public func removeKey(for id: UUID) { _ = lock.withLock { keys.removeValue(forKey: id) } }
}
