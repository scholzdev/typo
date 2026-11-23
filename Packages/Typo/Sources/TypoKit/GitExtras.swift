import Foundation
import TypstEngine

/// Who last changed a line; `git blame --porcelain`. Lines not yet committed carry the all-zero hash.
public struct GitBlameLine: Sendable, Equatable {
    public var hash: String
    public var author: String
    public var date: Date
    public var summary: String
    public init(hash: String, author: String, date: Date, summary: String) {
        self.hash = hash; self.author = author; self.date = date; self.summary = summary
    }

    public var isCommitted: Bool { hash.contains { $0 != "0" } }
    public var shortHash: String { String(hash.prefix(7)) }
}

public enum GitBlame {
    /// One entry per line of the blamed text, in order; a commit's details appear only at its first group.
    public static func parse(_ text: String) -> [GitBlameLine] {
        var info: [String: (author: String, time: TimeInterval, summary: String)] = [:]
        var byLine: [Int: String] = [:]
        var current: String?
        var fields: (author: String, time: TimeInterval, summary: String) = ("", 0, "")
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if raw.hasPrefix("\t") {                     // the line's content closes its group
                if let h = current, info[h] == nil { info[h] = fields }
                current = nil
                continue
            }
            if current == nil {
                let f = raw.split(separator: " ")
                guard f.count >= 3, f[0].count == 40, let final = Int(f[2]) else { continue }
                current = String(f[0])
                byLine[final] = current
                fields = info[String(f[0])] ?? ("", 0, "")
                continue
            }
            if raw.hasPrefix("author ") { fields.author = String(raw.dropFirst(7)) }
            else if raw.hasPrefix("author-time ") { fields.time = TimeInterval(raw.dropFirst(12)) ?? 0 }
            else if raw.hasPrefix("summary ") { fields.summary = String(raw.dropFirst(8)) }
        }
        guard let last = byLine.keys.max() else { return [] }
        return (1...last).map { n in
            let h = byLine[n] ?? String(repeating: "0", count: 40)
            let i = info[h] ?? ("", 0, "")
            return GitBlameLine(hash: h, author: i.author, date: Date(timeIntervalSince1970: i.time), summary: i.summary)
        }
    }
}

/// A stash entry; `stash list --format=%gd%x1f%ct%x1f%gs`.
public struct GitStash: Sendable, Equatable, Identifiable {
    public var ref: String          // stash@{0}
    public var date: Date
    public var message: String
    public var id: String { ref }
    public init(ref: String, date: Date, message: String) { self.ref = ref; self.date = date; self.message = message }

    public static let listFormat = "--format=%gd%x1f%ct%x1f%gs"

    public static func parse(_ text: String) -> [GitStash] {
        text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3, let t = TimeInterval(f[1]) else { return nil }
            return GitStash(ref: f[0], date: Date(timeIntervalSince1970: t), message: f[2])
        }
    }
}

/// A one-file unified diff split into its header and hunks, so a single hunk can be applied to the index.
public struct GitPatch: Sendable, Equatable {
    public var header: [String]
    public var hunks: [[String]]

    public init(_ text: String) {
        header = []; hunks = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("@@") { hunks.append([line]) }
            else if hunks.isEmpty { header.append(line) }
            else if !line.isEmpty { hunks[hunks.count - 1].append(line) }
        }
        while header.last == "" { header.removeLast() }
    }

    /// The header plus hunk `i`: a patch `git apply --cached` takes on its own.
    public func patch(forHunk i: Int) -> String? {
        guard hunks.indices.contains(i), !header.isEmpty else { return nil }
        return (header + hunks[i]).joined(separator: "\n") + "\n"
    }
}

/// A merge conflict written into a file: `<<<<<<<`, optional `|||||||` base, `=======`, `>>>>>>>`.
public struct ConflictRegion: Sendable, Equatable {
    public enum Choice: Sendable { case mine, theirs, both }
    /// 1-based lines of the `<<<<<<<` and `>>>>>>>` markers.
    public var startLine: Int
    public var endLine: Int
    public var mine: [String]
    public var theirs: [String]
    public var mineLabel: String
    public var theirsLabel: String

    public func contains(line: Int) -> Bool { (startLine...endLine).contains(line) }

    public static func parse(_ text: String) -> [ConflictRegion] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [ConflictRegion] = []
        var i = 0
        while i < lines.count {
            guard lines[i].hasPrefix("<<<<<<<") else { i += 1; continue }
            let start = i
            var mine: [String] = [], theirs: [String] = []
            var part = 0                              // 0 mine, 1 base (dropped), 2 theirs
            var j = i + 1
            var closed = false
            while j < lines.count {
                let l = lines[j]
                if l.hasPrefix("|||||||") && part == 0 { part = 1 }
                else if l.hasPrefix("=======") && part < 2 { part = 2 }
                else if l.hasPrefix(">>>>>>>") && part == 2 { closed = true; break }
                else if part == 0 { mine.append(l) }
                else if part == 2 { theirs.append(l) }
                j += 1
            }
            guard closed else { break }
            out.append(ConflictRegion(startLine: start + 1, endLine: j + 1, mine: mine, theirs: theirs,
                                      mineLabel: String(lines[start].dropFirst(7)).trimmingCharacters(in: .whitespaces),
                                      theirsLabel: String(lines[j].dropFirst(7)).trimmingCharacters(in: .whitespaces)))
            i = j + 1
        }
        return out
    }

    /// The edit that replaces the whole region, markers included, with the chosen side(s).
    public func resolution(_ choice: Choice, in text: String) -> Replacement {
        let kept: [String] = switch choice { case .mine: mine; case .theirs: theirs; case .both: mine + theirs }
        return LineRanges(text).replacing(lines: (startLine - 1)..<endLine, with: kept)
    }
}

