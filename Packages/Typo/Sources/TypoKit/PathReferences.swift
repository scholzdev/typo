import Foundation
import TypstEngine

/// Path strings after a rename or move (design/14d-files-safety.md): `"a.typ"`, `"../figs/cat.png"` or `"/a.typ"`
/// in code that pointed at the moved item, or that sit in a moved file, are rewritten to reach the same target.
public enum PathReferences {
    /// Replacements in `text` (the file that was at `file` before `old` moved to `new`) that keep each code string
    /// reaching its target. `existing` holds every project file and folder before the move; a string that did not
    /// resolve to one of them is not a path and stays.
    public static func edits(in text: String, of file: RelPath, moving old: RelPath, to new: RelPath, existing: Set<RelPath>) -> [Replacement] {
        let ns = text as NSString
        let newFile = file.replacing(old, with: new) ?? file
        return TypstSyntax.tokens(in: text).compactMap { t in
            guard t.tag == .string, t.range.length >= 2 else { return nil }
            let inner = NSRange(location: t.range.location + 1, length: t.range.length - 2)
            let s = ns.substring(with: inner)
            guard let target = resolve(s, in: file.parent), existing.contains(target) else { return nil }
            let moved = target.replacing(old, with: new) ?? target
            guard moved != target || newFile != file else { return nil }
            let spelled = spell(moved, from: newFile.parent, like: s)
            return spelled == s ? nil : Replacement(range: inner, text: spelled)
        }
    }

    /// The path string containing `offset` (its range is the content without quotes) and the existing file it names.
    public static func target(in text: String, of file: RelPath, at offset: Int, existing: Set<RelPath>) -> (range: NSRange, target: RelPath)? {
        let ns = text as NSString
        for t in TypstSyntax.tokens(in: text) where t.tag == .string && t.range.length >= 2 {
            let inner = NSRange(location: t.range.location + 1, length: t.range.length - 2)
            guard inner.location <= offset, offset <= NSMaxRange(inner) else { continue }
            guard let target = resolve(ns.substring(with: inner), in: file.parent), existing.contains(target) else { return nil }
            return (inner, target)
        }
        return nil
    }

    /// Typst's resolution: relative to the containing folder, "/" is the project root, "." and ".." normalized.
    /// shortcut: a string with escapes (`\`) is skipped rather than decoded; paths almost never have them.
    static func resolve(_ s: String, in dir: RelPath?) -> RelPath? {
        guard !s.isEmpty, !s.hasPrefix("@"), !s.contains("://"), !s.contains("\\") else { return nil }
        var parts = s.hasPrefix("/") ? [] : (dir?.raw.split(separator: "/").map(String.init) ?? [])
        for c in s.split(separator: "/") where c != "." {
            if c == ".." {
                guard !parts.isEmpty else { return nil }        // above the root: Typst reports an error
                parts.removeLast()
            } else {
                parts.append(String(c))
            }
        }
        return RelPath(parts.joined(separator: "/"))
    }

    /// The string reaching `target` from `dir` in the style of `original`: "/…" stays root-based, a relative one
    /// stays relative (keeping a leading "./" and a trailing "/").
    static func spell(_ target: RelPath, from dir: RelPath?, like original: String) -> String {
        let trailing = original.hasSuffix("/") ? "/" : ""
        var s: String
        if original.hasPrefix("/") {
            s = "/" + target.raw
        } else {
            let from = dir?.raw.split(separator: "/") ?? [], to = target.raw.split(separator: "/")
            var common = 0
            while common < min(from.count, to.count), from[common] == to[common] { common += 1 }
            s = (Array(repeating: "..", count: from.count - common) + to[common...].map(String.init)).joined(separator: "/")
            if s.isEmpty { s = "." }
            if original.hasPrefix("./"), !s.hasPrefix(".") { s = "./" + s }
        }
        return (s + trailing).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// What a move does to the project's path strings, read from the texts before it.
public struct ReferenceUpdates: Sendable {
    public let old: RelPath
    public let new: RelPath
    let existing: Set<RelPath>
    /// Per .typ file, keyed by its path after the move.
    public let edits: [RelPath: [Replacement]]
    public var count: Int { edits.values.reduce(0) { $0 + $1.count } }
}

extension Project {
    /// Before moving `old` to `new`: the path-string updates the move calls for, from every .typ file's current text
    /// (an open buffer wins over the disk).
    public func referenceUpdates(moving old: RelPath, to new: RelPath) -> ReferenceUpdates {
        func walk(_ nodes: [FileNode]) -> [RelPath] { nodes.flatMap { [$0.id] + walk($0.children ?? []) } }
        let existing = Set(walk(files))
        var edits: [RelPath: [Replacement]] = [:]
        for f in allFiles where FileKind.isTypst(f.raw) {
            guard let text = buffers[f]?.storage.string ?? (try? String(contentsOf: url(for: f), encoding: .utf8)) else { continue }
            let e = PathReferences.edits(in: text, of: f, moving: old, to: new, existing: existing)
            if !e.isEmpty { edits[f.replacing(old, with: new) ?? f] = e }
        }
        return ReferenceUpdates(old: old, new: new, existing: existing, edits: edits)
    }

    /// After the move succeeded: one undo step per file. The edits are recomputed on each file's current text
    /// (all inputs are from before the move, so they still hold), since it may have changed while the move ran.
    public func updateReferences(_ u: ReferenceUpdates) async throws(ProjectError) {
        for f in u.edits.keys.sorted(by: { $0.raw < $1.raw }) {
            let b = try await open(f)
            let before = f.replacing(u.new, with: u.old) ?? f
            b.apply(PathReferences.edits(in: b.storage.string, of: before, moving: u.old, to: u.new, existing: u.existing), actionName: "Update References")
        }
    }
}
