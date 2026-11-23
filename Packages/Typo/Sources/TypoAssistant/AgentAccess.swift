import Foundation

/// Settings › Intelligence › Permissions: what agents may do without asking, for every agent and every project.
/// The app consults it before it shows an agent's permission request and before it serves a file outside the project.
public struct AgentAccess: Sendable, Equatable {
    /// "Allowed Commands": each entry is a command prefix by words.
    public var commands: [String]
    /// "Control File & Folder Access": files outside the project are served only when the user allows it.
    public var controlsFiles: Bool
    /// "Allowed Folders": folders outside the project the user always allows.
    public var folders: [String]
    /// "Web Access" for fetch and web search tool calls.
    public var web: PermissionPolicy

    public init(commands: [String] = [], controlsFiles: Bool = true, folders: [String] = [], web: PermissionPolicy = .ask) {
        self.commands = commands; self.controlsFiles = controlsFiles; self.folders = folders; self.web = web
    }

    public enum Decision: Equatable, Sendable {
        /// Answered without asking; the rule that decided, for the log and the transcript.
        case allow(String)
        case reject(String)
        case ask
    }

    /// An agent's tool call as the policy sees it.
    public struct Request: Sendable, Equatable {
        public var kind: String?
        public var title: String
        /// The shell line of an `execute` call.
        public var command: String?
        /// Absolute paths the call names.
        public var paths: [String]
        public init(kind: String?, title: String, command: String? = nil, paths: [String] = []) {
            self.kind = kind; self.title = title; self.command = command; self.paths = paths
        }
        var changesFiles: Bool { ["edit", "delete", "move"].contains(kind ?? "") }
        var isWeb: Bool {
            let t = title.lowercased()
            return kind == "fetch" || t.hasPrefix("websearch") || t.hasPrefix("web search") || t.contains("web_search")
        }
    }

    /// What to answer a permission request; `changeFiles` is the conversation's "Change files" policy.
    public func decide(_ r: Request, root: String, changeFiles: PermissionPolicy) -> Decision {
        // Typo's own MCP tools only read the project; a page preview still asks, since its image goes to the provider.
        if r.title.hasPrefix("typo: "), !r.title.hasSuffix("view_preview") { return .allow("Typo's own tools") }
        if r.changesFiles {
            if changeFiles == .never { return .reject("Change files: Never") }
            if !outside(r.paths, root: root).isEmpty { return .ask }
            return changeFiles == .allow ? .allow("Change files: Allow") : .ask
        }
        if r.kind == "execute" {
            guard let rules = rules(for: r.command) else { return .ask }
            return .allow(rules.joined(separator: ", "))
        }
        if r.isWeb {
            switch web {
            case .allow: return .allow("Web Access: Allow")
            case .never: return .reject("Web Access: Never")
            case .ask: return .ask
            }
        }
        return .ask
    }

    /// Whether the agent may read or write `path` through Typo: inside the project it may; outside, with control off it
    /// may not (as before these settings), with control on only in an allowed folder, else the user is asked.
    public func fileAccess(_ path: String, root: String) -> Decision {
        if Self.contains(path, in: root) { return .allow("the project") }
        guard controlsFiles else { return .reject("outside the project") }
        if let f = folders.first(where: { Self.contains(path, in: $0) }) { return .allow(f) }
        return .ask
    }

    /// The paths that are neither in the project nor in an allowed folder; none when file access isn't controlled.
    public func outside(_ paths: [String], root: String) -> [String] {
        guard controlsFiles else { return [] }
        return paths.filter { p in !Self.contains(p, in: root) && !folders.contains { Self.contains(p, in: $0) } }
    }

    // MARK: Always Allow

