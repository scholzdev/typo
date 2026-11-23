import Foundation
import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
public typealias EditActions = NSTextStorageEditActions    // the iOS name is NSTextStorage.EditActions
#else
public typealias EditActions = NSTextStorage.EditActions
#endif

/// One open file. Its NSTextStorage is the single source of truth for that file's text.
/// The engine overlay is a mirror fed only by this delegate, and disk is a copy written by save.
@MainActor public final class Buffer: NSObject, NSTextStorageDelegate {
    public private(set) var path: RelPath
    public let storage: NSTextStorage
    public let undoManager = UndoManager()                    // per file, survives file switches
    var savedSeq: Seq                                         // seq of the text last written to disk
    var lastSeq: Seq                                          // seq of the latest edit to this file
    public var isDirty: Bool { lastSeq != savedSeq }
    /// Encoding and line ending the file had on disk; the text here is always LF (see TextFile.swift).
    var fileFormat = FileFormat()
    /// Only `.typ` files are highlighted, completed and spell-checked as Typst; other text files are plain.
    public private(set) var isTypst: Bool
    /// TOML and BibTeX files get a small scanner instead of the Typst mirror.
    private(set) var structured: StructuredLang?
    private var structuredSpans: [SyntaxSpan] = []
    private var pendingSelection: NSRange?
    var folding = FoldState()                                 // folded headings; see Folding.swift
    /// Ranges written by accepted assistant edits (gutter ribbon); they shift with edits and go when edited by hand.
    public internal(set) var aiMarks = AIMarks() { didSet { if aiMarks != oldValue { NotificationCenter.default.post(name: .bufferAIMarksChanged, object: self) } } }
    /// The changes the assistant applied that Revert can still undo; they shift with edits (see `AIChange`).
    public internal(set) var aiChanges: [AIChange] = [] { didSet { if aiChanges != oldValue { NotificationCenter.default.post(name: .bufferAIChangesChanged, object: self) } } }
    /// The assistant's pending edit being reviewed in the editor; any edit to the text dismisses it.
    public var inlineDiff: InlineDiffPreview? { didSet { NotificationCenter.default.post(name: .bufferInlineDiffChanged, object: self) } }
    /// This file's indentation: the app's settings with `.editorconfig` applied, assigned by the editor.
    public var indentSettings = IndentSettings.standard { didSet { if indentSettings.tabWidth != oldValue.tabWidth { syncWrapIndent() } } }
    public unowned let project: Project

    init(path: RelPath, text: String, seq: Seq, project: Project) {
        self.path = path
        self.storage = NSTextStorage(string: text)
        self.savedSeq = seq
        self.lastSeq = seq
        self.project = project
        self.isTypst = FileKind.isTypst(path.raw)
        self.structured = StructuredLang(path: path.raw)
        self.syntax = SyntaxMirror(text)
        super.init()
        recolor(NSRange(location: 0, length: storage.length))
        syncKerns()
        storage.delegate = self
    }

    /// Color swatches sit in a kern gap after each literal's `)` (see syncKerns).
    public static let swatchGap: CGFloat = 16
    /// The literals that currently have a swatch, kept current by syncKerns.
    public private(set) var colorLiterals: [ColorLiteral] = []
    public var colorSwatches = true { didSet { if colorSwatches != oldValue { syncKerns() } } }
    /// The inlay hints that currently have a gap (on the character before the argument), kept current by syncKerns.
    public private(set) var inlayHints: [InlayHint] = []
    /// Extra character widths by which wrapped continuation lines are indented past the paragraph's own indentation (see syncWrapIndent).
    public var wrapIndent = 0 { didSet { if wrapIndent != oldValue { syncWrapIndent() } } }

