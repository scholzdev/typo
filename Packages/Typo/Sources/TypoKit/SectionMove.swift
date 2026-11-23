import Foundation
import TypstEngine

/// A heading the syntax confirms: start of its line, start of its `=` marker, level.
public struct SectionHeading: Equatable, Sendable {
    public let line: Int
    public let marker: Int
    public let level: Int
}

/// A section move as edits of the original text, plus where the moved heading's line starts afterwards.
public struct SectionMove: Equatable, Sendable {
    public let edits: [Replacement]
    public let heading: Int
    /// The moved text, for the marks in it to go along.
    public let carry: MarkCarry
}

/// Text that edits move: `length` characters at `from` land at `to` in the text after the edits, every offset at or
/// past a step's `end` (relative to `from`) shifted by its `delta` (a heading level change).
public struct MarkCarry: Equatable, Sendable {
    public struct Step: Equatable, Sendable { let end: Int, delta: Int }
    let from: Int, length: Int, to: Int
    var steps: [Step] = []

    func contains(_ r: NSRange) -> Bool { r.location >= from && NSMaxRange(r) <= from + length && r.location < from + length }

    /// Where offset `o` of the moved text is afterwards.
    func map(_ o: Int) -> Int { to + o - from + steps.filter { $0.end <= o - from }.reduce(0) { $0 + $1.delta } }

    /// The move that undoes this one.
    var inverted: MarkCarry {
        var shift = 0
        let back = steps.sorted { $0.end < $1.end }.map { s in shift += s.delta; return Step(end: s.end + shift, delta: -s.delta) }
        return MarkCarry(from: to, length: length + shift, to: from, steps: back)
    }
}

/// Sections (a heading through the line before the next heading of the same or a higher level, or the end of the
/// file) and moving them: the outline's drag and Move Section Up/Down.
public enum Sections {
    /// Lines whose first non-blank is a `=` marker the syntax tags as a heading (not raw text, not a list item's content).
    static func headings(in text: NSString, syntax: SyntaxMirror) -> [SectionHeading] {
        Folding.candidates(text).filter { c in
            syntax.spans(in: NSRange(location: c.marker, length: 1)).contains { $0.tag == .heading && $0.range.location == c.marker }
        }.map { SectionHeading(line: text.lineRange(for: NSRange(location: $0.marker, length: 0)).location, marker: $0.marker, level: $0.level) }
    }

    static func headings(in text: String) -> [SectionHeading] { headings(in: text as NSString, syntax: SyntaxMirror(text)) }

    /// The section of the heading whose line starts at `line`; also one with no body (`= A\n= B`).
    public static func range(of line: Int, in headings: [SectionHeading], length: Int) -> NSRange? {
        guard let i = headings.firstIndex(where: { $0.line == line }) else { return nil }
        let end = headings[(i + 1)...].first { $0.level <= headings[i].level }?.line ?? length
        return NSRange(location: line, length: end - line)
    }

    /// The boundary Move Section Up/Down takes the section of `line` to: before its previous sibling, or after its next
    /// one. Nil when there is no sibling that way (first or last child, or a parent heading in the way).
    public static func neighbour(of line: Int, up: Bool, in headings: [SectionHeading], length: Int) -> Int? {
        guard let i = headings.firstIndex(where: { $0.line == line }), let s = range(of: line, in: headings, length: length) else { return nil }
        let level = headings[i].level
        if up {
            guard let prev = headings[..<i].last(where: { $0.level <= level }), prev.level == level else { return nil }
            return prev.line
        }
        guard let next = headings.first(where: { $0.line == NSMaxRange(s) }), next.level == level else { return nil }
        return range(of: next.line, in: headings, length: length).map(NSMaxRange)
    }

