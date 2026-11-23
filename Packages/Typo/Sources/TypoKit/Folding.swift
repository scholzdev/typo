import Foundation
import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// A region that can fold (design/14e): a heading's section (the lines after the heading line up to the next heading
/// of the same or a higher level, or to the end of the file) or a bracketed block spanning several lines (the lines
/// between the opening line and the closing bracket's line, which stays visible).
public struct FoldRegion: Equatable, Sendable {
    public enum Kind: Sendable { case heading, bracket }
    public let heading: Int     // start of the heading line, or of the line holding the opening bracket; unique per region
    public let level: Int       // 0 for a bracket block
    public let hidden: NSRange  // whole lines
    public let lines: Int
    public let kind: Kind
    public let end: Int         // end of the region's last line: the closing bracket's line for a block, else the hidden range's end
    /// A block's closing line without its indentation and line break (`}` or `), <label>`): drawn after the fold badge,
    /// so a folded block reads `{ ··· }` on one line as in Xcode.
    public let tail: NSRange?

    public init(heading: Int, level: Int, hidden: NSRange, lines: Int, kind: Kind = .heading, end: Int? = nil, tail: NSRange? = nil) {
        self.heading = heading; self.level = level; self.hidden = hidden; self.lines = lines; self.kind = kind
        self.end = end ?? NSMaxRange(hidden); self.tail = tail
    }
}

/// Folded sections merged into disjoint hidden ranges, each shown as the line of its outermost heading.
public struct HiddenRange: Equatable, Sendable {
    public let range: NSRange
    public let heading: Int
}

/// A region drawn on the gutter's ribbon: `depth` counts the regions around it (0 = outermost).
public struct FoldCapsule: Equatable, Sendable {
    public let region: FoldRegion
    public let depth: Int
}

public enum Folding {
    /// The regions overlapping the text offsets `visible`, outermost first so inner ones draw on top.
    public static func capsules(_ regions: [FoldRegion], in visible: Range<Int>) -> [FoldCapsule] {
        regions.filter { $0.heading < visible.upperBound && $0.end > visible.lowerBound }
            .map { r in FoldCapsule(region: r, depth: regions.filter { $0.heading < r.heading && $0.end >= r.end }.count) }
            .sorted { ($0.depth, $0.region.heading) < ($1.depth, $1.region.heading) }
    }

    /// The innermost region whose heading line or body holds offset `p`.
    public static func innermost(_ regions: [FoldRegion], at p: Int) -> FoldRegion? {
        regions.filter { $0.heading <= p && p < $0.end }.max { $0.heading < $1.heading }
    }

    /// Lines whose first non-blank character is `=`: where the marker starts and how many `=` it has. Only
    /// candidates; the syntax decides which are headings (not raw text, not a list item's content).
    static func candidates(_ text: NSString) -> [(marker: Int, level: Int)] {
        var out: [(Int, Int)] = []
        var i = 0
        let n = text.length
        while i < n {
            var j = i
            while j < n, [32, 9].contains(text.character(at: j)) { j += 1 }
            if j < n, text.character(at: j) == 61 {
                var k = j
                while k < n, text.character(at: k) == 61 { k += 1 }
                out.append((j, k - j))
            }
            i = NSMaxRange(text.lineRange(for: NSRange(location: j < n ? j : i, length: 0)))
        }
        return out
    }

    /// One region per heading (`line`: start of the heading line) whose section has at least one line.
    public static func regions(_ headings: [(line: Int, level: Int)], in text: NSString) -> [FoldRegion] {
        let heads = headings.sorted { $0.line < $1.line }
        return heads.indices.compactMap { i in
            let h = heads[i]
            let start = NSMaxRange(text.lineRange(for: NSRange(location: h.line, length: 0)))
            let end = heads[(i + 1)...].first { $0.level <= h.level }?.line ?? text.length
            guard end > start else { return nil }
            let hidden = NSRange(location: start, length: end - start)
            var lines = 0
            text.enumerateSubstrings(in: hidden, options: [.byLines, .substringNotRequired]) { _, _, _, _ in lines += 1 }
            return FoldRegion(heading: h.line, level: h.level, hidden: hidden, lines: lines)
        }
    }

