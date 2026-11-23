import AppKit
import TypoKit
import TypstEngine

extension SettingsKey {
    static let lineNumbers = "showLineNumbers"
    static let foldingRibbon = "codeFoldingRibbon"
    static let foldDuration = "codeFoldingDuration"                // seconds
    static let scopeGuides = "scopeGuides"                       // "none" or "indentation"
    static let formatGuide = "showFormatGuide"
    static let formatOnComplete = "formatOnComplete"
    static let highlightOccurrences = "highlightOccurrences"
    static let occurrenceDelay = "occurrenceHighlightDelay"
    static let overscroll = "editorOverscroll"                   // "none", "small", "medium", "large"
    static let wrapLines = "wrapLines"
    static let wrapIndent = "wrapIndent"
}

/// The Display settings as the editor reads them outside SwiftUI views; the defaults match TextEditingDisplaySettings.
enum DisplaySettings {
    private static var d: UserDefaults { .standard }
    static var lineNumbers: Bool { d.object(forKey: SettingsKey.lineNumbers) as? Bool ?? true }
    static var folding: Bool { d.object(forKey: SettingsKey.foldingRibbon) as? Bool ?? true }
    static var foldDuration: Double { min(max(d.object(forKey: SettingsKey.foldDuration) as? Double ?? FoldPaper.duration, 0.05), 2) }
    static var scopeGuides: Bool { d.string(forKey: SettingsKey.scopeGuides) == "indentation" }
    static var formatGuide: Bool { d.object(forKey: SettingsKey.formatGuide) as? Bool ?? false }
    static var formatOnComplete: Bool { d.object(forKey: SettingsKey.formatOnComplete) as? Bool ?? false }
    static var highlightOccurrences: Bool { d.object(forKey: SettingsKey.highlightOccurrences) as? Bool ?? true }
    static var occurrenceDelay: Double { d.object(forKey: SettingsKey.occurrenceDelay) as? Double ?? 0.25 }
    static var overscroll: CGFloat { ["small": 0.25, "medium": 0.5, "large": 0.75][d.string(forKey: SettingsKey.overscroll) ?? ""] ?? 0 }
    static var wrapLines: Bool { d.object(forKey: SettingsKey.wrapLines) as? Bool ?? true }
    static var wrapIndent: Int { d.object(forKey: SettingsKey.wrapIndent) as? Int ?? 0 }
    static var formatWidth: Int { d.object(forKey: SettingsKey.formatWidth) as? Int ?? 80 }
    static var formatIndent: Int { d.object(forKey: SettingsKey.formatIndent) as? Int ?? 2 }
    /// The gutter shows while it has something to show; Focus Mode hides it regardless.
    static var gutter: Bool { lineNumbers || folding || SourceControl.showsChanges }
    /// Spaces per scope guide level: what Enter and Tab indent by.
    static var guideUnit: Int { max(1, formatIndent) }
}

/// The editor's Display state that is not in UserDefaults.
struct DisplayState {
    struct PendingFormat { weak var buffer: Buffer?; let start: Int; let tail: Int }   // tail: characters after the insertion
    var folding = true
    var wraps = true
    var overscroll: CGFloat = 0                                  // the bottom inset last applied
    var observing = false
    var occurrences: Task<Void, Never>?
    var pendingFormat: PendingFormat?
}

/// What the decoration layer draws for the Display settings.
struct DisplayDecor: Equatable {
    var scopeGuides = false
    var guideColumn: Int?
    var occurrences: [NSRange] = []
}