    /// Moves the section of the heading at `line` to `boundary` (a heading line start, or the end of the text), keeping
    /// exactly one blank line between it and its new neighbours and closing the gap it leaves to one blank line. With
    /// `level`, the moved headings shift so the first one has that level (none below 1). Two edits, one removing and one
    /// inserting, so the sections in between stay untouched. Nil when `boundary` is not a section boundary outside it.
    public static func move(_ line: Int, to boundary: Int, level: Int? = nil, in text: String, headings: [SectionHeading]) -> SectionMove? {
        let ns = text as NSString, n = ns.length
        guard let s = range(of: line, in: headings, length: n), let first = headings.first(where: { $0.line == line }),
              boundary < s.location || boundary > NSMaxRange(s),
              boundary == n || headings.contains(where: { $0.line == boundary }) else { return nil }
        let nl = ns.range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n"
        let endsWithNewline = n > 0 && ns.character(at: n - 1) == 10
        func blank(_ i: Int) -> Bool { [10, 13, 32, 9].contains(ns.character(at: i)) }
        // End of the last non-blank character before `x`, then the start of the blank lines that follow it.
        func contentEnd(before x: Int) -> Int? {
            var k = x
            while k > 0, blank(k - 1) { k -= 1 }
            return k > 0 ? k : nil
        }
        func gap(before x: Int) -> (start: Int, content: Bool, newline: Bool) {
            guard let e = contentEnd(before: x) else { return (0, false, false) }
            let r = ns.range(of: "\n", range: NSRange(location: e, length: x - e))
            return r.location == NSNotFound ? (x, true, false) : (NSMaxRange(r), true, true)
        }

        var block = ns.substring(with: NSRange(location: s.location, length: contentEnd(before: NSMaxRange(s))! - s.location)) as NSString
        let length = block.length
        var steps: [MarkCarry.Step] = []
        if let level, level != first.level {
            let delta = level - first.level
            for h in headings.reversed() where h.line >= s.location && h.marker < s.location + block.length {
                block = block.replacingCharacters(in: NSRange(location: h.marker - s.location, length: h.level),
                                                  with: String(repeating: "=", count: max(1, h.level + delta))) as NSString
                steps.append(MarkCarry.Step(end: h.marker - s.location + h.level, delta: max(1, h.level + delta) - h.level))
            }
        }

        let before = gap(before: s.location)
        let removal: Replacement
        if !before.content {
            removal = Replacement(range: NSRange(location: 0, length: NSMaxRange(s)), text: "")
        } else if NSMaxRange(s) < n {
            removal = Replacement(range: NSRange(location: before.start, length: NSMaxRange(s) - before.start), text: nl)
        } else {
            let from = endsWithNewline ? before.start : contentEnd(before: s.location)!
            removal = Replacement(range: NSRange(location: from, length: n - from), text: "")
        }

        let at = gap(before: boundary)
        let lead = !at.content ? "" : at.newline ? nl : nl + nl
        let tail = boundary < n ? nl + nl : endsWithNewline ? nl : ""
        let insertion = Replacement(range: NSRange(location: at.start, length: boundary - at.start), text: lead + (block as String) + tail)
        let shift = boundary < s.location ? 0 : (removal.text as NSString).length - removal.range.length
        let heading = at.start + shift + (lead as NSString).length
        return SectionMove(edits: [insertion, removal].sorted { $0.range.location < $1.range.location }, heading: heading,
                           carry: MarkCarry(from: s.location, length: length, to: heading, steps: steps))
    }
}

extension Buffer {
    /// Every heading of the current text (none in a non-Typst file).
    public var sectionHeadings: [SectionHeading] {
        isTypst ? Sections.headings(in: storage.string as NSString, syntax: syntax) : []
    }

    /// Moves the section of the heading whose line starts at `line` to `boundary` (see `Sections.move`) as one undo step.
    /// Returns the moved heading's new line start; nil when nothing moved.
    @discardableResult public func moveSection(_ line: Int, to boundary: Int, level: Int? = nil) -> Int? {
        let heads = sectionHeadings, n = storage.length
        guard let s = Sections.range(of: line, in: heads, length: n) else { return nil }
        // A heading inside a content block (`#[ … ]`) has no section that can leave the block whole.
        let blocks = foldRegions.filter { $0.kind == .bracket }
        guard ![s.location, NSMaxRange(s), boundary].contains(where: { x in blocks.contains { $0.heading < x && x < $0.end } }),
              let m = Sections.move(line, to: boundary, level: level, in: storage.string, headings: heads) else { return nil }
        apply(m.edits, actionName: "Move Section", carry: m.carry)
        return m.heading
    }

    /// The marks inside the text `c` moves: bookmarks, folded headings, assistant marks and changes.
    func carriedMarks(_ c: MarkCarry) -> (bookmarks: [(CodeBookmark, Int)], folds: [Int], marks: [NSRange], changes: [AIChange]) {
        let bookmarks = project.bookmarks.compactMap { b -> (CodeBookmark, Int)? in
            guard b.path == path, let a = project.bookmarkAnchors[b.id], c.contains(NSRange(location: a.location, length: 0)) else { return nil }
            return (b, a.location)
        }
        return (bookmarks, folding.folded.filter { c.contains(NSRange(location: $0, length: 0)) }.sorted(),
                aiMarks.ranges.filter(c.contains), aiChanges.filter { c.contains($0.range) })
    }

