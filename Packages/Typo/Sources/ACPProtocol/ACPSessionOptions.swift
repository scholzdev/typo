import Foundation
import JSONRPC

/// One value of an agent's mode or model menu.
public struct ACPChoice: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    public init(id: String, name: String, description: String? = nil) { self.id = id; self.name = name; self.description = description }
}

/// A menu the agent offers, and how a pick is sent back.
public struct ACPSelector: Sendable, Equatable {
    public enum Setter: Sendable, Equatable {
        /// `session/set_config_option` with this config id.
        case config(String)
        /// `session/set_mode`.
        case mode
        /// The older `session/set_model`.
        case model
    }
    public var choices: [ACPChoice]
    public var current: String?
    public var setter: Setter

    public init(choices: [ACPChoice], current: String?, setter: Setter) { self.choices = choices; self.current = current; self.setter = setter }

    /// The request that picks `id`.
    public func request(_ id: String, session: String) -> (method: String, params: JSONValue) {
        switch setter {
        case .config(let c): ("session/set_config_option", ["sessionId": .string(session), "configId": .string(c), "value": .string(id)])
        case .mode: ("session/set_mode", ["sessionId": .string(session), "modeId": .string(id)])
        case .model: ("session/set_model", ["sessionId": .string(session), "modelId": .string(id)])
        }
    }
}

/// The modes and models a session offers, from `session/new` and later updates.
public struct ACPSessionOptions: Sendable, Equatable {
    public var modes: ACPSelector?
    public var models: ACPSelector?
    public init(modes: ACPSelector? = nil, models: ACPSelector? = nil) { self.modes = modes; self.models = models }

    /// From a `session/new` result: `configOptions` of category "mode" and "model" first, else `modes` and the older `models`.
    public static func parse(_ result: JSONValue) -> ACPSessionOptions {
        var o = ACPSessionOptions()
        o.applyConfig(result["configOptions"])
        if o.modes == nil, let m = result["modes"], let list = m["availableModes"]?.array {
            o.modes = ACPSelector(choices: list.compactMap(choice(id: "id")), current: m["currentModeId"]?.string, setter: .mode)
        }
        if o.models == nil, let m = result["models"], let list = m["availableModels"]?.array {
            o.models = ACPSelector(choices: list.compactMap(choice(id: "modelId")), current: m["currentModelId"]?.string, setter: .model)
        }
        return o
    }

    /// A `session/update` that changes the options: `current_mode_update` or `config_option_update`. False for others.
    public mutating func apply(update u: JSONValue) -> Bool {
        switch u["sessionUpdate"]?.string {
        case "current_mode_update":
            guard let id = u["currentModeId"]?.string ?? u["modeId"]?.string else { return false }
            modes?.current = id
            return true
        case "config_option_update":
            applyConfig(u["configOptions"])
            return true
        default:
            return false
        }
    }

    /// Select options of category mode or model; grouped options are flattened.
    private mutating func applyConfig(_ options: JSONValue?) {
        for c in options?.array ?? [] {
            guard let id = c["id"]?.string, c["type"]?.string ?? "select" == "select" else { continue }
            let flat = (c["options"]?.array ?? []).flatMap { $0["options"]?.array ?? [$0] }
            let s = ACPSelector(choices: flat.compactMap(Self.choice(id: "value")), current: c["currentValue"]?.string, setter: .config(id))
            switch c["category"]?.string {
            case "mode": modes = s
            case "model": models = s
            default: break
            }
        }
    }

    private static func choice(id key: String) -> (JSONValue) -> ACPChoice? {
        { v in v[key]?.string.map { ACPChoice(id: $0, name: v["name"]?.string ?? $0, description: v["description"]?.string) } }
    }
}
