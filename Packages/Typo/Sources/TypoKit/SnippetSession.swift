import Foundation
import TypstEngine

extension Snippet {
    /// `indented(by:)`, keeping the tab-stop groups (kept as a named entry point for the insertion paths).
    public func indentedKeepingGroups(by indent: String) -> Snippet {
        var s = indented(by: indent)
        if s.groups != groups { s.groups = groups }
        return s
    }

    /// Worth tracking while typing: several stops, a mirrored group, or an exit point.
    public var needsSession: Bool {
        let order = tabOrder
        return order.count >= 2 || order.contains { $0.count > 1 } || exit != nil
    }
}

/// The tab stops of an inserted snippet while the user types into them (Tab / Shift-Tab, mirroring).
public struct SnippetSession: Equatable, Sendable {
    /// Replace `range` (valid in the text as it is right after the user's edit, all of them at once) with `text`.
    public struct Replacement: Equatable, Sendable {
        public var range: NSRange
        public var text: String
    }

    private var stops: [NSRange]            // parallel to `groups`
    private let groups: [Int]
    private let order: [Int]                // group ids in visiting order
    private var index = 0
    private var end: Int                    // caret location after the snippet
    public private(set) var isFinished = false

    public init(snippet: Snippet, insertedAt start: Int) {
        stops = snippet.placeholders.map { NSRange(location: start + $0.location, length: $0.length) }
        groups = snippet.groups
        order = snippet.order
        end = start + snippet.text.utf16.count
        isFinished = order.isEmpty && !groups.contains(0)
    }

    private func ranges(of group: Int) -> [NSRange] { stops.indices.filter { groups[$0] == group }.map { stops[$0] } }
    private var exit: NSRange? { groups.firstIndex(of: 0).map { stops[$0] } }

    /// The ranges of the active stop (all mirrors), text order.
    public var current: [NSRange] { isFinished || order.indices.contains(index) == false ? [] : ranges(of: order[index]) }

    /// Every stop's ranges that are not the exit.
    public var allStops: [NSRange] { stops.indices.filter { groups[$0] != 0 }.map { stops[$0] } }

    /// Whether `selection` lies inside one of the stops.
    public func contains(_ selection: NSRange) -> Bool { owner(of: selection) != nil }

    private func owner(of r: NSRange) -> Int? {
        let hits = stops.indices.filter { groups[$0] != 0 && stops[$0].location <= r.location && NSMaxRange(r) <= NSMaxRange(stops[$0]) }
        return hits.first { order.indices.contains(index) && groups[$0] == order[index] } ?? hits.first
    }

    /// Makes the stop containing `selection` the active one; false when it is in none.
    public mutating func select(_ selection: NSRange) -> Bool {
        guard !isFinished, let i = owner(of: selection), let g = order.firstIndex(of: groups[i]) else { return false }
        index = g
        return true
    }

    /// Advances to the next stop and returns the selection to set; past the last stop it ends the session and returns the exit
    /// (else the caret at the end of the snippet). nil once finished.
    public mutating func next() -> NSRange? {
        guard !isFinished else { return nil }
        if index + 1 < order.count {
            index += 1
            return ranges(of: order[index]).first
        }
        isFinished = true
        return exit ?? NSRange(location: end, length: 0)
    }

    /// Goes back one stop (the first stays); nil once finished.
    public mutating func previous() -> NSRange? {
        guard !isFinished, !order.isEmpty else { return nil }
        index = max(0, index - 1)
        return ranges(of: order[index]).first
    }

    /// Feeds the user's edit (`range` of the old text replaced by `replacementLength` units; `text` is the text after the edit).
    /// Edits before a stop shift it, edits inside or at the edge of a stop resize it. Returns the replacements that make the other
    /// occurrences of a mirrored stop equal to the edited one; the session already assumes they are applied, so apply them (in the
    /// given order, last location first) without feeding them back. nil: the edit touches no stop and the session is over.
    public mutating func textDidChange(at range: NSRange, replacementLength: Int, in text: NSString) -> [Replacement]? {
        guard !isFinished, let i = owner(of: range) else { isFinished = true; return nil }
        let delta = replacementLength - range.length
        for j in stops.indices where j != i && stops[j].location >= NSMaxRange(range) { stops[j].location += delta }
        stops[i].length += delta
        guard stops[i].length >= 0, NSMaxRange(stops[i]) <= text.length else { isFinished = true; return nil }
        let group = groups[i]
        guard group != 0 else { return [] }
        let new = text.substring(with: stops[i])
        var out: [Replacement] = []
        for j in stops.indices where j != i && groups[j] == group {
            guard NSMaxRange(stops[j]) <= text.length else { isFinished = true; return nil }
            if text.substring(with: stops[j]) != new { out.append(Replacement(range: stops[j], text: new)) }
        }
        // Resize the replaced mirrors, shifting everything behind each of them.
        let newLength = (new as NSString).length
        var shift = 0
        for j in stops.indices.sorted(by: { stops[$0].location < stops[$1].location }) {
            stops[j].location += shift
            if j != i, groups[j] == group, stops[j].length != newLength {
                shift += newLength - stops[j].length
                stops[j].length = newLength
            }
        }
        end += delta + shift
        return out.sorted { $0.range.location > $1.range.location }
    }
}