    /// Puts the marks `carriedMarks` took before the edits where `c` moved their text.
    func restore(_ m: (bookmarks: [(CodeBookmark, Int)], folds: [Int], marks: [NSRange], changes: [AIChange]), _ c: MarkCarry) {
        func moved(_ r: NSRange) -> NSRange { NSRange(location: c.map(r.location), length: c.map(NSMaxRange(r)) - c.map(r.location)) }
        let text = storage.string as NSString
        if !m.bookmarks.isEmpty {
            let ids = Set(m.bookmarks.map(\.0.id))
            var all = project.bookmarks.filter { !ids.contains($0.id) }
            for (b, anchor) in m.bookmarks {
                var b = b
                b.line = CodeBookmark.line(at: c.map(anchor), in: text)
                project.bookmarkAnchors[b.id] = CodeBookmark.range(ofLine: b.line, in: text)
                all.append(b)
            }
            project.bookmarks = all
        }
        fold(m.folds.map(c.map))
        if !m.marks.isEmpty {
            var marks = aiMarks
            for r in m.marks { marks.add(moved(r)) }
            aiMarks = marks
        }
        if !m.changes.isEmpty {
            let ids = Set(m.changes.map(\.id))
            aiChanges = aiChanges.filter { !ids.contains($0.id) } + m.changes.map { var ch = $0; ch.range = moved(ch.range); return ch }
        }
    }

    /// Moves the section around `caret` before its previous sibling or after its next one; the caret keeps its place in
    /// the section. Returns the caret's new offset; nil when there is no sibling that way.
    public func moveSection(at caret: Int, up: Bool) -> Int? {
        let heads = sectionHeadings, n = storage.length
        // The last heading at or before the caret owns the innermost section around it.
        guard let h = heads.last(where: { $0.line <= caret }),
              let to = Sections.neighbour(of: h.line, up: up, in: heads, length: n),
              let new = moveSection(h.line, to: to) else { return nil }
        return min(new + caret - h.line, storage.length)
    }
}

/// Where a section dropped on an outline row goes: before that row's section or after it.
public enum SectionDrop: Sendable { case before, after }

extension Project {
    /// Moves `item`'s section before or after `target`'s, within one file (two files would be two undo steps in two
    /// undo histories). `adoptLevel`: the moved headings take `target`'s level. Returns a message when it cannot move.
    public func moveSection(_ item: OutlineItem, _ drop: SectionDrop, _ target: OutlineItem, adoptLevel: Bool = false) async -> String? {
        guard item.file == target.file else { return "Sections can only be moved within one file." }
        guard item.id != target.id, let b = try? await open(item.file) else { return nil }
        let text = b.storage.string as NSString, heads = b.sectionHeadings
        func line(_ o: Int) -> Int? { o <= text.length ? text.lineRange(for: NSRange(location: o, length: 0)).location : nil }
        guard let from = line(item.offset), heads.contains(where: { $0.line == from }), let to = line(target.offset),
              let t = Sections.range(of: to, in: heads, length: text.length) else { return "Only headings written with `=` can be moved." }
        let level = adoptLevel ? heads.first { $0.line == to }?.level : nil
        guard let new = b.moveSection(from, to: drop == .before ? to : NSMaxRange(t), level: level) else { return nil }
        show(item.file, range: NSRange(location: new, length: 0))
        return nil
    }

    /// Outline ids of headings carrying a label (on the heading line, or alone at the start of the next) that the lint
    /// reports as never referenced. Empty while lint is off; headings of files never opened are left out.
    public func unreferencedLabelHeadings(_ items: [OutlineItem]) -> Set<Int> {
        let unused = lintHints.compactMap { d -> Location? in
            guard Lint.isUnusedLabel(d), case .project(let l) = d.origin else { return nil }
            return l
        }
        guard !unused.isEmpty else { return [] }
        return Set(items.filter { h in
            guard let text = buffer(for: h.file)?.storage.string as NSString?, h.offset <= text.length else { return false }
            let heading = text.lineRange(for: NSRange(location: h.offset, length: 0))
            let next = text.lineRange(for: NSRange(location: NSMaxRange(heading), length: 0))
            return unused.contains { l in
                guard l.file == h.file else { return false }
                if NSLocationInRange(l.range.location, heading) { return true }
                return NSMaxRange(heading) < text.length && NSLocationInRange(l.range.location, next)
                    && text.substring(with: NSRange(location: next.location, length: l.range.location - next.location)).allSatisfy { $0 == " " || $0 == "\t" }
            }
        }.map(\.id))
    }

    /// Compiler errors for an `@ref` or `<label>` target that exists nowhere (no label, no bibliography key).
    public var brokenReferences: [Diagnostic] { diagnostics.filter(QuickFixes.isUnknownReference) }
}

extension Lint {
    /// Whether `d` is the "never referenced" hint of a label.
    public static func isUnusedLabel(_ d: Diagnostic) -> Bool { d.severity == .hint && d.message.hasPrefix("Label <") && d.message.hasSuffix("> is never referenced") }
}

extension QuickFixes {
    public static func isUnknownReference(_ d: Diagnostic) -> Bool {
        guard case .project = d.origin, case .unknownLabel = kind(of: d.message) else { return false }
        return true
    }
}