    /// What "Always Allow" adds for this request: a rule per command not yet allowed, a folder per path outside.
    public func additions(for r: Request, root: String) -> (commands: [String], folders: [String]) {
        var commands: [String] = [], folders: [String] = []
        if r.kind == "execute", let parts = r.command.flatMap(Self.simpleCommands) {
            for words in parts where rule(for: words) == nil {
                if let s = Self.suggestion(for: words), !commands.contains(s) { commands.append(s) }
            }
        }
        for p in outside(r.paths, root: root) {
            let real = Self.resolve(p)
            var isDir: ObjCBool = false
            let folder = FileManager.default.fileExists(atPath: real, isDirectory: &isDir) && isDir.boolValue ? real : (real as NSString).deletingLastPathComponent
            if !folders.contains(folder) { folders.append(folder) }
        }
        return (commands, folders)
    }

    public mutating func remember(_ r: Request, root: String) {
        let a = additions(for: r, root: root)
        commands = Array(Set(commands + a.commands)).sorted()
        folders = Array(Set(folders + a.folders)).sorted()
    }

    /// Tools whose second word picks what they do: `cargo check` is allowed, not all of cargo.
    static let subcommandTools: Set<String> = ["git", "cargo", "swift", "npm", "pnpm", "yarn", "bun", "go", "gh", "brew", "typst", "docker", "kubectl", "uv", "pip", "pip3", "xcrun"]

    /// The rule "Always Allow" offers for a simple command: the program, with its subcommand for tools that have them.
    static func suggestion(for words: [String]) -> String? {
        guard let program = words.first else { return nil }
        if subcommandTools.contains(program), words.count > 1, !words[1].hasPrefix("-") { return quote([program, words[1]]) }
        return quote([program])
    }

    // MARK: Commands

    /// The rules that allow every simple command of `line`, or nil when one is not allowed or the line does more than
    /// run commands one after another.
    func rules(for line: String?) -> [String]? {
        guard let parts = line.flatMap(Self.simpleCommands) else { return nil }
        var used: [String] = []
        for words in parts {
            guard let r = rule(for: words) else { return nil }
            if !used.contains(r) { used.append(r) }
        }
        return used
    }

    /// The entry that allows a simple command: its words start with the entry's words. The program is compared as
    /// written, never by basename: `cat` doesn't allow `/tmp/evil/cat`, and `/bin/cat` doesn't allow `cat`, which
    /// may resolve to another program on the agent's PATH.
    func rule(for words: [String]) -> String? {
        commands.first { entry in
            guard let e = Self.words(entry), !e.isEmpty, e.count <= words.count else { return false }
            return zip(e, words).allSatisfy(==)
        }
    }

    /// An entry's words; an entry is one simple command.
    static func words(_ entry: String) -> [String]? {
        guard let parts = split(entry), parts.count == 1 else { return nil }
        return parts[0]
    }

    /// The simple commands of a shell line, each as its words, with `sh -c 'script'` and the like unwrapped into the
    /// script's commands. Nil when the line does anything the policy can't vouch for (see `split`).
    public static func simpleCommands(_ line: String) -> [[String]]? { simpleCommands(line, depth: 0) }

    private static func simpleCommands(_ line: String, depth: Int) -> [[String]]? {
        guard depth < 4, let parts = split(line), !parts.isEmpty else { return nil }
        var out: [[String]] = []
        for words in parts {
            if let script = shellScript(words) {
                guard let inner = simpleCommands(script, depth: depth + 1) else { return nil }
                out += inner
            } else {
                out.append(words)
            }
        }
        return out
    }

    /// The script of `bash -c 'script'`, `zsh -lc 'script'` or `sh -e -c 'script'`; nil for any other command. A shell
    /// with arguments after the script is not unwrapped, so it only matches a rule for the shell itself.
    static func shellScript(_ words: [String]) -> String? {
        guard let program = words.first, ["sh", "bash", "zsh", "dash"].contains((program as NSString).lastPathComponent) else { return nil }
        for i in 1..<words.count {
            let w = words[i]
            guard w.hasPrefix("-"), !w.hasPrefix("--") else { return nil }
            if w.contains("c") { return i + 2 == words.count ? words[i + 1] : nil }
        }
        return nil
    }

