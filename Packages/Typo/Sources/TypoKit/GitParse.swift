import Foundation

/// Parsers for git's machine-readable output; design/14j-git.md.
public struct GitChange: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case modified, added, deleted, renamed, untracked, conflicted }
    public var path: String
    public var kind: Kind
    public var oldPath: String?
    /// The index differs from HEAD (X of git's XY), and the working tree from the index (Y).
    public var staged: Bool
    public var unstaged: Bool
    public var id: String { path }
    public init(path: String, kind: Kind, oldPath: String? = nil, staged: Bool = false, unstaged: Bool = true) {
        self.path = path; self.kind = kind; self.oldPath = oldPath; self.staged = staged; self.unstaged = unstaged
    }

    /// Staged in part: the checkbox shows mixed.
    public var partlyStaged: Bool { staged && unstaged }

    /// The one-letter status shown in the list.
    public var letter: String {
        switch kind {
        case .modified: "M"
        case .added: "A"
        case .deleted: "D"
        case .renamed: "R"
        case .untracked: "?"
        case .conflicted: "!"
        }
    }
}

/// The order of the Changes list (Settings › Source Control › Source control navigator).
public enum GitChangeOrder: String, CaseIterable, Sendable {
    case name, status

    public var title: String { self == .name ? "Sort by Name" : "Sort by Status" }

    public func sorted(_ changes: [GitChange]) -> [GitChange] {
        func byName(_ a: GitChange, _ b: GitChange) -> Bool { a.path.localizedStandardCompare(b.path) == .orderedAscending }
        switch self {
        case .name: return changes.sorted(by: byName)
        case .status:
            func rank(_ k: GitChange.Kind) -> Int {
                switch k {
                case .conflicted: 0
                case .modified: 1
                case .renamed: 2
                case .added: 3
                case .deleted: 4
                case .untracked: 5
                }
            }
            return changes.sorted { rank($0.kind) != rank($1.kind) ? rank($0.kind) < rank($1.kind) : byName($0, $1) }
        }
    }
}

public struct GitStatus: Sendable, Equatable {
    public var branch: String?          // nil when detached
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var changes: [GitChange] = []
    public init() {}

    /// `git status --porcelain=v2 --branch -z`.
    public init(porcelainV2 data: String) {
        var records = data.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let r = records.popFirst() {
            if r.hasPrefix("# ") {
                let f = r.dropFirst(2).split(separator: " ", maxSplits: 1).map(String.init)
                guard f.count == 2 else { continue }
                switch f[0] {
                case "branch.head": branch = f[1] == "(detached)" ? nil : f[1]
                case "branch.upstream": upstream = f[1]
                case "branch.ab":
                    let n = f[1].split(separator: " ").map { Int($0.dropFirst()) ?? 0 }
                    if n.count == 2 { ahead = n[0]; behind = n[1] }
                default: break
                }
                continue
            }
            let tag = r.first
            func fields(_ n: Int) -> [String] { r.split(separator: " ", maxSplits: n, omittingEmptySubsequences: false).map(String.init) }
            switch tag {
            case "1":
                let f = fields(8)
                guard f.count == 9 else { continue }
                let xy = f[1]
                changes.append(GitChange(path: f[8], kind: xy.contains("D") ? .deleted : xy.hasPrefix("A") ? .added : .modified,
                                         staged: xy.first != ".", unstaged: xy.last != "."))
            case "2":
                let f = fields(9)
                guard f.count == 10 else { continue }
                changes.append(GitChange(path: f[9], kind: .renamed, oldPath: records.popFirst(),   // the origin is the next record
                                         staged: f[1].first != ".", unstaged: f[1].last != "."))
            case "u":
                let f = fields(10)
                if f.count == 11 { changes.append(GitChange(path: f[10], kind: .conflicted)) }
            case "?":
                changes.append(GitChange(path: String(r.dropFirst(2)), kind: .untracked))
            default: break
            }
        }
    }
}

public struct DiffLine: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case context, added, removed, hunk }
    public let id: Int
    public var kind: Kind
    public var text: String
}