    /// One region per multi-line bracket pair `(...)`, `[...]`, `{...}` with at least one line between the opening and the
    /// closing line. Brackets in strings, raw text and comments (`mode == .text`) don't count. Of several blocks opening
    /// on one line the outermost wins, since a fold is identified by its opening line.
    public static func brackets(in text: NSString, mode: (Int) -> SyntaxMode) -> [FoldRegion] {
        let pairs: [unichar: unichar] = [0x28: 0x29, 0x5B: 0x5D, 0x7B: 0x7D]
        let closers = Set(pairs.values)
        var chars = [unichar](repeating: 0, count: text.length)
        text.getCharacters(&chars, range: NSRange(location: 0, length: text.length))
        var stack: [(closer: unichar, at: Int, newlines: Int)] = []
        var out: [Int: FoldRegion] = [:]
        var newlines = 0
        for (i, c) in chars.enumerated() {
            if c == 10 { newlines += 1; continue }
            let closer = pairs[c]
            guard closer != nil || closers.contains(c), mode(i + 1) != .text else { continue }
            if let closer { stack.append((closer, i, newlines)); continue }
            guard let open = stack.last, open.closer == c else { continue }
            stack.removeLast()
            let between = newlines - open.newlines - 1
            guard between > 0 else { continue }
            let openLine = text.lineRange(for: NSRange(location: open.at, length: 0)), closeLine = text.lineRange(for: NSRange(location: i, length: 0))
            // The closing line folds too; its text comes back after the badge (`tail`).
            var tailStart = closeLine.location, tailEnd = NSMaxRange(closeLine)
            while tailStart < i, chars[tailStart] == 32 || chars[tailStart] == 9 { tailStart += 1 }
            while tailEnd > tailStart, chars[tailEnd - 1] == 10 || chars[tailEnd - 1] == 13 { tailEnd -= 1 }
            let r = FoldRegion(heading: openLine.location, level: 0,
                               hidden: NSRange(location: NSMaxRange(openLine), length: NSMaxRange(closeLine) - NSMaxRange(openLine)),
                               lines: between, kind: .bracket, end: NSMaxRange(closeLine),
                               tail: NSRange(location: tailStart, length: tailEnd - tailStart))
            if let old = out[r.heading], old.end >= r.end { continue }
            out[r.heading] = r
        }
        return Array(out.values)
    }