    /// Makes every `.kern` in the storage match the swatches and inlay hints: sets missing ones, corrects changed
    /// widths, clears stale ones, touches nothing else. Runs after every recolor because painting resets attributes
    /// over the repainted range, and when new hints arrive.
    func syncKerns() {
        let typst = isTypst && structured == nil
        colorLiterals = colorSwatches && typst
            ? ColorLiterals.scan(storage.string) { [syntax, n = storage.length] in
                syntax.spans(in: NSRange(location: 0, length: n)).map { ($0.tag, $0.range) } }
            : []
        let text = storage.string as NSString
        inlayHints = typst ? project.inlayHints(in: path).filter { h in
            h.offset > 0 && h.offset < text.length && ![0x0A, 0x0D].contains(text.character(at: h.offset - 1))
        } : []
        var want: [Int: CGFloat] = [:]
        for l in colorLiterals { want[NSMaxRange(l.range) - 1, default: 0] += Self.swatchGap }
        for h in inlayHints { want[h.offset - 1, default: 0] += InlayHints.gap(h.label) }
        var have: [Int: CGFloat] = [:]
        storage.enumerateAttribute(.kern, in: NSRange(location: 0, length: storage.length)) { v, r, _ in
            guard let k = (v as? NSNumber).map({ CGFloat($0.doubleValue) }) else { return }
            for i in r.location..<NSMaxRange(r) { have[i] = k }
        }
        for i in have.keys where want[i] == nil { storage.removeAttribute(.kern, range: NSRange(location: i, length: 1)) }
        for (i, k) in want where have[i] != k { storage.addAttribute(.kern, value: k, range: NSRange(location: i, length: 1)) }
        syncWrapIndent()      // the same recolors reset the paragraph styles
    }

    /// The character edit as the storage reported it, captured before highlighting touches any attribute
    /// (attribute writes inflate editedRange, and the engine must see the true edit).
    private var pendingEdit: (pre: NSRange, replacement: String)?
    let syntax: SyntaxMirror

    /// Highlights inside willProcessEditing: attributes changed there are part of the same edit and join
    /// layout invalidation, so there is no second pass and no flash of stale color.
    public nonisolated func textStorage(_ s: NSTextStorage, willProcessEditing mask: EditActions,
                                 range: NSRange, changeInLength delta: Int) {
        guard mask.contains(.editedCharacters) else { return }
        MainActor.assumeIsolated {
            let pre = NSRange(location: range.location, length: range.length - delta)
            let text = storage.string as NSString
            let replacement = text.substring(with: range)
            pendingEdit = (pre, replacement)
            foldsWillEdit(pre, newLength: range.length, oldLength: storage.length - delta)
            pendingDirty = syntax.edit(pre, replacement, expectedLength: storage.length)
            if pendingDirty == nil { syntax.setText(storage.string) }
        }
    }
    private var pendingDirty: NSRange?

    /// The funnel. Typing, paste, undo/redo, spell-correction, and find/replace all end here.
    /// Grouped edits (beginEditing...endEditing) arrive as one union range, which is still exact.
    public nonisolated func textStorage(_ s: NSTextStorage, didProcessEditing mask: EditActions,
                                 range: NSRange, changeInLength delta: Int) {
        guard mask.contains(.editedCharacters) else { return }   // attribute-only: marks, theme changes
        MainActor.assumeIsolated {
            guard let e = pendingEdit else { return }
            pendingEdit = nil
            autoClosers = PairEdit.shift(autoClosers, edit: e.pre, newLength: (e.replacement as NSString).length)
            if structured != nil { recolorStructured(edit: (e.pre, (e.replacement as NSString).length)) }
            else { recolor(pendingDirty ?? NSRange(location: 0, length: storage.length)) }
            foldsDidEdit(e.pre, newLength: (e.replacement as NSString).length)
            aiMarks.edited(e.pre, newLength: (e.replacement as NSString).length)
            project.bookmarksEdited(path, e.pre, newLength: (e.replacement as NSString).length, text: storage.string as NSString)
            for i in aiChanges.indices { aiChanges[i].edited(e.pre, newLength: (e.replacement as NSString).length) }
            if inlineDiff != nil { inlineDiff = nil }
            project.record(path, e.pre, e.replacement, newLength: storage.length)
            syncKerns()           // after record: the hints are mapped through the edit log, which now holds this edit
        }
    }