extension EditorView.Coordinator {
    // Runs on every defaults change, so it must be idempotent and cheap.
    func applyDisplaySettings(_ tv: NSTextView, _ scroll: NSScrollView) {
        if !display.observing {
            display.observing = true
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(clipResized), name: NSView.frameDidChangeNotification, object: scroll.contentView)
            nc.addObserver(self, selector: #selector(clipScrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        }
        display.folding = DisplaySettings.folding
        if !display.folding, buffer?.hiddenRanges.isEmpty == false { unfoldAll() }     // no fold may stay without its triangle
        if let ruler = scroll.verticalRulerView as? LineNumberRuler {
            let numbers = DisplaySettings.lineNumbers
            let width = Self.gutterWidth(numbers: numbers, folding: display.folding)
            let relative = VimController.relativeNumbers
            if ruler.showsNumbers != numbers || ruler.ruleThickness != width || ruler.relative != relative {
                ruler.relative = relative
                ruler.showsNumbers = numbers
                ruler.ruleThickness = width
                ruler.needsDisplay = true
            }
        }
        buffer?.wrapIndent = DisplaySettings.wrapIndent
        setWraps(DisplaySettings.wrapLines, tv, scroll)
        applyOverscroll()
        decor?.display.scopeGuides = DisplaySettings.scopeGuides
        decor?.display.guideColumn = DisplaySettings.formatGuide ? DisplaySettings.formatWidth : nil
        if !DisplaySettings.highlightOccurrences { decor?.display.occurrences = [] }
    }

    /// Four digits plus the fold triangles' column (as `applyStyle` sizes it); without numbers just the triangles and the bar zone.
    private static func gutterWidth(numbers: Bool, folding: Bool) -> CGFloat {
        if numbers {
            let digits = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            return max(40, ceil(("8888" as NSString).size(withAttributes: [.font: digits]).width) + 14) + 10
        }
        return (folding ? 14 : 0) + GitGutter.barZone + 2    // the bar zone is also the assistant ribbon's, so it stays without git
    }

    @objc private func clipResized() {
        applyOverscroll()
        if !display.wraps, let tv = textView, let clip = tv.enclosingScrollView?.contentView { tv.minSize.width = clip.bounds.width }
    }

    /// Without wrapping the pills sit at the visible right edge, so horizontal scrolling moves them.
    @objc private func clipScrolled() { if !display.wraps { decor?.needsDisplay = true } }

    // MARK: Wrapping

    private func setWraps(_ on: Bool, _ tv: NSTextView, _ scroll: NSScrollView) {
        guard on != display.wraps, let container = tv.textContainer else { return }
        display.wraps = on
        (scroll as? AnchoredScrollView)?.holdAnchor()
        let clip = scroll.contentView.bounds.width
        scroll.hasHorizontalScroller = !on
        tv.isHorizontallyResizable = !on
        container.widthTracksTextView = on
        if on {
            tv.minSize.width = 0
            tv.setFrameSize(NSSize(width: clip, height: tv.frame.height))
        } else {
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.minSize.width = clip
            container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
        decor?.refresh()
        (scroll as? AnchoredScrollView)?.settleAnchor()
    }

    // MARK: Overscroll

    /// Extra scrollable space below the last line, as a share of the visible height; none while typewriter scrolling in
    /// Focus Mode already gives half a screen. The automatic top inset is kept as it was.
    func applyOverscroll() {
        guard let scroll = textView?.enclosingScrollView else { return }
        let typewriter = layout?.focus == true && UserDefaults.standard.bool(forKey: SettingsKey.typewriter)
        let bottom = typewriter ? 0 : floor(scroll.contentSize.height * DisplaySettings.overscroll)
        guard bottom != display.overscroll else { return }
        display.overscroll = bottom
        let top = scroll.contentInsets.top
        if bottom == 0 {
            scroll.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            scroll.automaticallyAdjustsContentInsets = true
        } else {
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        }
    }

    // MARK: Instances of the selected symbol

    /// Clears the marks at once; after the delay marks the other occurrences of the name at the caret.
    func refreshOccurrences() {
        display.occurrences?.cancel()
        decor?.display.occurrences = []
        guard DisplaySettings.highlightOccurrences, let tv = textView, tv.selectedRange().length == 0, let buffer, buffer.isTypst else { return }
        let storage = buffer.storage, text = storage.string, file = buffer.path, at = tv.selectedRange().location
        let delay = DisplaySettings.occurrenceDelay
        display.occurrences = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let ranges = await Self.occurrences(in: text, file: file, at: at)
            guard !Task.isCancelled, let self, self.buffer?.storage === storage, storage.string == text else { return }
            self.decor?.display.occurrences = ranges
        }
    }

    @concurrent private static func occurrences(in text: String, file: RelPath, at offset: Int) async -> [NSRange] {
        Occurrences.ranges(in: text, file: file, at: offset)
    }

    // MARK: Reformat after completion

    /// After an accepted completion at `start..<end`: formats it now, or once its snippet's tab stops are done.
    func completionInserted(at start: Int, end: Int) {
        guard DisplaySettings.formatOnComplete, let buffer, buffer.isTypst else { return }
        display.pendingFormat = DisplayState.PendingFormat(buffer: buffer, start: start, tail: buffer.storage.length - end)
        if snippetSession == nil { formatCompletion() }
    }

    /// From `snippetSession`'s didSet. Undo and redo end a session too: they drop the format.
    func snippetSessionEnded() {
        guard display.pendingFormat != nil else { return }
        if let um = buffer?.undoManager, um.isUndoing || um.isRedoing { display.pendingFormat = nil; return }
        formatCompletion()
    }

    /// Deferred: the session can end inside an edit. Quietly does nothing unless the caret is still in the inserted text
    /// and typstyle can format it (code or math, no syntax errors); the caret keeps its place in the text.
    private func formatCompletion() {
        Task { [weak self] in
            guard let self, self.snippetSession == nil, let p = self.display.pendingFormat else { return }
            self.display.pendingFormat = nil
            guard let tv = self.textView, let buffer = self.buffer, p.buffer === buffer else { return }
            let end = buffer.storage.length - p.tail, sel = tv.selectedRange()
            guard p.start <= end, p.start <= sel.location, NSMaxRange(sel) <= end,
                  [.code, .math].contains(buffer.mode(at: p.start)),
                  let r = buffer.codeFormatEdit(selection: NSRange(location: p.start, length: end - p.start),
                                                width: DisplaySettings.formatWidth, indent: DisplaySettings.formatIndent) else { return }
            let new = (r.text as NSString).length, rEnd = NSMaxRange(r.range)
            let caret = sel.location >= rEnd ? sel.location + new - r.range.length : min(sel.location, r.range.location + new)
            self.replace(r.range, with: r.text, selecting: NSRange(location: max(caret, 0), length: 0))
        }
    }
}

// MARK: Drawing

extension DecorationView {
    /// Thin lines at each indentation level of the visible lines; a blank line continues the guides of its block.
    func drawScopeGuides(_ lines: [(frag: NSTextLayoutFragment, frame: NSRect, start: Int)], text: NSString) {
        guard display.scopeGuides, !lines.isEmpty else { return }
        let unit = DisplaySettings.guideUnit
        let levels = ScopeGuides.levels(in: text, lineStarts: lines.map(\.start), unit: unit)
        // Positions come from the layout, so tabs are right; a blank line borrows them from a line that has the blanks.
        var shared: [Int: CGFloat] = [:]
        let own = lines.map { l -> [CGFloat] in
            guard let first = l.frag.textLineFragments.first else { return [] }
            let line = text.substring(with: text.lineRange(for: NSRange(location: l.start, length: 0)))
            let xs = ScopeGuides.starts(of: line, unit: unit).map { l.frame.minX + first.typographicBounds.minX + first.locationForCharacter(at: $0).x }
            for (k, x) in xs.enumerated() where shared[k] == nil { shared[k] = x }
            return xs
        }
        let char = ("0" as NSString).size(withAttributes: [.font: Highlighter.baseFont]).width
        Highlighter.style.colors.text.withAlphaComponent(0.12).setFill()
        for (i, l) in lines.enumerated() where levels[i] > 0 {
            for k in 0..<levels[i] {
                guard let x = k < own[i].count ? own[i][k] : shared[k] ?? shared[0].map({ $0 + CGFloat(k * unit) * char }) else { continue }
                NSRect(x: floor(x), y: l.frame.minY, width: 1, height: l.frame.height).fill()
            }
        }
    }