    /// Regions from the syntax spans (whole document, any order): multi-line display math `$ ... $`, fenced raw blocks, block
    /// comments, runs of 3+ `//` lines, and list or enum items with 2+ indented child lines. Math, raw and block comments
    /// need a line between the opening and closing line and keep the closing line as `tail` (`$ ··· $`); a comment run has an
    /// empty tail (`// first ···`); a list item has none. Delimiters in strings, raw and comments are never math or raw
    /// spans, so they need no check here.
    static func blocks(in text: NSString, spans: [SyntaxSpan]) -> [FoldRegion] {
        let spans = spans.sorted { $0.range.location < $1.range.location }
        var out: [FoldRegion] = []
        func lines(_ at: Int) -> NSRange { text.lineRange(for: NSRange(location: min(at, text.length), length: 0)) }
        func lineCount(_ r: NSRange) -> Int {
            var n = 0
            text.enumerateSubstrings(in: r, options: [.byLines, .substringNotRequired]) { _, _, _, _ in n += 1 }
            return n
        }
        // The lines after `open`'s through `close`'s; `tail` keeps the closing line's text to draw after the badge.
        func region(open: Int, close: Int, tail: Bool) {
            let o = lines(open), c = lines(close)
            guard c.location > NSMaxRange(o) else { return }
            let between = lineCount(NSRange(location: NSMaxRange(o), length: c.location - NSMaxRange(o)))
            var ts = c.location, te = NSMaxRange(c)
            while ts < close, text.character(at: ts) == 32 || text.character(at: ts) == 9 { ts += 1 }
            while te > ts, text.character(at: te - 1) == 10 || text.character(at: te - 1) == 13 { te -= 1 }
            out.append(FoldRegion(heading: o.location, level: 0, hidden: NSRange(location: NSMaxRange(o), length: NSMaxRange(c) - NSMaxRange(o)),
                                  lines: between, kind: .bracket, end: NSMaxRange(c), tail: tail ? NSRange(location: ts, length: te - ts) : nil))
        }
        // Math: `$` delimiters pair in order; an unpaired last one (unclosed math) folds nothing.
        let dollars = spans.filter { $0.tag == .mathDelimiter && text.substring(with: $0.range) == "$" }
        for i in stride(from: 0, to: dollars.count - 1, by: 2) { region(open: dollars[i].range.location, close: dollars[i + 1].range.location, tail: true) }
        // Raw: adjacent raw spans form one raw text; a fence of 3+ backticks closes with the same count of backticks.
        var group: [SyntaxSpan] = []
        func flushRaw() {
            defer { group = [] }
            guard let first = group.first, group.count > 1 else { return }
            let fence = text.substring(with: first.range)
            guard fence.count >= 3, fence.allSatisfy({ $0 == "`" }), let last = group.last, text.substring(with: last.range) == fence else { return }
            region(open: first.range.location, close: last.range.location, tail: true)
        }
        for s in spans where s.tag == .raw {
            if let l = group.last, NSMaxRange(l.range) != s.range.location { flushRaw() }
            group.append(s)
            let t = text.substring(with: s.range)
            if group.count > 1, t.count >= 3, t.allSatisfy({ $0 == "`" }), t == text.substring(with: group[0].range) { flushRaw() }
        }
        flushRaw()
        // Comments: a block comment, or a run of 3+ lines that each start with a `//` comment.
        var run: [Int] = []                                    // start offsets of consecutive line comments
        func flushRun() {
            defer { run = [] }
            guard run.count >= 3, let last = run.last else { return }
            let o = lines(run[0]), c = lines(last)
            let end = NSMaxRange(c)
            var te = end
            while te > c.location, text.character(at: te - 1) == 10 || text.character(at: te - 1) == 13 { te -= 1 }
            out.append(FoldRegion(heading: o.location, level: 0, hidden: NSRange(location: NSMaxRange(o), length: end - NSMaxRange(o)),
                                  lines: run.count - 1, kind: .bracket, end: end, tail: NSRange(location: te, length: 0)))
        }
        for s in spans where s.tag == .comment {
            let t = text.substring(with: NSRange(location: s.range.location, length: min(2, s.range.length)))
            if t == "/*" { region(open: s.range.location, close: NSMaxRange(s.range) - 1, tail: true); continue }
            let line = lines(s.range.location)
            let own = text.substring(with: NSRange(location: line.location, length: s.range.location - line.location)).allSatisfy { $0 == " " || $0 == "\t" }
            guard t == "//", own else { continue }
            if let l = run.last, lines(l).location + lines(l).length != line.location { flushRun() }
            run.append(s.range.location)
        }
        flushRun()
        // Lists: an item's children are the following lines indented deeper (blank lines between them stay inside).
        for s in spans where s.tag == .listMarker {
            let line = lines(s.range.location)
            let indent = s.range.location - line.location
            guard text.substring(with: NSRange(location: line.location, length: indent)).allSatisfy({ $0 == " " || $0 == "\t" }) else { continue }
            var pos = NSMaxRange(line), lastChild = -1, n = 0, pending = 0
            while pos < text.length {
                let l = text.lineRange(for: NSRange(location: pos, length: 0))
                var j = l.location
                while j < NSMaxRange(l), [32, 9].contains(text.character(at: j)) { j += 1 }
                if j == NSMaxRange(l) || [10, 13].contains(text.character(at: j)) { pending += 1 }
                else if j - l.location > indent { n += pending + 1; pending = 0; lastChild = NSMaxRange(l) }
                else { break }
                pos = NSMaxRange(l)
            }
            guard n >= 2 else { continue }
            out.append(FoldRegion(heading: line.location, level: 0, hidden: NSRange(location: NSMaxRange(line), length: lastChild - NSMaxRange(line)),
                                  lines: n, kind: .bracket, end: lastChild))
        }
        return out
    }

    /// Disjoint hidden ranges of `folded`, outer sections swallowing the folds inside them.
    public static func hidden(_ folded: [FoldRegion]) -> [HiddenRange] {
        var out: [HiddenRange] = []
        for r in folded.sorted(by: { $0.heading < $1.heading }) {
            if let last = out.last, r.hidden.location < NSMaxRange(last.range) {
                out[out.count - 1] = HiddenRange(range: NSUnionRange(last.range, r.hidden), heading: last.heading)
            } else {
                out.append(HiddenRange(range: r.hidden, heading: r.heading))
            }
        }
        return out
    }

    /// `p` is hidden: inside a hidden range, or the end of a file whose last section is folded.
    public static func isHidden(_ p: Int, in hidden: [HiddenRange], length: Int) -> HiddenRange? {
        hidden.first { NSLocationInRange(p, $0.range) || (p == length && NSMaxRange($0.range) == length) }
    }

