import Foundation

/// A slash command Typo runs itself, for any model: a Markdown file whose body becomes the prompt.
public struct Workflow: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable { case builtIn, mine }

    /// The slug typed after the slash, which is also the file name.
    public var name: String
    public var description: String
    /// What to type after the name, shown in the "/" popup.
    public var argumentHint: String
    public var body: String
    public var source: Source
    public var id: String { "\(source == .builtIn ? "typo" : "my"):\(name)" }

    public init(name: String, description: String, argumentHint: String = "", body: String, source: Source = .mine) {
        self.name = name; self.description = description; self.argumentHint = argumentHint; self.body = body; self.source = source
    }

    /// Reads a workflow file; without frontmatter the whole text is the body and `fallbackName` the name.
    public static func parse(_ text: String, fallbackName: String, source: Source = .mine) -> Workflow {
        guard let (fields, body) = Skill.frontmatter(text) else { return Workflow(name: fallbackName, description: "", body: text, source: source) }
        return Workflow(name: fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName, description: fields["description"] ?? "",
                        argumentHint: fields["argument-hint"] ?? "", body: body, source: source)
    }

    /// The file text. Values are double-quoted strings, so a colon in them stays valid YAML.
    public var markdown: String {
        func quoted(_ s: String) -> String {
            let oneLine = s.split(whereSeparator: \.isNewline).joined(separator: " ")
            return (try? JSONEncoder().encode(oneLine)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        }
        var head = "---\nname: \(name)\ndescription: \(quoted(description))\n"
        if !argumentHint.isEmpty { head += "argument-hint: \(quoted(argumentHint))\n" }
        return head + "---\n\n" + (body.hasSuffix("\n") || body.isEmpty ? body : body + "\n")
    }

    /// The prompt to send: the body with every `$ARGUMENTS` replaced; a body without one gets the arguments appended.
    public func prompt(arguments: String) -> String {
        if body.contains("$ARGUMENTS") { return body.replacingOccurrences(of: "$ARGUMENTS", with: arguments) }
        return arguments.isEmpty ? body : body + "\n\nARGUMENTS: " + arguments
    }

    /// The workflow a message starts: `/name args`, `/typo:name` or `/my:name`. A bare name finds one of `mine`
    /// before a built-in, so a copy can override it. Pass only the built-ins that are switched on.
    public static func resolve(_ text: String, builtIns: [Workflow], mine: [Workflow]) -> (workflow: Workflow, arguments: String)? {
        guard text.hasPrefix("/") else { return nil }
        let head = text.dropFirst().prefix { !$0.isWhitespace }
        let arguments = text.dropFirst(1 + head.count).trimmingCharacters(in: .whitespacesAndNewlines)
        let (pool, name): ([Workflow], Substring)
        if head.hasPrefix("typo:") { (pool, name) = (builtIns, head.dropFirst(5)) }
        else if head.hasPrefix("my:") { (pool, name) = (mine, head.dropFirst(3)) }
        else { (pool, name) = (mine + builtIns, head) }
        return pool.first { $0.name == name }.map { ($0, arguments) }
    }

    /// Lowercase letters, digits and single hyphens between them, at most 64 characters.
    public static func isValidName(_ s: String) -> Bool {
        s.count <= 64 && s.wholeMatch(of: /[a-z0-9]+(-[a-z0-9]+)*/) != nil
    }

    /// `base`, or `base-2`, `base-3`… when it is taken.
    public static func unique(_ base: String, among taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        return (2...).lazy.map { "\(base)-\($0)" }.first { !taken.contains($0) }!
    }
}

/// A folder of workflow files, `<name>.md` each.
public struct WorkflowFolder: Sendable {
    public let url: URL
    public let source: Workflow.Source
    public init(url: URL, source: Workflow.Source) { self.url = url; self.source = source }

    public func file(_ name: String) -> URL { url.appending(path: "\(name).md") }

    /// The workflows in the folder, sorted by name. The file name is the identity, whatever the frontmatter says.
    public func list() -> [Workflow] {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.filter { $0.pathExtension == "md" }.compactMap { f in
            (try? String(contentsOf: f, encoding: .utf8)).map {
                var w = Workflow.parse($0, fallbackName: f.deletingPathExtension().lastPathComponent, source: source)
                w.name = f.deletingPathExtension().lastPathComponent
                return w
            }
        }
        .sorted { $0.name < $1.name }
    }

    /// Writes `workflow`; `old` names the file it had before a rename.
    public func save(_ workflow: Workflow, replacing old: String? = nil) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        if let old, old != workflow.name, fm.fileExists(atPath: file(old).path) { try fm.moveItem(at: file(old), to: file(workflow.name)) }
        try Data(workflow.markdown.utf8).write(to: file(workflow.name), options: .atomic)
    }
}
