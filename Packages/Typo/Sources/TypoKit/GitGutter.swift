import Foundation
import TypstEngine

/// What the editor's gutter marks against HEAD (roadmap 6.1): lines added or modified in the current text, and the
/// places where lines were deleted. Line numbers are 1-based in the current text.
public struct GitGutterMarks: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case added, modified }
    public var lines: [Int: Kind] = [:]
    /// Lines were deleted right after these lines; 0 means before the first line.
    public var deletedAfter: Set<Int> = []
    /// Each run of changes with what HEAD had there, for the gutter's popover and its Revert.
    public var hunks: [Hunk] = []
    public init(lines: [Int: Kind] = [:], deletedAfter: Set<Int> = [], hunks: [Hunk] = []) {
        self.lines = lines; self.deletedAfter = deletedAfter; self.hunks = hunks
    }

    public struct Hunk: Sendable, Equatable {
        /// The first changed line (1-based); for a pure deletion, the line the deletion follows (0: before line 1).
        public var start: Int
        /// Where the old lines sat in the base, 0-based.
        public var oldStart: Int = 0
        public var oldLines: [String]
        public var newLines: [String]
        public var isDeletion: Bool { newLines.isEmpty }

        /// The base with this one change made: what the index gets when only this hunk is staged.
        public func apply(to base: String) -> String {
            var lines = base.isEmpty ? [] : base.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard oldStart + oldLines.count <= lines.count else { return base }
            lines.replaceSubrange(oldStart..<(oldStart + oldLines.count), with: newLines)
            return lines.joined(separator: "\n")
        }

        /// Puts HEAD's lines back in `text`, the current text the hunk was computed from.
        public func revert(in text: String) -> Replacement {
            // An empty text has no lines (as in `compute`), so the old lines simply become the text.
            if text.isEmpty { return Replacement(range: NSRange(location: 0, length: 0), text: oldLines.joined(separator: "\n")) }
            let lr = LineRanges(text)
            return isDeletion ? lr.replacing(lines: start..<start, with: oldLines)
                              : lr.replacing(lines: (start - 1)..<(start - 1 + newLines.count), with: oldLines)
        }
    }

    /// The hunk a gutter click on `line` means: one covering it, or a deletion marked at its edge.
    public func hunk(at line: Int) -> Hunk? {
        hunks.first { h in
            h.isDeletion ? h.start == line || (h.start == 0 && line == 1) : (h.start..<(h.start + h.newLines.count)).contains(line)
        }
    }

    public var isEmpty: Bool { hunks.isEmpty }

    /// A line diff in memory, so unsaved edits show at once. Within a run of changes, removed lines facing inserted
    /// ones make the inserted lines modified; a run with no insertions is a deletion, one with no removals an addition.
    public static func compute(base: String, current: String) -> GitGutterMarks {
        // An empty text has no lines (not one empty line), so a new file is all added.
        let old = base.isEmpty ? [] : base.split(separator: "\n", omittingEmptySubsequences: false)
        let new = current.isEmpty ? [] : current.split(separator: "\n", omittingEmptySubsequences: false)
        guard old != new else { return GitGutterMarks() }
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in new.difference(from: old) {
            switch change {
            case .remove(let o, _, _): removed.insert(o)
            case .insert(let n, _, _): inserted.insert(n)
            }
        }
        var marks = GitGutterMarks()
        var o = 0, n = 0
        // Unchanged lines pair up in order, so walking both sides together finds each run of changes.
        while o < old.count || n < new.count {
            var r = 0, a = 0
            while removed.contains(o + r) { r += 1 }
            while inserted.contains(n + a) { a += 1 }
            if r == 0 && a == 0 { o += 1; n += 1; continue }
            marks.hunks.append(Hunk(start: a == 0 ? n : n + 1, oldStart: o, oldLines: old[o..<(o + r)].map(String.init), newLines: new[n..<(n + a)].map(String.init)))
            if a == 0 {
                marks.deletedAfter.insert(n)
            } else {
                for line in (n + 1)...(n + a) { marks.lines[line] = r == 0 ? .added : .modified }
            }
            o += r; n += a
        }
        return marks
    }
}
