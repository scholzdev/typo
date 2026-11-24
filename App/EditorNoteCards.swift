import AppKit
import TypoKit
import TypstEngine

/// Presenter note lines (`#metadata("…") <note>` alone on a line) shown as editable cards. The text is untouched: the
/// FoldController lays such a line out as a card-tall fragment without drawing it, and a card view sits on top. The
/// keyboard steps over a card like over a fold. A note sharing its line is a pill the decoration view draws over its
/// call, edited in a popover; the keyboard steps over its call. The note mark in the gutter toggles a line's card or
/// pills to their code and back; the caret alone never does.
/// How presenter notes show in the editor (View › Presenter Notes in Editor): full cards, one-line cards, or hidden
/// with only the gutter mark (a note sharing its line keeps a bare note symbol, as hiding it would move the text).
enum NoteDisplay: String, CaseIterable {
    case cards, compact, hidden
    static let key = "editorNoteDisplay"
    static let changed = Notification.Name("NoteDisplayChanged")
    static var current: NoteDisplay { UserDefaults.standard.string(forKey: key).flatMap(NoteDisplay.init) ?? .cards }
}

@MainActor final class NoteCards {
    private weak var editor: EditorView.Coordinator?
    private var lines: [PresenterNotes.CardLine] = []
    /// Kept in step with edits as they happen (an edit inside one drops it), so a pill does not wait for the re-read.
    private var pills: [PresenterNotes.InlineNote] = []
    private weak var linesStorage: NSTextStorage?
    /// The text changed since `lines` was read; cleared by the deferred re-read.
    private var edited = false
    private var views: [Int: PresenterNoteCard] = [:]
    private var spare: [PresenterNoteCard] = []
    /// The line a fresh Add Presenter Note inserted, whose card takes focus once laid out.
    private var added: Replacement?
    private var pendingFocus: Int?
    /// Line starts of the notes switched to their code from the gutter; edits move them along with the text.
    private var sourceShown: Set<Int> = []