    /// A shell line as simple commands of words, split at `;`, `&`, `&&`, `|`, `||` and newlines, with quotes and
    /// backslashes removed as the shell would. Nil for an empty line and for anything that runs or touches more than its
    /// words say: command substitution (`$(`, backticks, also inside double quotes), redirection (`<`, `>`), subshells
    /// and groups (`(`, `)`), comments, an unclosed quote.
    public static func split(_ line: String) -> [[String]]? {
        // Unicode scalars, not Characters: "\r\n" or a quote with a combining mark is one Character, while the shell
        // reads them byte by byte.
        let it = Array(line.unicodeScalars)
        var commands: [[String]] = [], words: [String] = [], word: String.UnicodeScalarView? = nil, i = 0
        func endWord() { if let w = word { words.append(String(w)); word = nil } }
        func endCommand() { endWord(); if !words.isEmpty { commands.append(words); words = [] } }
        func append(_ c: Unicode.Scalar) { word = word ?? String.UnicodeScalarView(); word!.append(c) }
        func substitutes(at i: Int) -> Bool { it[i] == "`" || (it[i] == "$" && i + 1 < it.count && it[i + 1] == "(") }
        while i < it.count {
            let c = it[i]
            switch c {
            case " ", "\t": endWord()
            case "\n", "\r", ";", "&", "|": endCommand()
            case "<", ">", "(", ")": return nil
            case "#" where word == nil: return nil
            case _ where substitutes(at: i): return nil
            case "\\":
                i += 1
                guard i < it.count else { return nil }
                if it[i] != "\n" { append(it[i]) }
            case "'":
                guard let end = it[(i + 1)...].firstIndex(of: "'") else { return nil }
                if word == nil { word = String.UnicodeScalarView() }
                word!.append(contentsOf: it[(i + 1)..<end])
                i = end
            case "\"":
                if word == nil { word = String.UnicodeScalarView() }
                i += 1
                while i < it.count, it[i] != "\"" {
                    if substitutes(at: i) { return nil }
                    if it[i] == "\\", i + 1 < it.count, "$`\"\\\n".unicodeScalars.contains(it[i + 1]) { i += 1 }
                    append(it[i])
                    i += 1
                }
                guard i < it.count else { return nil }
            default: append(c)
            }
            i += 1
        }
        endCommand()
        return commands.isEmpty ? nil : commands
    }

    /// Words as a shell line that `split` reads back to the same words.
    public static func quote(_ words: [String]) -> String {
        words.map { w in
            w.isEmpty || w.contains(where: { !($0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0)) })
                ? "'" + w.replacingOccurrences(of: "'", with: "'\\''") + "'" : w
        }.joined(separator: " ")
    }

    // MARK: Paths

    /// Whether `path` is `folder` or inside it, after `..` and symlinks are resolved on both sides. A sibling that shares
    /// the folder's name as a prefix (/proj2 next to /proj) is not inside.
    public static func contains(_ path: String, in folder: String) -> Bool {
        let base = resolve(folder), full = resolve(path)
        guard base.hasPrefix("/"), full.hasPrefix("/") else { return false }
        return full == base || full.hasPrefix(base == "/" ? "/" : base + "/")
    }

    /// The real path: `..` resolved, then symlinks as far as the path exists (/tmp is /private/tmp; a new file's folder
    /// may not exist yet). A relative path stays as it is, and so is inside nothing.
    public static func resolve(_ path: String) -> String {
        var head = (path as NSString).standardizingPath, tail: [String] = []
        while head.hasPrefix("/") {
            if let r = realpath(head, nil) {
                defer { free(r) }
                return ([String(cString: r)] + tail.reversed()).joined(separator: "/").replacingOccurrences(of: "//", with: "/")
            }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return path
    }
}