    /// The file moved or was renamed: same storage, undo history, selection and syntax mirror. Only the
    /// highlighting follows when the extension changed the file's kind.
    func rekey(to new: RelPath) {
        let kind = (FileKind.isTypst(new.raw), StructuredLang(path: new.raw) != nil)
        let changed = kind != (isTypst, structured != nil)
        path = new
        guard changed else { return }
        isTypst = kind.0
        structured = StructuredLang(path: new.raw)
        structuredSpans = []
        recolor(NSRange(location: 0, length: storage.length))
        syncKerns()
    }

    /// Rescans the whole file (small, pure) and repaints only the lines where the spans changed or that were
    /// edited: a multi-line string or a brace can recolor lines far from the edit.
    private func recolorStructured(edit: (pre: NSRange, newLength: Int)?) {
        guard let lang = structured else { return }
        let new = lang.spans(storage.string)
        let old = structuredSpans
        structuredSpans = new
        guard let edit else { Highlighter.paint(storage, new, NSRange(location: 0, length: storage.length)); return }
        let delta = edit.newLength - edit.pre.length
        let editEnd = edit.pre.location + edit.newLength
        var head = 0
        while head < min(old.count, new.count), old[head] == new[head], NSMaxRange(old[head].range) <= edit.pre.location { head += 1 }
        var tail = 0
        func shifted(_ s: SyntaxSpan) -> SyntaxSpan { SyntaxSpan(range: NSRange(location: s.range.location + delta, length: s.range.length), tag: s.tag) }
        while tail < min(old.count, new.count) - head, old.count - 1 - tail >= 0,
              old[old.count - 1 - tail].range.location >= NSMaxRange(edit.pre),
              shifted(old[old.count - 1 - tail]) == new[new.count - 1 - tail] { tail += 1 }
        var lo = edit.pre.location, hi = editEnd
        if head < old.count { lo = min(lo, old[head].range.location) }
        if head < new.count { lo = min(lo, new[head].range.location) }
        if tail < old.count - head { hi = max(hi, NSMaxRange(shifted(old[old.count - 1 - tail]).range)) }
        if tail < new.count - head { hi = max(hi, NSMaxRange(new[new.count - 1 - tail].range)) }
        let lines = (storage.string as NSString).lineRange(for: NSRange(location: min(lo, storage.length), length: max(0, min(hi, storage.length) - min(lo, storage.length))))
        Highlighter.paint(storage, new, lines)
    }

    func recolor(_ range: NSRange) {
        if structured != nil { recolorStructured(edit: nil) }
        else if isTypst { Highlighter.recolor(storage, syntax, range) }
        else {
            let r = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            if r.length > 0 { storage.setAttributes(Highlighter.base, range: r) }
        }
    }

    /// Words the spell checker may look at: markup text, not code, math, strings or raw. None in plain files.
    public func proseRanges(in range: NSRange) -> [NSRange] { isTypst ? syntax.prose(in: range) : [] }

    /// The parts of `range` outside prose: where no spelling mark may stay.
    public func nonProseRanges(in range: NSRange) -> [NSRange] {
        var out: [NSRange] = [], pos = range.location
        for p in proseRanges(in: range).sorted(by: { $0.location < $1.location }) {
            if p.location > pos { out.append(NSRange(location: pos, length: p.location - pos)) }
            pos = max(pos, NSMaxRange(p))
        }
        if pos < NSMaxRange(range) { out.append(NSRange(location: pos, length: NSMaxRange(range) - pos)) }
        return out
    }

    /// The bottom-bar edit for `selection`, nil in plain files or when nothing applies.
    public func formatEdit(_ c: Formatting.Command, selection: NSRange) -> TextEdit? {
        isTypst ? Formatting.edit(c, in: storage.string, selection: selection, syntax: syntax) : nil
    }

    /// The selection-based refactorings (equation, heading, extract); none in plain files.
    public func refactorings(selection: NSRange) -> [Refactoring] {
        isTypst ? Refactorings.available(in: storage.string, selection: selection, syntax: syntax) : []
    }