    /// Whether an edit of `pre` (in a text of `length` before the edit) touches the fold hiding `h`: it changes hidden
    /// text, the heading line's line break, or inserts right before that line break or at the end of a folded last section.
    public static func touches(_ pre: NSRange, _ h: NSRange, length: Int) -> Bool {
        let end = NSMaxRange(h)
        let startsBefore = end == length ? pre.location <= end : pre.location < end
        return startsBefore && max(NSMaxRange(pre), pre.location + 1) >= h.location
    }

    /// A selection change against the folds. A caret the keyboard moved into hidden text steps over the fold (to the
    /// next visible line going forward, to the heading line's end going back). Any other selection with an end in
    /// hidden text (find, a jump) asks for the folds there to open: `reveal` lists those positions.
    public static func resolve(_ new: NSRange, from old: NSRange, keyboard: Bool, hidden: [HiddenRange], length: Int) -> (selection: NSRange, reveal: [Int]) {
        if keyboard, new.length == 0, let h = isHidden(new.location, in: hidden, length: length) {
            let forward = new.location >= old.location && NSMaxRange(h.range) < length
            return (NSRange(location: forward ? NSMaxRange(h.range) : max(h.range.location - 1, 0), length: 0), [])
        }
        var reveal: [Int] = []
        if isHidden(new.location, in: hidden, length: length) != nil { reveal.append(new.location) }
        let end = NSMaxRange(new)
        if new.length > 0, let h = isHidden(end, in: hidden, length: length), end > h.range.location { reveal.append(end) }
        return (new, reveal)
    }
}

/// A buffer's folds: heading line starts, kept through edits, plus the regions of the current text.
struct FoldState {
    var folded: Set<Int> = []
    var revision = 0                                  // bumped whenever `folded` changes
    var regions: [FoldRegion]?                        // nil after an edit until asked again
    var hidden: [HiddenRange] = []
}

extension Buffer {
    /// Every heading of the current text whose section can fold (none in a non-Typst file).
    public var foldRegions: [FoldRegion] {
        if let r = folding.regions { return r }
        let text = storage.string as NSString
        let heads = Folding.regions(headingLines, in: text)
        let taken = Set(heads.map(\.heading))
        let all = isTypst ? Folding.brackets(in: text, mode: { mode(at: $0) })
            + Folding.blocks(in: text, spans: syntax.spans(in: NSRange(location: 0, length: text.length))) : []
        // One region per start line: a heading wins, else the outermost block.
        var blocks: [FoldRegion] = []
        for b in all.sorted(by: { ($0.heading, -$0.end) < ($1.heading, -$1.end) }) where !taken.contains(b.heading) && blocks.last?.heading != b.heading { blocks.append(b) }
        let r = (heads + blocks).sorted { ($0.heading, -$0.end) < ($1.heading, -$1.end) }
        folding.regions = r
        return r
    }

    /// The heading sections only, for the outline, sticky headings and the jump bar.
    public var headingRegions: [FoldRegion] { foldRegions.filter { $0.kind == .heading } }

    /// Every heading of the current text (start of its line, level), also those without a section to fold.
    public var headingLines: [(line: Int, level: Int)] { sectionHeadings.map { (line: $0.line, level: $0.level) } }

    /// Bumped by every fold and unfold, including the ones an edit causes; the editor lays out again when it changes.
    public var foldRevision: Int { folding.revision }
    public var hiddenRanges: [HiddenRange] { folding.hidden }

    public func isFolded(_ heading: Int) -> Bool { folding.folded.contains(heading) }

    /// The hidden range `p` lies in, if any.
    public func hidden(at p: Int) -> HiddenRange? { Folding.isHidden(p, in: folding.hidden, length: storage.length) }

    /// The line a position shows on: its own, or the heading line of the fold hiding it.
    public func visibleLine(of p: Int) -> Int {
        hidden(at: p)?.heading ?? (storage.string as NSString).lineRange(for: NSRange(location: min(p, storage.length), length: 0)).location
    }

    /// The innermost section around `p` (on its heading line or in its body) that is folded or not, as asked.
    public func foldRegion(at p: Int, folded: Bool) -> FoldRegion? {
        foldRegions.last { $0.heading <= p && p < $0.end && isFolded($0.heading) == folded }
    }