    init(editor: EditorView.Coordinator) {
        self.editor = editor
        NotificationCenter.default.addObserver(self, selector: #selector(storageEdited), name: NSTextStorage.didProcessEditingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged), name: NoteDisplay.changed, object: nil)
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }

    private var textView: NSTextView? { editor?.textView }

    @objc private func displayChanged() {
        if views.values.contains(where: \.isEditing) { textView?.window?.makeFirstResponder(textView) }
        refresh()
    }

    @objc private func storageEdited(_ n: Notification) {
        guard let s = n.object as? NSTextStorage, s === textView?.textContentStorage?.textStorage, s.editedMask.contains(.editedCharacters) else { return }
        let at = s.editedRange.location, delta = s.changeInLength
        sourceShown = Set(sourceShown.compactMap { $0 > at ? ($0 + delta >= at ? $0 + delta : nil) : $0 })
        let preEnd = at + s.editedRange.length - delta
        pills = pills.compactMap { p in
            if at >= NSMaxRange(p.call) { return p }
            guard preEnd <= p.call.location else { return nil }
            var q = p
            q.call.location += delta
            if q.lineStart > at { q.lineStart = max(at, q.lineStart + delta) }
            return q
        }
        guard !edited else { return }
        edited = true
        Task { [weak self] in
            guard let self else { return }
            reread()
            refresh()
        }
    }

    private func reread() {
        let storage = textView?.textContentStorage?.textStorage
        (lines, pills) = editor?.buffer?.isTypst == true ? storage.map { PresenterNotes.noteLines(in: $0.string) } ?? ([], []) : ([], [])
        linesStorage = storage
        edited = false
    }

    private func holds(_ p: Int, _ line: NSRange, length: Int) -> Bool {
        NSLocationInRange(p, line) || (p == length && NSMaxRange(line) == length)
    }

    /// A single-character delete (Backspace, Forward Delete) that would cut into a shown pill's hidden code takes the
    /// whole note instead, as one undo step; true when it did.
    func deletePill(touching range: NSRange, replacement: String?) -> Bool {
        guard replacement == "", range.length <= 1, !edited, let tv = textView, let buffer = editor?.buffer, editor?.readOnly == false,
              linesStorage === tv.textContentStorage?.textStorage,
              let pill = pills.first(where: { !sourceShown.contains($0.lineStart) && NSIntersectionRange($0.call, range).length > 0 })
        else { return false }
        buffer.apply([PresenterNotes.replacement(for: pill.call, in: tv.string, writing: "")], actionName: String(localized: "Delete Presenter Note"))
        return true
    }

    /// The pills to draw: those of the shown file whose line is not switched to its code.
    var shownPills: [PresenterNotes.InlineNote] {
        linesStorage === textView?.textContentStorage?.textStorage ? pills.filter { !sourceShown.contains($0.lineStart) } : []
    }

    /// The selection a keyboard move takes: over a card, as over a fold, and over a pill's call to its other side. A
    /// line switched to its code is left alone.
    func selection(_ new: NSRange, from old: NSRange, keyboard: Bool) -> NSRange {
        guard keyboard, let tv = textView, tv.window?.firstResponder === tv else { return new }
        if new.length == 0, let p = shownPills.first(where: { $0.call.location < new.location && new.location < NSMaxRange($0.call) }) {
            return NSRange(location: new.location >= old.location ? NSMaxRange(p.call) : p.call.location, length: 0)
        }
        guard !edited, !lines.isEmpty else { return new }
        let length = (tv.string as NSString).length
        let hidden = lines.filter { !sourceShown.contains($0.line.location) }.map { HiddenRange(range: $0.line, heading: $0.line.location) }
        return Folding.resolve(new, from: old, keyboard: true, hidden: hidden, length: length).selection
    }

    /// Recomputes which lines are cards and how tall, then lays them out; a no-op while an edit's re-read is pending.
    func refresh() {
        guard !edited, let tv = textView, let folds = editor?.folds else { return }
        if linesStorage !== tv.textContentStorage?.textStorage {
            // Another file is shown: a card being edited commits to its own file first.
            if views.values.contains(where: \.isEditing) { tv.window?.makeFirstResponder(tv) }
            sourceShown = []
            reread()
        }
        let width = cardWidth(tv), display = NoteDisplay.current
        var map: [Int: CGFloat] = [:]
        for l in lines where !sourceShown.contains(l.line.location) {
            let editing = views[l.line.location].flatMap { $0.isEditing ? $0.text : nil }
            // A negative height collapses the line (see FoldFragment.card).
            map[l.line.location] = display == .hidden ? -1 : PresenterNoteCard.height(editing ?? l.text, width: width, compact: display == .compact)
        }
        folds.setCards(map)
        place()
        editor?.decor?.needsDisplay = true
        tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true   // the line numbers move with a card's height
    }

    private func cardWidth(_ tv: NSTextView) -> CGFloat {
        let padding = tv.textContainer?.lineFragmentPadding ?? 5
        return max(160, min(640, (tv.textContainer?.size.width ?? tv.bounds.width) - 2 * padding - 12))
    }

    /// Puts a card over every card line in the viewport. Called after each viewport layout: only moves views.
    func place() {
        guard !edited, let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage,
              linesStorage === tcs.textStorage, let viewport = tlm.textViewportLayoutController.viewportRange else { return }
        let byStart = Dictionary(lines.map { ($0.line.location, $0) }, uniquingKeysWith: { a, _ in a })
        let end = tcs.offset(of: viewport.endLocation), origin = tv.textContainerOrigin
        let x = origin.x + (tv.textContainer?.lineFragmentPadding ?? 5), width = cardWidth(tv)
        var placed: [Int: PresenterNoteCard] = [:]
        var old = views
        tlm.enumerateTextLayoutFragments(from: viewport.location, options: []) { frag in
            let start = tcs.offset(of: frag.rangeInElement.location)
            guard start < end else { return false }
            guard let f = frag as? FoldFragment, f.card > 0, let line = byStart[start] else { return true }
            let card = old.removeValue(forKey: start) ?? spare.popLast() ?? makeCard(in: tv)
            card.show(line, of: editor?.buffer, readOnly: editor?.readOnly ?? true)
            card.frame = NSRect(x: x, y: f.layoutFragmentFrame.minY + origin.y + PresenterNoteCard.margin, width: width, height: f.card - 2 * PresenterNoteCard.margin)
            card.isHidden = false
            placed[start] = card
            return true
        }
        // A card being edited stays, also when scrolled away: hiding it would end the edit in the middle of layout.
        for (start, card) in old {
            if card.isEditing { placed[start] = card } else { card.isHidden = true; spare.append(card) }
        }
        views = placed
        if let p = pendingFocus, let card = views[p] {
            pendingFocus = nil
            card.added = added
            added = nil
            // Not inside the layout callback: scrolling and a focus change lay out again.
            Task { tv.scrollToVisible(card.frame); card.focus() }
        }
    }

    private func makeCard(in tv: NSTextView) -> PresenterNoteCard {
        let card = PresenterNoteCard()
        card.onCommit = { [weak self] c, text in self?.commit(c, text) }
        card.onEndEditing = { [weak self] in self?.endEditing() }
        card.onResize = { [weak self] in self?.refresh() }
        tv.addSubview(card)
        return card
    }

    // MARK: Editing

    /// Add Presenter Note: an empty note on its own line after the caret's line, whose card takes the focus. Left
    /// empty, the line goes again with the undo step that added it.
    func add() {
        guard let tv = textView, let buffer = editor?.buffer else { return }
        let sel = tv.selectedRange()
        let edit = PresenterNotes.insertion(of: PresenterNotes.written(""), afterLineAt: sel.location, in: tv.string)
        buffer.apply([edit], actionName: String(localized: "Add Presenter Note"))
        editor?.selectProgrammatically(sel, in: tv, scroll: false)
        reread()
        let line = edit.range.location + 1
        added = edit
        pendingFocus = line
        tv.scrollRangeToVisible(NSRange(location: line, length: 0))
        refresh()
        tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
    }

    private func endEditing() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    /// Writes the card's text over its note as one undo step; empty text removes the line. Deferred, since focus can
    /// leave a card in the middle of a layout.
    private func commit(_ card: PresenterNoteCard, _ text: String) {
        guard let original = card.line, let buffer = card.buffer else { return }
        let added = card.added
        card.added = nil
        Task { [weak self] in
            guard let self, editor?.readOnly == false else { return }
            let new = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
            let source = buffer.storage.string
            guard let now = PresenterNotes.cardLines(in: source).filter({ $0.text == original.text })
                    .min(by: { abs($0.call.location - original.call.location) < abs($1.call.location - original.call.location) }) else { return }
            let um = buffer.undoManager, addName = String(localized: "Add Presenter Note")
            if let added, now.text.isEmpty, now.call.location == added.range.location + 1, um.canUndo, um.undoActionName == addName {
                // The add and the text become one undo step: take the empty note back and add the written one.
                um.undo()
                if !new.isEmpty { buffer.apply([Replacement(range: added.range, text: "\n" + PresenterNotes.written(new))], actionName: addName) }
            } else if new != original.text {
                buffer.apply([PresenterNotes.replacement(for: now.call, in: source, writing: new)], actionName: String(localized: "Edit Presenter Note"))
            }
        }
    }

    /// Opens a popover at `anchor` (in the decoration view) editing `pill`; its text is written back when it closes.
    func edit(_ pill: PresenterNotes.InlineNote, anchor: NSRect) {
        guard let decor = editor?.decor, let buffer = editor?.buffer else { return }
        let popover = NSPopover()
        let content = NotePillEditor(text: pill.text, editable: editor?.readOnly == false, popover: popover)
        content.onClose = { [weak self, weak buffer] text in
            guard let self, let buffer else { return }
            Task { self.commit(pill, text, in: buffer) }
        }
        popover.behavior = .transient
        popover.contentViewController = content
        popover.delegate = content
        popover.show(relativeTo: anchor, of: decor, preferredEdge: .maxY)
    }

    /// Writes a pill's text over its call as one undo step; empty text removes the call and one space next to it.
    private func commit(_ pill: PresenterNotes.InlineNote, _ text: String, in buffer: Buffer) {
        guard editor?.readOnly == false else { return }
        let new = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
        let source = buffer.storage.string
        guard new != pill.text, let now = PresenterNotes.inlineNotes(in: source).filter({ $0.text == pill.text })
                .min(by: { abs($0.call.location - pill.call.location) < abs($1.call.location - pill.call.location) }) else { return }
        buffer.apply([PresenterNotes.replacement(for: now.call, in: source, writing: new)], actionName: String(localized: "Edit Presenter Note"))
    }

    /// For the gutter: nil when the line at `start` holds no note card or pill, else whether it shows as one.
    func mark(at start: Int) -> Bool? {
        guard !edited, lines.contains(where: { $0.line.location == start }) || pills.contains(where: { $0.lineStart == start }) else { return nil }
        return !sourceShown.contains(start)
    }

    /// The gutter's note mark: card or pills to code and back. A caret in the line moves to the start of the next line
    /// when the card comes back (the end of the one before at the end of the text), so it does not sit in code no longer
    /// drawn; a caret inside a pill's call moves to its end.
    func toggle(at start: Int) {
        guard let tv = textView, let editor, mark(at: start) != nil else { return }
        tv.window?.makeFirstResponder(tv)
        let caret = tv.selectedRange().location
        if sourceShown.remove(start) == nil {
            sourceShown.insert(start)
        } else if let pill = pills.first(where: { $0.lineStart == start && $0.call.location < caret && caret < NSMaxRange($0.call) }) {
            editor.selectProgrammatically(NSRange(location: NSMaxRange(pill.call), length: 0), in: tv, scroll: false)
        } else if let line = lines.first(where: { $0.line.location == start }),
                  NSLocationInRange(caret, line.line) || caret == NSMaxRange(line.line) {
            let length = (tv.string as NSString).length
            let to = NSMaxRange(line.line) < length || start == 0 ? min(NSMaxRange(line.line), length) : start - 1
            editor.selectProgrammatically(NSRange(location: to, length: 0), in: tv, scroll: false)
        }
        refresh()
    }

    /// Whether `point` (text view coordinates) is over a card: hover and ⌘-hover leave the hidden code alone.
    func covers(_ point: NSPoint) -> Bool { views.values.contains { !$0.isHidden && $0.frame.contains(point) } }
}

/// One note card: a sticky-note box with a header and the note's text, editable in place.
@MainActor final class PresenterNoteCard: NSView, NSTextViewDelegate {
    static let margin: CGFloat = 2
    private static let pad: CGFloat = 6, header: CGFloat = 18, maxLines: CGFloat = 6
    private static var font: NSFont { .systemFont(ofSize: Highlighter.fontSize) }