public enum GitDiff {
    /// Unified diff to lines; the file headers before the first hunk are dropped.
    public static func parse(_ text: String) -> [DiffLine] {
        var out: [DiffLine] = []
        func add(_ k: DiffLine.Kind, _ t: Substring) { out.append(DiffLine(id: out.count, kind: k, text: String(t))) }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") { add(.hunk, line); continue }
            guard !out.isEmpty else { continue }
            switch line.first {
            case "+": add(.added, line.dropFirst())
            case "-": add(.removed, line.dropFirst())
            case " ": add(.context, line.dropFirst())
            default: break      // "\ No newline at end of file", the trailing empty line
            }
        }
        return out
    }
}

/// A local branch; `for-each-ref --format=%(HEAD)%00%(refname:short) refs/heads`.
public struct GitBranch: Sendable, Equatable, Identifiable {
    public var name: String
    public var isCurrent: Bool
    public var id: String { name }
    public init(name: String, isCurrent: Bool = false) { self.name = name; self.isCurrent = isCurrent }

    public static func parse(_ text: String) -> [GitBranch] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
            guard f.count == 2, !f[1].isEmpty else { return nil }
            return GitBranch(name: String(f[1]), isCurrent: f[0] == "*")
        }
    }
}

/// One commit of a file's history, with the file's path in that commit (it differs before a rename).
public struct GitCommit: Sendable, Equatable, Identifiable, Hashable {
    public var hash: String
    public var author: String
    public var date: Date
    public var subject: String
    public var path: String
    public var id: String { hash }
    public var shortHash: String { String(hash.prefix(7)) }
    public init(hash: String, author: String, date: Date, subject: String, path: String) {
        self.hash = hash; self.author = author; self.date = date; self.subject = subject; self.path = path
    }

    /// The `log` format `parse` reads: RS before each commit, US between the fields, then `--name-only` lines.
    public static let logFormat = "--format=%x1e%H%x1f%an%x1f%at%x1f%s"

    /// `git log --follow --name-only <logFormat> -- path`; the name is the last non-empty line of a record.
    public static func parse(_ text: String) -> [GitCommit] {
        text.split(separator: "\u{1e}").compactMap { record in
            let lines = record.split(separator: "\n", omittingEmptySubsequences: true)
            guard let head = lines.first else { return nil }
            let f = head.split(separator: "\u{1f}", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, let t = TimeInterval(f[2]), let path = lines.dropFirst().last else { return nil }
            return GitCommit(hash: f[0], author: f[1], date: Date(timeIntervalSince1970: t), subject: f[3], path: String(path))
        }
    }
}

extension GitDiff {
    /// One row of a side-by-side diff: the old line on the left, the new on the right, with their line numbers.
    public struct Pair: Sendable, Equatable, Identifiable {
        public var id: Int
        public var isHunk = false
        public var old: (number: Int, text: String)?
        public var new: (number: Int, text: String)?

        public static func == (a: Pair, b: Pair) -> Bool {
            a.id == b.id && a.isHunk == b.isHunk && a.old?.number == b.old?.number && a.old?.text == b.old?.text
                && a.new?.number == b.new?.number && a.new?.text == b.new?.text
        }
    }

    /// Lines to side-by-side rows: context on both sides, and within a run of changes the n-th removed line faces
    /// the n-th added one; the longer side continues against empty rows. Numbers come from the hunk headers.
    public static func sideBySide(_ lines: [DiffLine]) -> [Pair] {
        var out: [Pair] = []
        var old = 0, new = 0
        var removed: [String] = [], added: [String] = []
        func flush() {
            for i in 0..<max(removed.count, added.count) {
                var p = Pair(id: out.count)
                if i < removed.count { p.old = (old, removed[i]); old += 1 }
                if i < added.count { p.new = (new, added[i]); new += 1 }
                out.append(p)
            }
            removed = []; added = []
        }
        for l in lines {
            switch l.kind {
            case .removed: if !added.isEmpty { flush() }; removed.append(l.text)
            case .added: added.append(l.text)
            case .context:
                flush()
                out.append(Pair(id: out.count, old: (old, l.text), new: (new, l.text)))
                old += 1; new += 1
            case .hunk:
                flush()
                // "@@ -a,b +c,d @@ context"
                let nums = l.text.split(separator: " ").dropFirst().prefix(2).map { $0.dropFirst().split(separator: ",").first.flatMap { Int($0) } ?? 0 }
                if nums.count == 2 { old = nums[0]; new = nums[1] }
                out.append(Pair(id: out.count, isHunk: true, old: (0, l.text), new: nil))
            }
        }
        flush()
        return out
    }
}