    public func fold(_ headings: [Int]) { setFolded(folding.folded.union(headings.filter { h in foldRegions.contains { $0.heading == h } })) }
    public func unfold(_ headings: [Int]) { setFolded(folding.folded.subtracting(headings)) }
    /// Headings only: folding every bracket block would hide whole documents behind one outer fold.
    public func foldAll() { setFolded(Set(headingRegions.map(\.heading))) }
    public func unfoldAll() { setFolded([]) }

    /// Opens every fold hiding one of `positions`.
    public func reveal(_ positions: [Int]) {
        let n = storage.length
        unfold(foldRegions.filter { r in
            isFolded(r.heading) && positions.contains { NSLocationInRange($0, r.hidden) || ($0 == n && NSMaxRange(r.hidden) == n) }
        }.map(\.heading))
    }

    private func setFolded(_ new: Set<Int>) {
        guard new != folding.folded else { return }
        folding.folded = new
        folding.revision += 1
        folding.hidden = Folding.hidden(foldRegions.filter { new.contains($0.heading) })
    }

    /// Before an edit is processed (the storage already holds the new text): folds the edit touches open, the
    /// others move with the text. `pre` is the replaced range in the old text of `oldLength`.
    func foldsWillEdit(_ pre: NSRange, newLength: Int, oldLength: Int) {
        defer { folding.regions = nil }
        guard !folding.folded.isEmpty, let regions = folding.regions else { return }
        let touched = regions.filter { folding.folded.contains($0.heading) && Folding.touches(pre, $0.hidden, length: oldLength) }.map(\.heading)
        let kept = Set(folding.folded.subtracting(touched).compactMap { h -> Int? in
            if h < pre.location { return h }
            if h >= NSMaxRange(pre) { return h - pre.length + newLength }
            return nil                                          // the edit replaced the heading's start
        })
        if kept.count != folding.folded.count { folding.revision += 1 }
        folding.folded = kept
    }

    /// After the edit (text and syntax current): folds whose heading is gone open, and so do folds that a changed
    /// heading level stretched over the edited text. Any other change of the hidden ranges beyond the edit's shift
    /// (a heading level edited elsewhere) counts as a fold change, so the editor lays out again.
    func foldsDidEdit(_ pre: NSRange, newLength: Int) {
        guard !folding.folded.isEmpty || !folding.hidden.isEmpty else { return }
        let delta = newLength - pre.length
        let shifted = folding.hidden.compactMap { h -> NSRange? in
            if NSMaxRange(h.range) <= pre.location { return h.range }
            if h.range.location >= NSMaxRange(pre) { return NSRange(location: h.range.location + delta, length: h.range.length) }
            return nil
        }
        let edited = NSRange(location: pre.location, length: newLength)
        let regions = foldRegions
        let kept = Set(regions.filter { r in
            folding.folded.contains(r.heading) && !NSLocationInRange(edited.location, r.hidden) && NSIntersectionRange(edited, r.hidden).length == 0
        }.map(\.heading))
        folding.hidden = Folding.hidden(regions.filter { kept.contains($0.heading) })
        if kept != folding.folded || folding.hidden.map(\.range) != shifted { folding.revision += 1 }
        folding.folded = kept
    }
}