    /// Words in the prose of `selection`; 0 for an empty selection or a plain file.
    public func selectedWordCount(_ selection: NSRange) -> Int {
        selection.length == 0 ? 0 : WordCount.selected(in: storage.string, prose: proseRanges(in: selection), selection: selection)
    }

    /// What the caret at `position` edits (markup, code, math, or string/raw/comment text).
    public func mode(at position: Int) -> SyntaxMode { isTypst ? syntax.mode(at: position) : .text }

    /// The selection Tab (or Shift-Tab) should produce to move between call arguments; nil keeps the key's normal action.
    public func tabJump(from selection: NSRange, forward: Bool) -> NSRange? {
        isTypst ? TabJump.selection(in: storage.string, syntax: syntax, from: selection, forward: forward) : nil
    }

    /// Tab by the Tab key setting (nest the lines, or type one unit) as one undo step; returns the new selection.
    /// Nil leaves the key to the text view.
    public func indentAtCaret(_ selection: NSRange) -> NSRange? {
        guard let o = Indent.tab(in: storage.string, from: selection, settings: indentSettings) else { return nil }
        apply(o.edits, actionName: "Indent")
        return o.selection
    }

    /// Shift-Tab where it nests: outdents the lines by one unit as one undo step; returns the new selection.
    /// `anywhere` is the last resort of "Indents always", after a jump back declined; nil in the other modes.
    public func outdentAtCaret(_ selection: NSRange, anywhere: Bool = false) -> NSRange? {
        if anywhere, indentSettings.tabKey != .always { return nil }
        guard let o = Indent.outdent(in: storage.string, from: selection, settings: indentSettings, anywhere: anywhere) else { return nil }
        apply(o.edits, actionName: "Outdent")
        return o.selection
    }

    /// Enter: the edit that keeps (and after a bracket, deepens) the line's indentation.
    public func newlineEdit(_ selection: NSRange) -> TextEdit {
        Indent.newline(in: storage.string, selection: selection, mode: mode(at: selection.location), settings: indentSettings)
    }

    /// Re-Indent of the lines the selection reaches, as one undo step; returns the new selection. Nil in plain files
    /// or when nothing changes.
    public func reindent(_ selection: NSRange) -> NSRange? {
        guard isTypst, let o = Reindent.edits(in: storage.string, selection: selection,
                                              spans: syntax.spans(in: NSRange(location: 0, length: storage.length)), settings: indentSettings)
        else { return nil }
        apply(o.edits, actionName: "Re-Indent")
        return o.selection
    }

    /// The text to paste instead of `text` when "Re-indent on paste" applies: multi-line, Typst, outside raw, strings and comments.
    public func reindentedPaste(_ text: String, replacing selection: NSRange) -> String? {
        guard indentSettings.reindentOnPaste, isTypst, mode(at: selection.location) != .text else { return nil }
        return Reindent.pasted(text, into: storage.string, at: selection, settings: indentSettings)
    }

    private var pendingFlash = false

    /// Closers auto-inserted by the pair editor and still where it left them; every edit remaps them here.
    var autoClosers: Set<Int> = []
    var executingPair = false

    /// Where the caret was when the file was last shown; the editor restores it on a swap.
    public var selection = NSRange(location: 0, length: 0)
    /// `selection` clamped to the current text, so it can never point beyond it.
    public var restoredSelection: NSRange {
        let loc = min(selection.location, storage.length)
        return NSRange(location: loc, length: min(selection.length, storage.length - loc))
    }

    func requestSelection(_ r: NSRange, flash: Bool = false) { pendingSelection = r; pendingFlash = flash }
    public func takePendingSelection() -> NSRange? { defer { pendingSelection = nil }; return pendingSelection }
    /// True once after a click-to-source selection: the editor shows a find indicator at the caret.
    public func takePendingFlash() -> Bool { defer { pendingFlash = false }; return pendingFlash }
}

