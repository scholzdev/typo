import Foundation

/// A skill an agent can load: a `skills/<name>/SKILL.md` in a Claude plugin directory, with `name` and
/// `description` frontmatter above a Markdown body.
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
        var skill = Skill(name: fallbackName, description: "", body: text)
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n") else { return skill }
        let rest = text.dropFirst(4)
        let end: Range<Substring.Index>
        if rest.hasPrefix("---\n") || rest == "---" { end = rest.startIndex..<rest.index(rest.startIndex, offsetBy: 3) }
        else if let r = rest.range(of: "\n---\n") ?? (rest.hasSuffix("\n---") ? rest.range(of: "\n---", options: .backwards) : nil) { end = r }
        else { return skill }
        for line in rest[..<end.lowerBound].split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = unquote(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            switch key {
            case "name" where !value.isEmpty: skill.name = value
            case "description": skill.description = value
            default: break
            }
        }
        var body = rest[end.upperBound...]
        if body.hasPrefix("\n") { body = body.dropFirst() }
        while body.hasPrefix("\n") { body = body.dropFirst() }
        skill.body = String(body)
        return skill
    }

    private static func unquote(_ v: String) -> String {
        if v.count >= 2, v.hasPrefix("\""), v.hasSuffix("\""),
           let s = try? JSONDecoder().decode(String.self, from: Data(v.utf8)) { return s }
        if v.count >= 2, v.hasPrefix("'"), v.hasSuffix("'") { return String(v.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'") }
        return v
    }

    /// The SKILL.md text. The description is always a double-quoted string, so a colon in it stays valid YAML.
    public var markdown: String {
        let oneLine = description.split(whereSeparator: \.isNewline).joined(separator: " ")
        let quoted = (try? JSONEncoder().encode(oneLine)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let body = body.hasSuffix("\n") || body.isEmpty ? body : body + "\n"
        return "---\nname: \(name)\ndescription: \(quoted)\n---\n\n" + body
    }

    /// Lowercase letters, digits and single hyphens between them, at most 64 characters.
    public static func isValidName(_ s: String) -> Bool {
        s.count <= 64 && s.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil
    }

    /// A kebab-case slug for `title`: "Write Tables, Fast!" becomes "write-tables-fast".
    public static func slug(_ title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en")).lowercased()
        let words = folded.split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return String(words.joined(separator: "-").prefix(64)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// `base`, or `base-2`, `base-3`… when it is taken.
    public static func unique(_ base: String, among taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        return (2...).lazy.map { "\(base)-\($0)" }.first { !taken.contains($0) }!
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

    /// The key of a skill in the disabled set: `plugin/name`.
    public func key(_ skill: String) -> String { "\(name)/\(skill)" }

    /// Writes plugin.json when it is missing.
    public func prepare() throws {
        let manifest = url.appending(path: ".claude-plugin/plugin.json")
        guard !FileManager.default.fileExists(atPath: manifest.path) else { return }
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"name": "\#(name)"}"#.utf8).write(to: manifest)
        try FileManager.default.createDirectory(at: skillsURL, withIntermediateDirectories: true)
    }

    /// Writes `skill` to `skills/<name>/SKILL.md`; `replacing` names the folder it had before a rename.
    public func save(_ skill: Skill, replacing old: String? = nil) throws {
        try prepare()
        let fm = FileManager.default
        if let old, old != skill.name, fm.fileExists(atPath: folder(old).path) {
            try fm.moveItem(at: folder(old), to: folder(skill.name))
        }
        try fm.createDirectory(at: folder(skill.name), withIntermediateDirectories: true)
        try Data(skill.markdown.utf8).write(to: folder(skill.name).appending(path: "SKILL.md"), options: .atomic)
    }

    /// Copies the skill folder `from` (a SKILL.md and anything beside it) into this plugin as `name`.
    public func importSkill(from folder: URL, as name: String) throws {
        try prepare()
        try FileManager.default.copyItem(at: folder, to: self.folder(name))
    }

    /// The skill folders (those with a SKILL.md) in and under `root`, sorted by path; dependency and VCS folders are skipped.
    public static func skillFolders(in root: URL) -> [URL] {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appending(path: "SKILL.md").path) { return [root] }
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walk {
            if ["node_modules", ".git"].contains(url.lastPathComponent) || walk.level > 8 { walk.skipDescendants(); continue }
            if url.lastPathComponent == "SKILL.md" { found.append(url.deletingLastPathComponent()); walk.skipDescendants() }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Builds `into` as a copy of this plugin with only the skills whose key is not in `disabled`, and returns it;
    /// nil when no skill is enabled. Copies, not symlinks: a loader that lists directories may skip linked ones.
    public func assemble(into dest: URL, disabled: Set<String>) throws -> URL? {
        let fm = FileManager.default
        let enabled = ((try? fm.contentsOfDirectory(at: skillsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { fm.fileExists(atPath: $0.appending(path: "SKILL.md").path) && !disabled.contains(key($0.lastPathComponent)) }
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