    /// Card height (with its margins) for `text` in a card `width` wide: one to six lines, then the text scrolls.
    /// Compact: one line, no header; the text scrolls within it.
    static func height(_ text: String, width: CGFloat, compact: Bool = false) -> CGFloat {
        // Laid out the way the card's text view lays it out, so the card ends where its text does.
        let layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: max(20, width - 2 * pad), height: .greatestFiniteMagnitude))
        let storage = NSTextStorage(string: text.isEmpty ? " " : text, attributes: [.font: font])
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let line = ceil(layout.defaultLineHeight(for: font))
        if compact { return 2 * margin + pad + line }
        let measured = ceil(layout.usedRect(for: container).height)
        return 2 * margin + 2 * pad + header + min(max(measured, line), maxLines * line)
    }

    private(set) var line: PresenterNotes.CardLine?
    private(set) weak var buffer: Buffer?
    var added: Replacement?
    var onCommit: ((PresenterNoteCard, String) -> Void)?
    var onEndEditing: (() -> Void)?
    var onResize: (() -> Void)?

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: String(localized: "Presenter Note"))
    private let scroll = NSScrollView()
    private let textView = NoteCardTextView(usingTextLayoutManager: true)
    /// The card's own: typing in it is undone here, not in the file (its commit is the file's one undo step).
    private let undo = UndoManager()
    private var shownText = ""

    var text: String { textView.string }
    var isEditing: Bool { window?.firstResponder === textView }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.zPosition = 1000.5   // above the decorations, under the inline diff
        icon.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 11, weight: .medium)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .secondaryLabelColor
        textView.delegate = self
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.setAccessibilityLabel(String(localized: "Presenter Note"))
        textView.onCommit = { [weak self] in self?.onEndEditing?() }
        textView.onResign = { [weak self] in
            guard let self else { return }
            onCommit?(self, textView.string)
            shownText = textView.string
            undo.removeAllActions()
        }
        textView.onCancel = { [weak self] in
            guard let self else { return }
            textView.string = shownText
            onEndEditing?()
        }
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        for v in [icon, title, scroll] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ line: PresenterNotes.CardLine, of buffer: Buffer?, readOnly: Bool) {
        self.line = line
        self.buffer = buffer
        textView.isEditable = !readOnly
        textView.font = Self.font
        textView.textColor = Highlighter.style.colors.text
        textView.insertionPointColor = Highlighter.style.colors.cursor
        guard !isEditing, shownText != line.text || textView.string != line.text else { return }
        shownText = line.text
        textView.string = line.text
        undo.removeAllActions()
    }

    func focus() { window?.makeFirstResponder(textView) }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let p = Self.pad, w = bounds.width
        if NoteDisplay.current == .compact {
            // One row: the symbol, then the text, without the title.
            let row = bounds.height - p
            title.isHidden = true
            icon.frame = NSRect(x: p + 2, y: (bounds.height - 14) / 2, width: 14, height: 14)
            scroll.frame = NSRect(x: icon.frame.maxX + 6, y: p / 2, width: max(0, w - icon.frame.maxX - 6 - p), height: max(0, row))
        } else {
            title.isHidden = false
            icon.frame = NSRect(x: p + 2, y: p, width: 14, height: 14)
            title.sizeToFit()
            title.frame.origin = NSPoint(x: icon.frame.maxX + 4, y: p + (14 - title.frame.height) / 2)
            scroll.frame = NSRect(x: p, y: p + Self.header, width: w - 2 * p, height: max(0, bounds.height - 2 * p - Self.header))
        }
        textView.frame.size.width = scroll.contentSize.width
        textView.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    override func draw(_ dirty: NSRect) { Self.paint(NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)) }

    /// The sticky-note look of a card and a pill: opaque, so the code under it does not show.
    static func paint(_ shape: NSBezierPath) {
        Highlighter.style.colors.background.setFill()
        shape.fill()
        NSColor.systemYellow.withAlphaComponent(0.16).setFill()
        shape.fill()
        NSColor.systemYellow.withAlphaComponent(0.45).setStroke()
        shape.stroke()
    }

    /// A click on the box, not on its text, edits the note rather than reaching the code under it.
    override func mouseDown(with event: NSEvent) { if textView.isEditable { focus() } }


    func undoManager(for view: NSTextView) -> UndoManager? { undo }

    func textDidChange(_ notification: Notification) { onResize?() }
}

