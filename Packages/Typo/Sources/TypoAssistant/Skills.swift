import Foundation

/// A Claude skill: a `skills/<name>/SKILL.md` in a Claude plugin directory, with `name` and `description`
/// frontmatter above a Markdown body.
public struct Skill: Sendable, Equatable, Identifiable {
    /// The slug, which is also the skill's folder name.
    public var name: String
    /// When to use the skill; the agent decides from it.
    public var description: String
    public var body: String
    public var id: String { name }

    public init(name: String, description: String, body: String) {
        self.name = name; self.description = description; self.body = body
    }

    /// Reads a SKILL.md; without frontmatter the whole text is the body and `fallbackName` the name.
    public static func parse(_ text: String, fallbackName: String) -> Skill {
        guard let (fields, body) = frontmatter(text) else { return Skill(name: fallbackName, description: "", body: text) }
        return Skill(name: fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName, description: fields["description"] ?? "", body: body)
    }

    /// The `key: value` lines between a leading `---` pair and the Markdown after it; nil when the text has no such block.
    static func frontmatter(_ text: String) -> (fields: [String: String], body: String)? {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n") else { return nil }
        let rest = text.dropFirst(4)
        let end: Range<Substring.Index>
        if rest.hasPrefix("---\n") || rest == "---" { end = rest.startIndex..<rest.index(rest.startIndex, offsetBy: 3) }
        else if let r = rest.range(of: "\n---\n") ?? (rest.hasSuffix("\n---") ? rest.range(of: "\n---", options: .backwards) : nil) { end = r }
        else { return nil }
        var fields: [String: String] = [:]
        for line in rest[..<end.lowerBound].split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[line[..<colon].trimmingCharacters(in: .whitespaces)] = unquote(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        var body = rest[end.upperBound...]
        while body.hasPrefix("\n") { body = body.dropFirst() }
        return (fields, String(body))
    }

    private static func unquote(_ v: String) -> String {
        if v.count >= 2, v.hasPrefix("\""), v.hasSuffix("\""),
           let s = try? JSONDecoder().decode(String.self, from: Data(v.utf8)) { return s }
        if v.count >= 2, v.hasPrefix("'"), v.hasSuffix("'") { return String(v.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return v
    }
}

/// A plugin directory of skills: `.claude-plugin/plugin.json` and `skills/<name>/SKILL.md`.
public struct SkillPlugin: Sendable {
    public let url: URL
    /// The plugin's name, which namespaces its skills for the agent (`typo:math`).
    public let name: String
    public init(url: URL, name: String) { self.url = url; self.name = name }

    public var skillsURL: URL { url.appending(path: "skills", directoryHint: .isDirectory) }
    public func folder(_ name: String) -> URL { skillsURL.appending(path: name, directoryHint: .isDirectory) }

    /// The skills in the plugin, sorted by name; a folder without SKILL.md is skipped.
    public func list() -> [Skill] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: skillsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return folders.compactMap { f in
            // The folder name is the skill's identity, whatever its frontmatter says.
            (try? String(contentsOf: f.appending(path: "SKILL.md"), encoding: .utf8)).map { var s = Skill.parse($0, fallbackName: f.lastPathComponent); s.name = f.lastPathComponent; return s }
        }
        .sorted { $0.name < $1.name }
    }

    /// The key of a skill in the set of switched-on skills: `plugin/name`.
    public func key(_ skill: String) -> String { "\(name)/\(skill)" }

    /// Builds `into` as a copy of this plugin with only the skills whose key is in `enabled`, and returns it;
    /// nil when no skill is enabled. Copies, not symlinks: a loader that lists directories may skip linked ones.
    public func assemble(into dest: URL, enabled keys: Set<String>) throws -> URL? {
        let fm = FileManager.default
        let enabled = ((try? fm.contentsOfDirectory(at: skillsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { fm.fileExists(atPath: $0.appending(path: "SKILL.md").path) && keys.contains(key($0.lastPathComponent)) }
        guard !enabled.isEmpty else {
            try? fm.removeItem(at: dest)
            return nil
        }
        // Built next to `dest` and swapped in, so a running session never sees a half-built folder.
        let tmp = dest.deletingLastPathComponent().appending(path: ".\(dest.lastPathComponent)-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: tmp) }
        let built = SkillPlugin(url: tmp, name: name)
        try fm.createDirectory(at: built.skillsURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: tmp.appending(path: ".claude-plugin"), withIntermediateDirectories: true)
        let manifest = url.appending(path: ".claude-plugin/plugin.json")
        if fm.fileExists(atPath: manifest.path) {
            try fm.copyItem(at: manifest, to: tmp.appending(path: ".claude-plugin/plugin.json"))
        } else {
            try Data(#"{"name": "\#(name)"}"#.utf8).write(to: tmp.appending(path: ".claude-plugin/plugin.json"))
        }
        for f in enabled { try fm.copyItem(at: f, to: built.folder(f.lastPathComponent)) }
        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: dest)
        }
        return dest
    }
}
