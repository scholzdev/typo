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
        let n = (text as NSString).length
        guard let s = range(of: line, in: headings, length: n), boundary < s.location || boundary > NSMaxRange(s),
              boundary == n || headings.contains(where: { $0.line == boundary }),
              let c = cut(line, level: level, in: text, headings: headings) else { return nil }
        let p = paste(c.block, at: boundary, in: text)
        let shift = boundary < s.location ? 0 : (c.removal.text as NSString).length - c.removal.range.length
        let heading = p.heading + shift
        return SectionMove(edits: [p.insertion, c.removal].sorted { $0.range.location < $1.range.location }, heading: heading,
                           carry: MarkCarry(from: s.location, length: c.length, to: heading, steps: c.steps))
    }

    /// The section of the heading at `line` as text to put elsewhere (its headings shifted like `move`'s), and the edit
    /// that takes it out of `text`, leaving one blank line where it was. `length`: the section's length here.
    public static func cut(_ line: Int, level: Int? = nil, in text: String, headings: [SectionHeading])
        -> (block: String, length: Int, steps: [MarkCarry.Step], removal: Replacement)? {
        let ns = text as NSString, n = ns.length
        guard let s = range(of: line, in: headings, length: n), let first = headings.first(where: { $0.line == line }),
              let end = contentEnd(ns, before: NSMaxRange(s)), end > s.location else { return nil }
        var block = ns.substring(with: NSRange(location: s.location, length: end - s.location)) as NSString
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
        let endsWithNewline = n > 0 && ns.character(at: n - 1) == 10
        let before = gap(ns, before: s.location)
        let removal: Replacement
        if !before.content {
            removal = Replacement(range: NSRange(location: 0, length: NSMaxRange(s)), text: "")
        } else if NSMaxRange(s) < n {
            removal = Replacement(range: NSRange(location: before.start, length: NSMaxRange(s) - before.start), text: newline(ns))
        } else {
            let from = endsWithNewline ? before.start : contentEnd(ns, before: s.location)!
            removal = Replacement(range: NSRange(location: from, length: n - from), text: "")
        }
        return (block as String, length, steps, removal)
    }

    /// The edit that puts `block` at `boundary` of `text` with one blank line on each side, and where the block starts
    /// in the text after that edit alone.
    public static func paste(_ block: String, at boundary: Int, in text: String) -> (insertion: Replacement, heading: Int) {
        let ns = text as NSString, n = ns.length, nl = newline(ns)
        let endsWithNewline = n > 0 && ns.character(at: n - 1) == 10
        let at = gap(ns, before: boundary)
        let lead = !at.content ? "" : at.newline ? nl : nl + nl
        let tail = boundary < n ? nl + nl : endsWithNewline || n == 0 ? nl : ""
        return (Replacement(range: NSRange(location: at.start, length: boundary - at.start), text: lead + block + tail),
                at.start + (lead as NSString).length)
    }

    private static func newline(_ ns: NSString) -> String { ns.range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n" }
    private static func blank(_ ns: NSString, _ i: Int) -> Bool { [10, 13, 32, 9].contains(ns.character(at: i)) }

    /// End of the last non-blank character before `x`; nil when there is none.
    private static func contentEnd(_ ns: NSString, before x: Int) -> Int? {
        var k = x
        while k > 0, blank(ns, k - 1) { k -= 1 }
        return k > 0 ? k : nil
    }

    /// The start of the blank lines before `x`, whether any text comes before them, and whether a line break ends that text.
    private static func gap(_ ns: NSString, before x: Int) -> (start: Int, content: Bool, newline: Bool) {
        guard let e = contentEnd(ns, before: x) else { return (0, false, false) }
        let r = ns.range(of: "\n", range: NSRange(location: e, length: x - e))
        return r.location == NSNotFound ? (x, true, false) : (NSMaxRange(r), true, true)
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
        apply(m.edits, actionName: String(localized: "Move Section", bundle: .module), carry: m.carry)
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
    /// Moves `item`'s section before or after `target`'s, also into another file of the project. `adoptLevel`: the
    /// moved headings take `target`'s level. Returns a message when it cannot move.
    public func moveSection(_ item: OutlineItem, _ drop: SectionDrop, _ target: OutlineItem, adoptLevel: Bool = false) async -> String? {
        guard item.file == target.file else { return await moveSectionAcrossFiles(item, drop, target, adoptLevel: adoptLevel) }
        guard item.id != target.id, let b = try? await open(item.file) else { return nil }
        let text = b.storage.string as NSString, heads = b.sectionHeadings
        func line(_ o: Int) -> Int? { o <= text.length ? text.lineRange(for: NSRange(location: o, length: 0)).location : nil }
        guard let from = line(item.offset), heads.contains(where: { $0.line == from }), let to = line(target.offset),
              let t = Sections.range(of: to, in: heads, length: text.length) else { return String(localized: "Only headings written with `=` can be moved.", bundle: .module) }
        let level = adoptLevel ? heads.first { $0.line == to }?.level : nil
        guard let new = b.moveSection(from, to: drop == .before ? to : NSMaxRange(t), level: level) else { return nil }
        show(item.file, range: NSRange(location: new, length: 0))
        return nil
    }

    /// The section lands in `target`'s file first, then leaves `item`'s: each file gets one undo step of its own, and
    /// a failure in between leaves a copy rather than losing the text. Marks inside it (bookmarks, folds) stay behind.
    private func moveSectionAcrossFiles(_ item: OutlineItem, _ drop: SectionDrop, _ target: OutlineItem, adoptLevel: Bool) async -> String? {
        let refusal = String(localized: "Only headings written with `=` can be moved.", bundle: .module)
        guard let src = try? await open(item.file), let dst = try? await open(target.file), src.isTypst, dst.isTypst else { return refusal }
        let from = src.storage.string as NSString, into = dst.storage.string as NSString
        func line(_ o: Int, _ t: NSString) -> Int? { o <= t.length ? t.lineRange(for: NSRange(location: o, length: 0)).location : nil }
        let srcHeads = src.sectionHeadings, dstHeads = dst.sectionHeadings
        guard let start = line(item.offset, from), srcHeads.contains(where: { $0.line == start }), let to = line(target.offset, into),
              let s = Sections.range(of: start, in: srcHeads, length: from.length),
              let t = Sections.range(of: to, in: dstHeads, length: into.length) else { return refusal }
        let boundary = drop == .before ? to : NSMaxRange(t)
        // A heading inside a content block (`#[ … ]`) has no section that can leave or enter the block whole.
        func inBlock(_ b: Buffer, _ xs: [Int]) -> Bool { xs.contains { x in b.foldRegions.contains { $0.kind == .bracket && $0.heading < x && x < $0.end } } }
        guard !inBlock(src, [s.location, NSMaxRange(s)]), !inBlock(dst, [boundary]) else { return String(localized: "This section is inside a content block and can't leave it.", bundle: .module) }
        let level = adoptLevel ? dstHeads.first { $0.line == to }?.level : nil
        guard let c = Sections.cut(start, level: level, in: src.storage.string, headings: srcHeads) else { return refusal }
        let p = Sections.paste(c.block, at: boundary, in: dst.storage.string)
        dst.apply([p.insertion], actionName: String(localized: "Move Section", bundle: .module))
        src.apply([c.removal], actionName: String(localized: "Move Section", bundle: .module))
        show(target.file, range: NSRange(location: p.heading, length: 0))
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
    public static func isUnusedLabel(_ d: Diagnostic) -> Bool {
        guard d.severity == .hint else { return false }
        let parts = unusedLabelMessage("\u{1}").components(separatedBy: "\u{1}")      // the message in the user's language, around the name
        return parts.count == 2 && d.message.hasPrefix(parts[0]) && d.message.hasSuffix(parts[1])
    }

    static func unusedLabelMessage(_ name: String) -> String { String(localized: "Label <\(name)> is never referenced", bundle: .module) }
}

extension QuickFixes {
    public static func isUnknownReference(_ d: Diagnostic) -> Bool {
        guard case .project = d.origin, case .unknownLabel = kind(of: d.message) else { return false }
        return true
    }
}