/// Hides folded sections from a text view's layout: the content storage asks it about every paragraph. It lays
/// out again whenever the shown buffer's folds change, also when an edit (typing, undo, another feature) opened one.
@MainActor public final class FoldController: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
    public weak var buffer: Buffer? { didSet { if buffer !== oldValue { applied = nil; held = nil; pad = nil } } }
    /// Also its delegate, so every paragraph lays out as a FoldFragment that can grow a placeholder.
    public weak var textLayoutManager: NSTextLayoutManager? { didSet { textLayoutManager?.delegate = self } }
    /// After a new layout: the app redraws the ruler and decorations and moves a caret out of hidden text.
    public var onChange: (() -> Void)?
    private var applied: Int?
    /// Lines the layout hides although the buffer shows them: an unfold's lines until its animation ends.
    public var held: NSRange?
    /// The fold animation's placeholder: extra height under the line starting at `line`.
    public private(set) var pad: (line: Int, extra: CGFloat)?

    public override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(edited), name: NSTextStorage.didProcessEditingNotification, object: nil)
    }

    /// Deferred: layout must not be invalidated while the storage is still processing the edit.
    @objc private func edited(_ n: Notification) {
        guard let s = n.object as? NSTextStorage, s === buffer?.storage else { return }
        Task { [weak self] in self?.update() }
    }

    /// Lays the document out again if the folds changed since the last time; only the text offsets `range` when the
    /// caller knows that is all that changed (one fold).
    public func update(_ range: NSRange? = nil) {
        guard let buffer, let tlm = textLayoutManager, buffer.foldRevision != applied else { return }
        applied = buffer.foldRevision
        tlm.invalidateLayout(for: range.flatMap(textRange) ?? tlm.documentRange)
        onChange?()
    }

    /// Lays the text offsets `range` out again (after `held` changed) and the viewport with them.
    public func relayout(_ range: NSRange) {
        guard let tlm = textLayoutManager, let r = textRange(range) else { return }
        tlm.invalidateLayout(for: r)
        tlm.textViewportLayoutController.layoutViewport()
    }

    /// Sets the placeholder under the line at `line` (nil: none) and lays the viewport out again: only that paragraph
    /// changes height, the ones after it just move. False when the line has no FoldFragment to carry it.
    @discardableResult public func setPad(_ line: Int?, _ extra: CGFloat) -> Bool {
        let old = pad?.line
        pad = line.map { ($0, extra) }
        var carried = false
        for l in Set([old, line].compactMap { $0 }) {
            guard let tlm = textLayoutManager, let loc = textRange(NSRange(location: l, length: 0))?.location,
                  let f = tlm.textLayoutFragment(for: loc) as? FoldFragment else { continue }
            f.extra = l == line ? extra : 0
            carried = carried || l == line
            tlm.invalidateLayout(for: f.rangeInElement)
        }
        textLayoutManager?.textViewportLayoutController.layoutViewport()
        return carried
    }

    private func textRange(_ r: NSRange) -> NSTextRange? {
        guard let tcs = textLayoutManager?.textContentManager as? NSTextContentStorage,
              let start = tcs.location(tcs.documentRange.location, offsetBy: r.location) else { return nil }
        return NSTextRange(location: start, end: tcs.location(start, offsetBy: r.length))
    }

    /// After the text view adopted the buffer's storage: that already laid everything out with the current folds, so
    /// this only records them and tells the app, without a second full invalidation.
    public func adopted() {
        guard let buffer else { return }
        applied = buffer.foldRevision
        onChange?()
    }

    /// The selection a text view takes instead of `new` (its selection delegate asks): the keyboard steps over a
    /// fold, any other selection of hidden text (find, a jump) opens the folds there first.
    public func selection(_ new: NSRange, from old: NSRange, keyboard: Bool) -> NSRange {
        guard let buffer, !buffer.hiddenRanges.isEmpty else { return new }
        let r = Folding.resolve(new, from: old, keyboard: keyboard, hidden: buffer.hiddenRanges, length: buffer.storage.length)
        if !r.reveal.isEmpty {
            buffer.reveal(r.reveal)
            update()
        }
        return r.selection
    }

    public nonisolated func textContentManager(_ manager: NSTextContentManager, shouldEnumerate element: NSTextElement,
                                               options: NSTextContentManager.EnumerationOptions) -> Bool {
        guard let start = element.elementRange?.location, let tcs = manager as? NSTextContentStorage else { return true }
        let p = tcs.offset(from: tcs.documentRange.location, to: start)
        return MainActor.assumeIsolated {
            !(buffer?.hiddenRanges.contains { NSLocationInRange(p, $0.range) } ?? false) && !(held.map { NSLocationInRange(p, $0) } ?? false)
        }
    }

    public nonisolated func textLayoutManager(_ m: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                                              in element: NSTextElement) -> NSTextLayoutFragment {
        let f = FoldFragment(textElement: element, range: element.elementRange)
        if let start = element.elementRange?.location, let tcs = m.textContentManager as? NSTextContentStorage {
            let p = tcs.offset(from: tcs.documentRange.location, to: start)
            f.extra = MainActor.assumeIsolated { pad.flatMap { $0.line == p ? $0.extra : nil } ?? 0 }
        }
        return f
    }
}

/// A paragraph's layout with room for the fold animation's placeholder under it: TextKit stacks the next paragraph
/// below `layoutFragmentFrame`, so growing it moves the real text after it without touching the text storage.
public final class FoldFragment: NSTextLayoutFragment, @unchecked Sendable {
    public var extra: CGFloat = 0
    public override var layoutFragmentFrame: CGRect {
        var f = super.layoutFragmentFrame
        f.size.height += extra
        return f
    }
}
