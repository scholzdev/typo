import Foundation

/// Registering typo-mcp with Claude Desktop, whose config is ~/Library/Application Support/Claude/claude_desktop_config.json.
public enum MCPInstall {
    public static var desktopConfig: URL {
        URL.applicationSupportDirectory.appending(path: "Claude/claude_desktop_config.json")
    }

    /// `config` (nil: no file yet) with the "typo" server set to `command` and everything else kept; nil when it is not a JSON object.
    public static func merging(_ config: Data?, command: String) -> Data? {
        var root: [String: Any] = [:]
        if let config {
            guard let o = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return nil }
            root = o
        }
        guard var servers = (root["mcpServers"] ?? [String: Any]()) as? [String: Any] else { return nil }
        servers["typo"] = ["command": command, "args": [String]()]
        root["mcpServers"] = servers
        return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Whether `config` names a "typo" server.
    public static func isAdded(_ config: Data?) -> Bool {
        guard let config, let o = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return false }
        return (o["mcpServers"] as? [String: Any])?["typo"] != nil
    }

    /// Writes the merged config, after copying the old file to claude_desktop_config.json.bak. Returns what to tell the user.
    public static func addToDesktop(command: String, config url: URL = desktopConfig) -> (ok: Bool, text: String) {
        let fm = FileManager.default
        let old = try? Data(contentsOf: url)
        guard let merged = merging(old, command: command) else {
            return (false, "\(url.lastPathComponent) is not valid JSON, so it was left unchanged. Fix or remove it, then try again.")
        }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let old { try old.write(to: url.appendingPathExtension("bak"), options: .atomic) }
            try merged.write(to: url, options: .atomic)
        } catch {
            return (false, String(localized: "The Claude Desktop settings could not be written: \(error.localizedDescription)", bundle: .module))
        }
        return (true, String(localized: "Added. Restart Claude Desktop to use it.", bundle: .module))
    }
}