/// The card's text: ⌘↩ ends the edit, Escape takes it back, and an empty note shows a placeholder.
final class NoteCardTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    /// Focus left: also without an edit, so a fresh empty note is cleaned up.
    var onResign: (() -> Void)?

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { onResign?() }
        return ok
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, event.keyCode == 36, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            onCommit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func draw(_ dirty: NSRect) {
        super.draw(dirty)
        guard string.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: NSColor.placeholderTextColor]
        (String(localized: "Note for this slide") as NSString).draw(at: NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 5), y: textContainerOrigin.y), withAttributes: attrs)
    }
}

/// The popover a note pill opens: the note's text, written back when the popover closes. ⌘↩ closes it, Escape closes it
/// without the edit.
@MainActor final class NotePillEditor: NSViewController, NSPopoverDelegate, NSTextViewDelegate {
    var onClose: ((String) -> Void)?
    private let textView = NoteCardTextView(usingTextLayoutManager: true)
    private let original: String
    private weak var popover: NSPopover?
    /// Its own, like a card's: the commit is the file's one undo step.
    private let undo = UndoManager()

    init(text: String, editable: Bool, popover: NSPopover) {
        original = text
        self.popover = popover
        super.init(nibName: nil, bundle: nil)
        textView.string = text
        textView.isEditable = editable
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        textView.frame = NSRect(origin: .zero, size: scroll.contentSize)
        textView.delegate = self
        textView.font = .systemFont(ofSize: Highlighter.fontSize)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.setAccessibilityLabel(String(localized: "Presenter Note"))
        textView.onCommit = { [weak self] in self?.popover?.performClose(nil) }
        textView.onCancel = { [weak self] in
            guard let self else { return }
            textView.string = original
            popover?.performClose(nil)
        }
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        view = scroll
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    func popoverDidClose(_ notification: Notification) { onClose?(textView.string) }

    func undoManager(for view: NSTextView) -> UndoManager? { undo }
}

extension DecorationView {
    /// A sticky-note pill over each shown note call that sits on one visual line, with the note's text cut to the call's
    /// width. Not while a selection end is inside the call, so find and jumps show the code they land in.
    func drawNotePills(tv: NSTextView, tlm: NSTextLayoutManager, tcs: NSTextContentStorage, viewport: NSTextRange, sel: NSRange) {
        guard let pills = notePills?(), !pills.isEmpty else { return }
        let lo = tcs.offset(of: viewport.location), hi = tcs.offset(of: viewport.endLocation)
        let font = NSFont.systemFont(ofSize: Highlighter.fontSize - 2)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let config = NSImage.SymbolConfiguration(pointSize: Highlighter.fontSize - 3, weight: .medium).applying(.init(paletteColors: [.secondaryLabelColor]))
        let icon = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        for pill in pills where pill.call.location >= lo && pill.call.location < hi && (shownLine?(pill.lineStart) ?? pill.lineStart) == pill.lineStart {
            let inside = { (p: Int) in pill.call.location < p && p < NSMaxRange(pill.call) }
            guard !inside(sel.location), !inside(NSMaxRange(sel)), let range = tcs.textRange(for: pill.call) else { continue }
            var rects: [CGRect] = []
            tlm.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
                rects.append(frame)
                return true
            }
            guard let first = rects.first, rects.allSatisfy({ abs($0.minY - first.minY) < 0.5 }) else { continue }
            let hit = rects.reduce(first) { $0.union($1) }.offsetBy(dx: tv.textContainerOrigin.x, dy: tv.textContainerOrigin.y)
            guard hit.width > 1, hit.height > 1 else { continue }
            // The editor's background over the whole call first, so no edge of a glyph shows beside the rounded pill.
            Highlighter.style.colors.background.setFill()
            hit.fill()
            if NoteDisplay.current == .hidden {
                icon?.draw(in: NSRect(x: hit.minX + 2, y: hit.midY - (icon?.size.height ?? 0) / 2, width: icon?.size.width ?? 0, height: icon?.size.height ?? 0))
                continue
            }
            let box = hit.insetBy(dx: 1, dy: 1)
            PresenterNoteCard.paint(NSBezierPath(roundedRect: box, xRadius: min(5, box.height / 2), yRadius: min(5, box.height / 2)))
            var x = box.minX + 5
            if let icon {
                icon.draw(in: NSRect(x: x, y: box.midY - icon.size.height / 2, width: icon.size.width, height: icon.size.height))
                x += icon.size.width + 4
            }
            let empty = pill.text.isEmpty
            let label = (empty ? String(localized: "Note for this slide") : pill.text.replacingOccurrences(of: "\n", with: " ")) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style,
                                                        .foregroundColor: empty ? NSColor.placeholderTextColor : Highlighter.style.colors.text]
            let height = label.size(withAttributes: attrs).height
            label.draw(in: NSRect(x: x, y: box.midY - height / 2, width: max(0, box.maxX - 5 - x), height: height), withAttributes: attrs)
            notePillHits.append((hit, pill))
        }
    }
}

extension LineNumberRuler {
    /// A note symbol left of a presenter note's line number, clear of the git bar at the edge: the note while the card
    /// shows, the code brackets while the line shows its code. A click on the row toggles (see `mouseDown`).
    func drawNoteMark(at start: Int, y: CGFloat, height: CGFloat) {
        guard let card = editor?.noteCards.mark(at: start) else { return }
        let color = card ? NSColor.systemYellow.blended(withFraction: 0.35, of: .systemOrange) ?? .systemYellow : Highlighter.style.colors.ruler
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium).applying(.init(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: card ? "note.text" : "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        img.draw(in: NSRect(x: 5, y: y + max(height, img.size.height) / 2 - img.size.height / 2, width: img.size.width, height: img.size.height))
    }
}