/// A file with conflicts as the merge editor shows it: lines between blocks, and the blocks in order.
public enum MergeSegment: Sendable, Equatable {
    case context([String])
    case conflict(index: Int, ConflictRegion)
}

extension ConflictRegion {
    /// `text` with each block replaced by its `choices` entry; nil keeps the block and its markers.
    /// `choices[i]` belongs to `parse(text)[i]`; missing entries count as nil.
    public static func resolve(_ text: String, choices: [Choice?]) -> String {
        var out = text as NSString
        for (i, r) in parse(text).enumerated().reversed() {      // back to front keeps earlier line numbers valid
            guard i < choices.count, let c = choices[i] else { continue }
            let e = r.resolution(c, in: text)
            out = out.replacingCharacters(in: e.range, with: e.text) as NSString
        }
        return out as String
    }

    /// The context lines between blocks (a trailing newline does not add an empty last line) and the blocks, in file order.
    public static func segments(_ text: String) -> [MergeSegment] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        var out: [MergeSegment] = []
        var next = 0                                              // 0-based first line not yet emitted
        for (i, r) in parse(text).enumerated() {
            if r.startLine - 1 > next { out.append(.context(Array(lines[next..<(r.startLine - 1)]))) }
            out.append(.conflict(index: i, r))
            next = r.endLine
        }
        if next < lines.count { out.append(.context(Array(lines[next...]))) }
        return out
    }
}

/// UTF-16 offsets of line starts, for edits addressed by line.
struct LineRanges {
    let starts: [Int]
    let length: Int

    init(_ text: String) {
        var s = [0], pos = 0
        for u in text.utf16 { pos += 1; if u == 10 { s.append(pos) } }
        starts = s
        length = pos
    }

    var count: Int { starts.count }

    /// Replaces 0-based lines `range` (an empty range inserts before its lower bound) with `lines`.
    func replacing(lines range: Range<Int>, with lines: [String]) -> Replacement {
        let lo = range.lowerBound, hi = range.upperBound
        if hi < count {
            let start = starts[min(lo, count - 1)]
            return Replacement(range: NSRange(location: start, length: starts[hi] - start), text: lines.map { $0 + "\n" }.joined())
        }
        // Up to the end: the last line has no newline after it.
        if lo >= count || (range.isEmpty && lo == count) {
            return Replacement(range: NSRange(location: length, length: 0), text: lines.isEmpty ? "" : "\n" + lines.joined(separator: "\n"))
        }
        let start = starts[lo]
        if lines.isEmpty, lo > 0 {                        // removing the tail also removes the newline before it
            return Replacement(range: NSRange(location: start - 1, length: length - start + 1), text: "")
        }
        return Replacement(range: NSRange(location: start, length: length - start), text: lines.joined(separator: "\n"))
    }
}

extension GitDiff {
    /// A unified diff of two texts computed in memory (snapshots are not in git), as `parse` would return it.
    public static func between(_ old: String, _ new: String, context: Int = 3) -> [DiffLine] {
        let a = old.isEmpty ? [] : old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let b = new.isEmpty ? [] : new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard a != b else { return [] }
        var removed = Set<Int>(), inserted = Set<Int>()
        for c in b.difference(from: a) {
            switch c { case .remove(let o, _, _): removed.insert(o); case .insert(let n, _, _): inserted.insert(n) }
        }
        // The full edit script first, then cut into hunks with `context` lines around each change.
        var script: [(kind: DiffLine.Kind, text: String, o: Int, n: Int)] = []
        var o = 0, n = 0
        while o < a.count || n < b.count {
            if removed.contains(o) { script.append((.removed, a[o], o, n)); o += 1 }
            else if inserted.contains(n) { script.append((.added, b[n], o, n)); n += 1 }
            else { script.append((.context, a[o], o, n)); o += 1; n += 1 }
        }
        let changed = script.indices.filter { script[$0].kind != .context }
        var out: [DiffLine] = []
        var i = 0
        while i < changed.count {
            let lo = max(0, changed[i] - context)
            var hi = min(script.count - 1, changed[i] + context)
            while i + 1 < changed.count, changed[i + 1] - context <= hi + 1 { i += 1; hi = min(script.count - 1, changed[i] + context) }
            let slice = script[lo...hi]
            let oldCount = slice.filter { $0.kind != .added }.count, newCount = slice.filter { $0.kind != .removed }.count
            let os = oldCount == 0 ? slice.first!.o : slice.first!.o + 1, ns = newCount == 0 ? slice.first!.n : slice.first!.n + 1
            out.append(DiffLine(id: out.count, kind: .hunk, text: "@@ -\(os),\(oldCount) +\(ns),\(newCount) @@"))
            for s in slice { out.append(DiffLine(id: out.count, kind: s.kind, text: s.text)) }
            i += 1
        }
        return out
    }
}
