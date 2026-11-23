import Foundation

/// Text ranges (UTF-16) that accepted assistant edits wrote, so the gutter can mark their lines. They shift with
/// edits and are dropped when an edit touches them.
public struct AIMarks: Equatable, Sendable {
    public private(set) var ranges: [NSRange] = []
    public init() {}

    public var isEmpty: Bool { ranges.isEmpty }

    public mutating func add(_ r: NSRange) {
        guard r.length > 0 else { return }
        var merged = r
        ranges.removeAll { m in
            guard m.location <= NSMaxRange(r) && r.location <= NSMaxRange(m) else { return false }    // overlapping or touching
            merged = NSUnionRange(merged, m)
            return true
        }
        ranges.append(merged)
        ranges.sort { $0.location < $1.location }
    }

    /// `pre` was replaced by `newLength` characters. A mark entirely before the edit stays and one entirely after
    /// moves; any other is dropped (shortcut: the whole mark, not just the touched lines).
    public mutating func edited(_ pre: NSRange, newLength: Int) {
        guard !ranges.isEmpty else { return }
        let delta = newLength - pre.length
        ranges = ranges.compactMap { m in
            if pre.location >= NSMaxRange(m) { return m }
            if NSMaxRange(pre) <= m.location { return NSRange(location: m.location + delta, length: m.length) }
            return nil
        }
    }

    /// Drops the marks that overlap `r`; the text stays.
    public mutating func remove(overlapping r: NSRange) {
        ranges.removeAll { $0.location < max(NSMaxRange(r), r.location + 1) && r.location < NSMaxRange($0) }
    }

    /// Whether the character range `[lo, hi)` (a layout fragment) overlaps a mark.
    public func touches(_ lo: Int, _ hi: Int) -> Bool { ranges.contains { $0.location < max(hi, lo + 1) && lo < NSMaxRange($0) } }
}

/// One change the assistant applied, tracked so Revert can put the old text back exactly, however the file was
/// edited elsewhere since. `range` is where the written text is now; a hand edit that touches it sets `edited`,
/// and the change can then no longer be reverted.
public struct AIChange: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var range: NSRange
    public let original: String
    public let written: String
    public var edited = false

    public init(id: UUID = UUID(), range: NSRange, original: String, written: String) {
        self.id = id; self.range = range; self.original = original; self.written = written
    }

    /// `pre` was replaced by `newLength` characters: a change before it stays, one after it moves, any other is edited.
    public mutating func edited(_ pre: NSRange, newLength: Int) {
        if pre.location >= NSMaxRange(range) { return }
        if NSMaxRange(pre) <= range.location { range.location += newLength - pre.length } else { edited = true }
    }
}

extension Buffer {
    /// The mark range `[lo, hi)` (a layout fragment) lies in, or the range a pending inline diff replaces: one block of the gutter ribbon.
    public func assistantBlock(_ lo: Int, _ hi: Int) -> NSRange? {
        let top = max(hi, lo + 1)
        if let m = aiMarks.ranges.first(where: { $0.location < top && lo < NSMaxRange($0) }) { return m }
        return inlineDiff.map(\.range).flatMap { $0.location < top && lo < NSMaxRange($0) ? $0 : nil }
    }

    /// A mark whose every tracked change was made before the running turn: drawn grey as "Previous changes".
    public func isPreviousAIBlock(_ r: NSRange) -> Bool {
        let inside = aiChanges.filter { $0.range.location < max(NSMaxRange(r), r.location + 1) && r.location < NSMaxRange($0.range) }
        return !inside.isEmpty && inside.allSatisfy { previousAIChanges.contains($0.id) }
    }

    /// The tracked changes inside the mark, newest last.
    public func aiChanges(in r: NSRange) -> [AIChange] {
        aiChanges.filter { $0.range.location < max(NSMaxRange(r), r.location + 1) && r.location < NSMaxRange($0.range) }
    }

    /// Gutter "Dismiss": the mark goes, the text stays.
    public func dismissAIMark(_ r: NSRange) { aiMarks.remove(overlapping: r) }

    /// Whether the text `[lo, hi)` (a layout fragment) is marked as written by the assistant or is what a pending inline diff replaces.
    public func marksAssistantChange(_ lo: Int, _ hi: Int) -> Bool { assistantBlock(lo, hi) != nil }
}

/// The text of the bar above the prompt: "1 Change in 1 File".
public enum AssistantChangeSummary {
    public static func title(changes: Int, files: Int) -> String {
        "\(changes) \(changes == 1 ? "Change" : "Changes") in \(files) \(files == 1 ? "File" : "Files")"
    }
}

/// A proposed edit shown in the editor before it is applied: `range` is what it replaces, `replacement` what comes instead.
@MainActor public struct InlineDiffPreview {
    public let range: NSRange
    public let replacement: String
    public let accept: @MainActor () -> Void
    public let reject: @MainActor () -> Void
    public init(range: NSRange, replacement: String, accept: @escaping @MainActor () -> Void, reject: @escaping @MainActor () -> Void) {
        self.range = range; self.replacement = replacement; self.accept = accept; self.reject = reject
    }
}