    /// The column typstyle wraps at, across the text.
    func drawFormatGuide(_ tv: NSTextView, in dirty: NSRect) {
        guard let column = display.guideColumn else { return }
        let char = ("0" as NSString).size(withAttributes: [.font: Highlighter.baseFont]).width
        let x = tv.textContainerOrigin.x + (tv.textContainer?.lineFragmentPadding ?? 0) + CGFloat(column) * char
        Highlighter.style.colors.text.withAlphaComponent(0.15).setFill()
        NSRect(x: floor(x), y: dirty.minY, width: 1, height: dirty.height).fill()
    }

    /// The other occurrences of the name at the caret: the bracket highlight's shape, fainter.
    func drawOccurrences(tlm: NSTextLayoutManager, tcs: NSTextContentStorage, length: Int, origin: NSPoint) {
        let color = Highlighter.style.colors.text
        for r in display.occurrences where NSMaxRange(r) <= length {
            guard let range = tcs.textRange(for: r) else { continue }
            tlm.enumerateTextSegments(in: range, type: .selection, options: []) { _, rect, _, _ in
                let path = NSBezierPath(roundedRect: rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
                color.withAlphaComponent(0.09).setFill()
                path.fill()
                color.withAlphaComponent(0.25).setStroke()
                path.lineWidth = 1
                path.stroke()
                return true
            }
        }
    }
}