extension Buffer {
    /// Applies non-overlapping replacements through the storage funnel, like a text view edit, as one undo step on
    /// this file's undo manager. Works whether or not the file is shown; undo and redo restore all of them at once.
    /// `carry`: the edits move text, and the marks in it go along (see `MarkCarry`), also on undo and redo.
    public func apply(_ edits: [Replacement], actionName: String? = nil, carry: MarkCarry? = nil) {
        guard !edits.isEmpty else { return }
        let text = storage.string as NSString
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        var shift = 0
        let inverse = sorted.map { e -> Replacement in
            let new = (e.text as NSString).length
            defer { shift += new - e.range.length }
            return Replacement(range: NSRange(location: e.range.location + shift, length: new), text: text.substring(with: e.range))
        }
        let um = undoManager
        let own = um.groupingLevel == 0 && !um.isUndoing && !um.isRedoing   // no event group outside the run loop
        if own { um.beginUndoGrouping() }
        let marks = carry.map(carriedMarks)
        for e in sorted.reversed() { storage.replaceCharacters(in: e.range, with: e.text) }
        if let carry, let marks { restore(marks, carry) }
        um.registerUndo(withTarget: self) { b in MainActor.assumeIsolated { b.apply(inverse, carry: carry?.inverted) } }
        if let actionName { um.setActionName(actionName) }
        if own { um.endUndoGrouping() }
    }
}

extension Notification.Name {
    /// Posted with the buffer as object when its assistant marks or its inline diff change.
    public static let bufferAIMarksChanged = Notification.Name("Tympan.bufferAIMarksChanged")
    /// Posted with the buffer as object when a change the assistant applied moves or can no longer be reverted.
    public static let bufferAIChangesChanged = Notification.Name("Tympan.bufferAIChangesChanged")
    public static let bufferInlineDiffChanged = Notification.Name("Tympan.bufferInlineDiffChanged")
}

extension Buffer {
    /// `apply` for an assistant edit: the text it wrote is marked in the gutter and tracked for `revertAssistant`.
    /// Returns the id of each change, in range order.
    @discardableResult public func applyAssistant(_ edits: [Replacement], actionName: String? = nil) -> [UUID] {
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        let text = storage.string as NSString
        var shift = 0
        let changes = sorted.map { e -> AIChange in
            let new = (e.text as NSString).length
            defer { shift += new - e.range.length }
            return AIChange(range: NSRange(location: e.range.location + shift, length: new), original: text.substring(with: e.range), written: e.text)
        }
        apply(edits, actionName: actionName)
        var marks = aiMarks
        for c in changes { marks.add(c.range) }
        aiMarks = marks
        aiChanges += changes
        return changes.map(\.id)
    }

    /// Whether the change is still there exactly as written: no hand edit touched it since.
    public func canRevert(_ id: UUID) -> Bool {
        guard let c = aiChanges.first(where: { $0.id == id }), !c.edited, NSMaxRange(c.range) <= storage.length else { return false }
        return (storage.string as NSString).substring(with: c.range) == c.written
    }

    /// Puts the text the change replaced back, as one undo step; other edits of the file stay. False when `canRevert` is false.
    @discardableResult public func revertAssistant(_ id: UUID, actionName: String? = "Revert Assistant Change") -> Bool {
        guard canRevert(id), let c = aiChanges.first(where: { $0.id == id }) else { return false }
        aiChanges.removeAll { $0.id == id }
        apply([Replacement(range: c.range, text: c.original)], actionName: actionName)
        return true
    }
}

extension Project {
    /// `edit` for an accepted assistant edit; see `Buffer.applyAssistant`.
    @discardableResult public func assistantEdit(_ path: RelPath, _ edits: [Replacement], actionName: String? = nil) async throws(ProjectError) -> [UUID] {
        try await open(path).applyAssistant(edits, actionName: actionName)
    }

    /// Edits a file whether or not it is open: loads its buffer without showing it, then applies `edits` as one
    /// undo step. Autosave writes it like any other edit.
    public func edit(_ path: RelPath, _ edits: [Replacement], actionName: String? = nil) async throws(ProjectError) {
        try await open(path).apply(edits, actionName: actionName)
    }
}
