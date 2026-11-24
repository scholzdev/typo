import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// Routes the system completion command (Esc, Option-Esc, F5) to the typst-ide popup instead of the
/// dictionary word list.
final class EditorTextView: NSTextView {
    var onComplete: (@MainActor () -> Void)?
    override func complete(_ sender: Any?) { onComplete?() }

    var onMouseMoved: (@MainActor (NSPoint) -> Void)?
    var onMouseLeft: (@MainActor () -> Void)?
    var onKeyDown: (@MainActor () -> Void)?
    var onMouseDown: (@MainActor () -> Void)?
    /// ⌘-click at a character index; true when it was handled (a label or reference), so the click is not a selection.
    var onCommandClick: (@MainActor (Int) -> Bool)?
    var onFocusChange: (@MainActor () -> Void)?
    /// A selection change while the mouse is still down, which AppKit does not report to the delegate.
    var onSelectionTracking: (@MainActor () -> Void)?
    var tableAtCaret: (@MainActor () -> Bool)?
    var onEditTable: (@MainActor () -> Void)?
    /// Whether the line at an offset is bookmarked (nil: no bookmarks here), and the context menu's toggle.
    var bookmarkedAt: (@MainActor (Int) -> Bool?)?
    var onToggleBookmark: (@MainActor (Int) -> Void)?
    var multi = MultiCursorState()      // multiple cursors: see MultiCursor.swift
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = hoverArea { removeTrackingArea(a) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(a)
        hoverArea = a
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?(convert(event.locationInWindow, from: nil))
        updateCommandHover(event.modifierFlags, at: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseLeft?()
        setCommandHover(nil)
    }

    // MARK: ⌘- and ⌥-hover (as in Xcode): with ⌘ a jumpable name under the pointer is link-colored and underlined and
    // the pointer a hand; with ⌥ it is dotted-underlined and the pointer a question mark (⌥-click shows Quick Help).

    /// The jumpable name at a character index, if any.
    var navigableRange: (@MainActor (Int) -> NSRange?)?
    /// Puts back the diagnostic underlines inside a range the hover underline covered.
    var restoreUnderlines: (@MainActor (NSRange) -> Void)?
    /// ⌥-click on a name: Quick Help at that character index.
    var onOptionClick: (@MainActor (Int) -> Void)?
    private enum HoverModifier { case command, option }
    /// What ⌘-click and ⌥-click do (Navigation settings); the hover feedback follows.
    var clickActions = (command: NavigationSettings.standard.commandClick, option: NavigationSettings.standard.optionClick) {
        didSet { if clickActions != oldValue { setCommandHover(nil) } }
    }
    private func action(for modifier: HoverModifier) -> NavigationSettings.ClickAction { modifier == .command ? clickActions.command : clickActions.option }
    private var commandHover: (range: NSRange, modifier: HoverModifier)?

    /// The system's help pointer (arrow with question mark) that Xcode shows for Quick Help. AppKit has no public
    /// accessor, so it is loaded from HIServices' cursor resources with the shadow its info.plist describes; the arrow otherwise.
    private static let helpCursor: NSCursor = {
        let dir = "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors/help"
        guard let pdf = NSImage(contentsOfFile: dir + "/cursor.pdf") else { return .arrow }
        let info = NSDictionary(contentsOfFile: dir + "/info.plist")
        let hot = NSPoint(x: (info?["hotx"] as? Double) ?? 9, y: (info?["hoty"] as? Double) ?? 9)
        let pad: CGFloat = 3                                  // room for the shadow
        let size = NSSize(width: pdf.size.width + 2 * pad, height: pdf.size.height + 2 * pad)
        let image = NSImage(size: size, flipped: false) { _ in
            let shadow = NSShadow()
            shadow.shadowBlurRadius = CGFloat((info?["blur"] as? Double) ?? 1.8)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
            shadow.set()
            pdf.draw(in: NSRect(x: pad, y: pad, width: pdf.size.width, height: pdf.size.height))
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: hot.x + pad, y: hot.y + pad))
    }()

    private func cursor(for modifier: HoverModifier) -> NSCursor { action(for: modifier) == .jump ? .pointingHand : Self.helpCursor }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateCommandHover(event.modifierFlags, at: window?.mouseLocationOutsideOfEventStream)
    }

    override func cursorUpdate(with event: NSEvent) {
        if let h = commandHover { cursor(for: h.modifier).set() } else { super.cursorUpdate(with: event) }
    }

    private func updateCommandHover(_ flags: NSEvent.ModifierFlags, at windowPoint: NSPoint?) {
        let mods = flags.intersection(.deviceIndependentFlagsMask)
        let modifier: HoverModifier? = mods == .command ? .command : mods == .option ? .option : nil
        guard let modifier, action(for: modifier) != .none, let windowPoint, let navigableRange else { return setCommandHover(nil) }
        let p = convert(windowPoint, from: nil)
        guard visibleRect.contains(p) else { return setCommandHover(nil) }
        let i = characterIndexForInsertion(at: p)
        // The index of the nearest insertion point; only a name whose glyphs are under the pointer counts.
        guard let r = navigableRange(i), viewRect(forCharacterRange: r).insetBy(dx: -1, dy: -1).contains(p) else { return setCommandHover(nil) }
        setCommandHover((r, modifier))
    }

    private func setCommandHover(_ hover: (range: NSRange, modifier: HoverModifier)?) {
        if hover?.range == commandHover?.range, hover?.modifier == commandHover?.modifier {
            if let hover { cursor(for: hover.modifier).set() }
            return
        }
        if let old = commandHover?.range, let tlm = textLayoutManager, let r = textContentStorage?.textRange(for: old) {
            tlm.removeRenderingAttribute(.foregroundColor, for: r)
            tlm.removeRenderingAttribute(.underlineStyle, for: r)
            tlm.removeRenderingAttribute(.underlineColor, for: r)
            restoreUnderlines?(old)
        }
        commandHover = hover
        if let hover, let tlm = textLayoutManager, let r = textContentStorage?.textRange(for: hover.range) {
            let jumps = action(for: hover.modifier) == .jump
            let style: NSUnderlineStyle = jumps ? .single : [.single, .patternDot]
            var attrs: [NSAttributedString.Key: Any] = [.underlineStyle: style.rawValue, .underlineColor: NSColor.linkColor]
            if jumps { attrs[.foregroundColor] = NSColor.linkColor }
            tlm.setRenderingAttributes(attrs, for: r)
            cursor(for: hover.modifier).set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    @objc private func editTable(_ sender: Any?) { onEditTable?() }
    private var bookmarkClick = 0
    @objc private func toggleBookmark(_ sender: Any?) { onToggleBookmark?(bookmarkClick) }
    /// The context menu's Jump to Definition and Find References; the caret is already at the clicked name.
    var onJumpToDefinition: (@MainActor () -> Void)?
    var onFindReferences: (@MainActor () -> Void)?
    /// The context menu's "Quick Fixes…" for a clicked diagnostic; `fixableAt` says whether the offset is inside one.
    var onQuickFixes: (@MainActor (Int, NSPoint) -> Void)?
    var fixableAt: (@MainActor (Int) -> Bool)?
    /// Whether the selection has refactorings, which the same menu item offers.
    var hasRefactorings: (@MainActor () -> Bool)?
    private var quickFixClick: (offset: Int, point: NSPoint)?
    @objc private func quickFixes(_ sender: Any?) { if let c = quickFixClick { onQuickFixes?(c.offset, c.point) } }
    @objc private func jumpToDefinition(_ sender: Any?) { onJumpToDefinition?() }
    @objc private func findReferences(_ sender: Any?) { onFindReferences?() }
    var onExplainSelection: (@MainActor () -> Void)?
    var canAddPresenterNote: (@MainActor () -> Bool)?
    var onAddPresenterNote: (@MainActor () -> Void)?
    @objc private func addPresenterNote(_ sender: Any?) { onAddPresenterNote?() }
    @objc private func explainSelection(_ sender: Any?) { onExplainSelection?() }

    /// A right-click puts the caret under the pointer (unless it is inside the selection), so "Edit Table…"
    /// refers to the table that was clicked.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        let i = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if !NSLocationInRange(i, selectedRange()) { setSelectedRange(NSRange(location: i, length: 0)) }
        if navigableRange?(i) != nil {
            let items = [(String(localized: "Jump to Definition"), "arrow.right.circle", #selector(jumpToDefinition(_:))),
                         (String(localized: "Find References"), "list.bullet.rectangle", #selector(findReferences(_:)))]
            for (n, (title, symbol, action)) in items.enumerated() {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                menu?.insertItem(item, at: n)
            }
            menu?.insertItem(.separator(), at: items.count)
        }
        if fixableAt?(i) == true || hasRefactorings?() == true {
            quickFixClick = (i, convert(event.locationInWindow, from: nil))
            let item = NSMenuItem(title: String(localized: "Quick Fixes…"), action: #selector(quickFixes(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: nil)
            menu?.insertItem(item, at: 0)
            menu?.insertItem(.separator(), at: 1)
        }
        if selectedRange().length > 0, onExplainSelection != nil {
            let item = NSMenuItem(title: String(localized: "Explain with AI"), action: #selector(explainSelection(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            menu?.insertItem(item, at: 0)
            menu?.insertItem(.separator(), at: 1)
        }
        if tableAtCaret?() == true {
            let item = NSMenuItem(title: String(localized: "Edit Table…"), action: #selector(editTable(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "tablecells.badge.ellipsis", accessibilityDescription: nil)
            menu?.insertItem(item, at: 0)
            menu?.insertItem(.separator(), at: 1)
        }
        if let marked = bookmarkedAt?(i) {
            bookmarkClick = i
            let item = NSMenuItem(title: marked ? String(localized: "Remove Bookmark") : String(localized: "Add Bookmark"), action: #selector(toggleBookmark(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: marked ? "bookmark.slash" : "bookmark", accessibilityDescription: nil)
            menu?.insertItem(item, at: 0)
            menu?.insertItem(.separator(), at: 1)
        }
        if canAddPresenterNote?() == true {
            let item = NSMenuItem(title: String(localized: "Add Presenter Note"), action: #selector(addPresenterNote(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
            menu?.insertItem(item, at: 0)
            menu?.insertItem(.separator(), at: 1)
        }
        return menu
    }

    private func perform(_ action: NavigationSettings.ClickAction, at i: Int) -> Bool {
        switch action {
        case .jump: return onCommandClick?(i) == true
        case .quickHelp:
            guard let onOptionClick, navigableRange?(i) != nil else { return false }
            onOptionClick(i)
            return true
        case .none: return false
        }
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        setCommandHover(nil)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let p = convert(event.locationInWindow, from: nil)
        var i = characterIndexForInsertion(at: p)
        // The insertion point may sit before the name (between `#` and `text`), where the engine sees the `#`:
        // ask about the name's middle instead.
        if !mods.isDisjoint(with: [.command, .option]), let r = navigableRange?(i), viewRect(forCharacterRange: r).insetBy(dx: -1, dy: -1).contains(p) {
            i = r.location + r.length / 2
        }
        // ⌥-click elsewhere keeps NSTextView's rectangular selection; "Does Nothing" is a normal click.
        if mods.contains(.command), perform(clickActions.command, at: i) { return }
        if mods == .option, perform(clickActions.option, at: i) { return }
        if multiMouseDown(event) { return }
        super.mouseDown(with: event)
    }

    // A click or drag sets the selection with stillSelecting on mouse-down and tells the delegate only on
    // mouse-up, so without this the drawn caret and selection trail the press by however long it lasts.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if stillSelecting { onSelectionTracking?() }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        onFocusChange?()
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        onFocusChange?()
        return ok
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if !multiInsert(string, replacementRange) { super.insertText(string, replacementRange: replacementRange) }
    }
    override func copy(_ sender: Any?) { if !multiCopy() { super.copy(sender) } }
    override func cut(_ sender: Any?) { if !multiCut() { super.cut(sender) } }
    override func selectAll(_ sender: Any?) { clearExtras(); super.selectAll(sender) }
    /// Vim mode (App/VimMode.swift): takes the key first while the setting is on.
    var vim: VimController?

    override func keyDown(with event: NSEvent) {
        onKeyDown?()
        setCommandHover(nil)                       // the text may change under the underlined name
        if vim?.handle(event, in: self) == true { return }
        super.keyDown(with: event)
    }
}

struct EditorView: NSViewRepresentable {
    @ObservedObject private var settingsObserver = EditorSettingsObserver.shared
    let project: Project
    let buffer: Buffer
    let tables: TableEditing
    let actions: EditorActions
    let marks: [Diagnostic]
    let revealToken: Int   // changes when a diagnostic click asks for a selection
    var layout: EditorLayout?
    var focusMode = false
    var readOnly = false
    var isPrimary = true   // the split editor's second pane is not: jumps go to the first
    @AppStorage(SettingsKey.animatedCaret) private var animatedCaret = true
    @AppStorage(SettingsKey.bracketMatch) private var bracketMatch = true
    @AppStorage(SettingsKey.rainbowBrackets) private var rainbowBrackets = true
    @AppStorage(SettingsKey.colorSwatches) private var colorSwatches = true
    @AppStorage(SettingsKey.inlayHints) private var inlayHints = false
    @AppStorage(SettingsKey.stickyScroll) private var stickyScroll = true
    @AppStorage(SettingsKey.editorFontSize) private var fontSize = EditorStyle.defaultSize
    @AppStorage(SettingsKey.editorTheme) private var theme = "default"
    @AppStorage(SettingsKey.typewriter) private var typewriter = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = AnchoredScrollView()
        let tv = EditorTextView(usingTextLayoutManager: true)
        let c = context.coordinator
        tv.onComplete = { [weak c] in c?.request(explicit: true) }
        tv.onMouseMoved = { [weak c] in c?.mouseMoved(to: $0) }
        tv.onMouseLeft = { [weak c] in c?.mouseLeft() }
        tv.onKeyDown = { [weak c] in c?.hideHover() }
        tv.onMouseDown = { [weak c] in c?.hideHover() }
        tv.onCommandClick = { [weak c, project] i in
            guard let b = c?.buffer, References.isNavigable(b, at: i) else { return false }
            Task { await References.jump(project, buffer: b, at: i) }
            return true
        }
        tv.navigableRange = { [weak c] i in c?.buffer.flatMap { References.navigableRange($0, at: i) } }
        tv.restoreUnderlines = { [weak c, weak tv] r in if let tv { c?.restoreMarks(in: r, of: tv) } }
        tv.onJumpToDefinition = { [weak c, weak tv, project] in
            guard let b = c?.buffer, let i = tv?.selectedRange().location else { return }
            Task { await References.jump(project, buffer: b, at: i) }
        }
        tv.fixableAt = { [weak c, weak tv] i in
            guard let c, let tv, let file = c.buffer?.path else { return false }
            return QuickFixMenu.fixableDiagnostics(project: project, file: file, at: i, text: tv.string as NSString).isEmpty == false
        }
        tv.hasRefactorings = { [weak c, weak tv] in
            guard let tv else { return false }
            return c?.buffer?.refactorings(selection: tv.selectedRange()).isEmpty == false
        }
        tv.onQuickFixes = { [weak c, weak tv] i, point in
            guard let c, let tv else { return }
            c.showQuickFixes(at: i, from: tv, point: point)
        }
        tv.onFindReferences = { [project] in Task { await References.findReferences(project) } }
        tv.onOptionClick = { [weak c, project] i in
            guard let b = c?.buffer else { return }
            Task { await References.quickHelp(project, buffer: b, at: i) }
        }
        tv.onFocusChange = { [weak c] in c?.decor?.refresh(); c?.focusChanged() }
        tv.onSelectionTracking = { [weak c] in c?.decor?.refresh() }
        tv.tableAtCaret = { [weak c] in c?.tableAtCaret() != nil }
        tv.onEditTable = { [weak c] in c?.tables?.beginEdit() }
        tv.onExplainSelection = { [actions] in actions.explainSelection?() }
        tv.canAddPresenterNote = { [weak c] in c?.buffer?.isTypst == true && c?.readOnly == false }
        tv.onAddPresenterNote = { [weak c] in c?.addPresenterNote() }
        tv.bookmarkedAt = { [weak c] i in c?.isBookmarked(at: i) }
        tv.onToggleBookmark = { [weak c] i in c?.toggleBookmark(at: i) }
        tv.multi.buffer = { [weak c] in c?.readOnly == true ? nil : c?.buffer }
        tv.multi.onChange = { [weak c] in c?.decor?.refresh() }
        tv.observeStorageForMultiCursor()
        c.attach(tv, scroll: scroll)
        tv.vim = VimController(textView: tv, coordinator: c)
        scroll.editor = c
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 4, height: 8)
        tv.isRichText = false
        tv.usesFontPanel = false                 // bold, italic and underline write Typst markup, never font traits
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = false
        // Typst markup uses " ' - -- ... literally; substitutions would corrupt it.
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.delegate = context.coordinator
        // The decoration layer draws the selection (rounded); the native square one is made invisible.
        tv.selectedTextAttributes = [.backgroundColor: NSColor.clear]

        scroll.hasVerticalScroller = true
        scroll.documentView = tv
        scroll.verticalRulerView = LineNumberRuler(scrollView: scroll, textView: tv, editor: c)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        // Views do not clip by default (macOS 14+): the gutter fill used to run up through the tab bar above.
        scroll.clipsToBounds = true
        scroll.verticalRulerView?.clipsToBounds = true
        let decor = DecorationView(textView: tv)
        decor.onPillClick = { [weak c] in c?.showHover(forDiagnosticAt: $0) }
        decor.onFixablePillClick = { [weak c, weak decor] range, rect in
            guard let c, let decor else { return }
            c.showQuickFixes(at: range.location, from: decor, point: NSPoint(x: rect.minX, y: rect.maxY + 2), details: range)
        }
        decor.colorLiterals = { [weak c] in c?.buffer?.colorLiterals ?? [] }
        decor.onSwatchClick = { [weak c] in c?.pickColor($0, anchor: $1) }
        decor.inlayHints = { [weak c] in c?.buffer?.inlayHints ?? [] }
        tv.addSubview(decor)
        c.decor = decor
        let diff = InlineDiffOverlay(textView: tv)
        tv.addSubview(diff)
        c.diffOverlay = diff
        let sticky = StickyHeadingsView(scrollView: scroll, textView: tv, editor: c)
        scroll.addSubview(sticky, positioned: .above, relativeTo: scroll.contentView)   // under the scroller
        c.sticky = sticky
        c.setUpFolding(tv, decor: decor)
        MinimapView.attach(to: scroll, textView: tv, editor: c)   // after setUpFolding: it chains the folds' onChange
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        _ = settingsObserver.revision   // any defaults change re-runs this
        let tv = scroll.documentView as! NSTextView
        let c = context.coordinator
        c.buffer = buffer
        c.project = project
        c.tables = tables
        c.actions = actions
        c.layout = layout
        c.isPrimary = isPrimary
        c.readOnly = readOnly
        tv.isEditable = !readOnly
        c.claimEditorIfUnset()
        c.applyStyle(size: fontSize, theme: theme, to: tv, in: scroll)
        c.applyFocus(focusMode, typewriter: typewriter, to: tv, in: scroll)
        if c.folds.buffer !== buffer { c.foldAnimator.finish() }   // its offsets belong to the old file
        c.folds.buffer = buffer
        c.gitGutter.ruler = scroll.verticalRulerView as? LineNumberRuler
        c.gitGutter.show(buffer, in: project)
        if tv.textContentStorage?.textStorage !== buffer.storage {
            c.dismiss()
            c.hideSignatureHelp()
            c.swapping = true                              // the swap and the restore are not the user moving the caret
            tv.textContentStorage?.adopt(buffer.storage)
            tv.typingAttributes = Highlighter.base   // the buffer's own attributes carry the font and colors
            c.appliedMarks = nil
            // A swapped storage keeps the old selection, which can lie beyond the new text.
            let restored = c.savedSelection(of: buffer)
            tv.setSelectedRange(restored)
            tv.scrollRangeToVisible(restored)
            c.swapping = false
            c.refreshCaretStatus()
            c.folds.adopted()                              // a restored caret that a fold now hides moves out
            c.refreshRainbow()
            c.focusChanged()
            scroll.verticalRulerView?.needsDisplay = true
        }
        c.apply(marks, to: tv)
        c.setAnimatedCaret(animatedCaret, in: tv)
        c.setMatchesBrackets(bracketMatch)
        c.setRainbowBrackets(rainbowBrackets)
        buffer.colorSwatches = colorSwatches
        project.inlayHintsEnabled = inlayHints
        c.decor?.needsDisplay = true
        c.diffOverlay?.buffer = buffer
        c.sticky?.enabled = stickyScroll
        c.sticky?.refresh()
        c.sticky?.needsDisplay = true                      // a theme or font change repaints the pinned headings
        if isPrimary, let range = buffer.takePendingSelection() {
            let r = range.clamped(within: buffer.storage.length)
            c.revealFolds(r)                               // a jump into a folded section opens it first
            c.selectProgrammatically(r, in: tv)
            tv.window?.makeFirstResponder(tv)
            if buffer.takePendingFlash() { tv.showFindIndicator(for: tv.selectionRange(forProposedRange: r, granularity: .selectByWord)) }
        }
        c.refreshCaretInTable()
        c.applyAppearanceSettings(tv, scroll)
        c.applyDisplaySettings(tv, scroll)
        c.applyIndentationSettings(tv)
        c.applyNavigationSettings(tv)
        c.updateMinimap(scroll)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var buffer: Buffer? { didSet { if buffer !== oldValue { endSnippetSession() } } }
        var project: Project?
        var readOnly = false
        var tables: TableEditing?
        var actions: EditorActions?
        var appliedMarks: [Mark]?
        var decor: DecorationView?
        var diffOverlay: InlineDiffOverlay?
        var sticky: StickyHeadingsView?
        var matchesBrackets = true
        var rainbowBrackets = true
        var swatchRange: NSRange?                       // the literal the color popover is editing
        weak var layout: EditorLayout?
        var isPrimary = true
        let folds = FoldController()
        let foldAnimator = FoldAnimator()
        let gitGutter = GitGutter()
        private var hoverPinned = false                 // a pill click opened the card: it stays until a key, click or scroll

        weak var textView: NSTextView?
        private let popup = CompletionPopup()
        var completionVisible: Bool { popup.isVisible }
        private let hoverPopup = HoverPopup()
        let signaturePopup = SignatureHelpPopup()
        var signatureRequestID = 0
        private var hoverRange: NSRange?                // the range the visible hover card describes
        private var hoverTask: Task<Void, Never>?       // the dwell timer and the request it starts
        private var list: CompletionList?
        private var requestID = 0
        private var typed: Character?                   // the single character shouldChange saw, until textDidChange
        var accepting = false
        var snippetSession: SnippetSession? {           // the tab stops of the last inserted snippet, while they are being filled in
            didSet { if oldValue != nil, snippetSession == nil { snippetSessionEnded() } }
        }
        var display = DisplayState()
        var pendingEdit: (range: NSRange, length: Int)? // the user's edit between shouldChange and textDidChange
        var swapping = false                            // a file switch is in progress: do not record its selection
        var programmatic = false                        // the app, not the user, is moving the selection

        func attach(_ tv: NSTextView, scroll: NSScrollView) {
            textView = tv
            popup.onPick = { [weak self] in self?.accept($0) }
            popup.labelEquation = { [weak self] name in
                guard let project = self?.project, let scale = tv.window?.backingScaleFactor,
                      let e = await project.labelEquation(name, pixelsPerPoint: Float(2 * scale)) else { return nil }
                // Like the hover card: the page-white render on a rounded tile, at most as tall as the detail area.
                let fit = min(1.4, 30 / e.size.height)
                let size = NSSize(width: (e.size.width * fit).rounded(), height: (e.size.height * fit).rounded())
                return NSImage(size: size, flipped: false) { rect in
                    let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
                    NSGraphicsContext.saveGraphicsState()
                    shape.addClip()
                    NSImage(cgImage: e.image, size: size).draw(in: rect)
                    NSGraphicsContext.restoreGraphicsState()
                    return true
                }
            }
            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(scrollStarted), name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            nc.addObserver(self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification, object: nil)
            nc.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didResignKeyNotification, object: nil)
            nc.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didBecomeKeyNotification, object: nil)
            nc.addObserver(self, selector: #selector(refreshDecor), name: NSView.frameDidChangeNotification, object: tv)
            nc.addObserver(self, selector: #selector(storageProcessed), name: NSTextStorage.didProcessEditingNotification, object: nil)
        }

        /// New inlay hints change the kerns without an edit, so the decoration layer redraws on any storage change.
        @objc private func storageProcessed(_ n: Notification) {
            guard let s = n.object as? NSTextStorage, s === textView?.textContentStorage?.textStorage else { return }
            decor?.needsDisplay = true
            // A programmatic edit moves the offsets a fold's motion relies on; layout waits until the edit is processed.
            if s.editedMask.contains(.editedCharacters), foldAnimator.state != nil { DispatchQueue.main.async { self.foldAnimator.finish() } }
        }

        @objc private func windowKeyChanged(_ n: Notification) {
            if (n.object as? NSWindow) === textView?.window { decor?.refresh() }
        }
        @objc private func refreshDecor() { decor?.refresh(); fitColumn() }

        func setAnimatedCaret(_ on: Bool, in tv: NSTextView) {
            // The system insertion point is hidden by its public color; with the setting off it is restored.
            tv.insertionPointColor = on ? .clear : .textInsertionPointColor
            decor?.animatedCaret = on
        }

        @objc private func scrollStarted() { dismiss(); hideSignatureHelp(); foldAnimator.finish() }
        @objc private func windowResigned(_ n: Notification) {
            if (n.object as? NSWindow) === textView?.window { dismiss(); hideSignatureHelp() }
        }

        // MARK: Hover

        private static let hoverDwell: Duration = .milliseconds(100)

        func hideHover() {
            hoverPinned = false
            hoverTask?.cancel()
            hoverTask = nil
            hoverRange = nil
            if References.hoverTarget?.buffer === buffer { References.hoverTarget = nil }
            hoverPopup.hide()
        }

        /// A pill click: the card for the diagnostic at `range`, held in place.
        func showHover(forDiagnosticAt range: NSRange) {
            guard let tv = textView, let project, let file = buffer?.path else { return }
            hideHover()
            let storage = buffer?.storage
            let index = min(range.location, max(tv.string.utf16.count - 1, 0))
            Task { [weak self] in
                guard let info = await project.hover(in: file, at: index), let self, self.buffer?.path == file, self.buffer?.storage === storage,
                      info.range.location + min(info.range.length, 1) <= tv.string.utf16.count else { return }
                self.hoverRange = info.range
                self.hoverPinned = true
                self.hoverPopup.show(info, in: tv)
            }
        }

        func mouseMoved(to point: NSPoint) {
            guard !hoverPinned else { return }
            if hoverPopup.isVisible, let range = hoverRange, let tv = textView, keepsHover(range, at: point, in: tv) { return }
            hideHover()
            guard !popup.isVisible else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: Self.hoverDwell)
                guard !Task.isCancelled else { return }
                await self?.showHover(at: point)
            }
        }

        func mouseLeft() {
            guard !hoverPinned else { return }
            // Moving onto the card is not leaving: it can be scrolled and its links clicked.
            if hoverPopup.isVisible, hoverPopup.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) { return }
            hideHover()
        }

        /// The character whose glyph is under `point`; nil over line ends, the margin and empty space.
        private func glyphIndex(at point: NSPoint, in tv: NSTextView) -> Int? {
            guard tv.window != nil else { return nil }
            let text = tv.string as NSString
            let near = tv.characterIndexForInsertion(at: point)
            for i in [near, near - 1] where i >= 0 && i < text.length {
                let r = text.rangeOfComposedCharacterSequence(at: i)
                if ["\n", "\r"].contains(text.substring(with: r)) { continue }
                if tv.viewRect(forCharacterRange: r).contains(point) { return r.location }
            }
            return nil
        }

        /// The card stays while the mouse is over the hovered range, or in the gap towards the card and on it.
        private func keepsHover(_ range: NSRange, at point: NSPoint, in tv: NSTextView) -> Bool {
            if let i = glyphIndex(at: point, in: tv), NSLocationInRange(i, range) { return true }
            guard let window = tv.window else { return false }
            let gap = hoverPopup.frame.union(tv.firstRect(forCharacterRange: range, actualRange: nil)).insetBy(dx: -6, dy: -6)
            return gap.contains(window.convertPoint(toScreen: tv.convert(point, to: nil)))
        }

        private func showHover(at point: NSPoint) async {
            guard let tv = textView, let project, let file = buffer?.path, buffer?.isTypst == true, let window = tv.window, window.isKeyWindow,
                  NSEvent.pressedMouseButtons == 0, !tv.hasMarkedText(), !popup.isVisible,
                  let index = glyphIndex(at: point, in: tv) else { return }
            let storage = buffer?.storage
            guard let info = await project.hover(in: file, at: index, pixelsPerPoint: Float(HoverPopup.equationScale * 1.5 * window.backingScaleFactor)), !Task.isCancelled,
                  buffer?.path == file, buffer?.storage === storage, !popup.isVisible, !tv.hasMarkedText(),
                  info.range.location + min(info.range.length, 1) <= tv.string.utf16.count else { return }
            hoverRange = info.range
            // A jumpable name: Jump to Definition follows it while the card is up, and the card names the shortcut.
            let navigable = buffer.flatMap { References.navigableRange($0, at: index) } != nil
            References.hoverTarget = navigable ? buffer.map { ($0, index) } : nil
            let hint = navigable && UserDefaults.standard.object(forKey: SettingsKey.hoverJumpHint) as? Bool ?? true
            hoverPopup.show(info, jumpHint: hint ? JumpShortcut.current?.display : nil, in: tv)
        }

        isolated deinit { NotificationCenter.default.removeObserver(self) }

        private static let triggers = Set("#.@<(,:\"$ ")

        /// Typing never waits: the request runs in a task, and a reply is shown through `live`, which maps
        /// it over whatever was typed meanwhile.
        func request(explicit: Bool) {
            guard let tv = textView, let project, let file = buffer?.path, buffer?.isTypst == true else { return }
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return }
            requestID += 1
            let id = requestID
            Task { [weak self] in
                let result = await project.complete(in: file, at: sel.location, explicit: explicit)
                guard let self, id == self.requestID, self.buffer?.path == file else { return }
                self.list = result
                self.refresh()
            }
        }

        /// Shows the list narrowed to what is typed since it was requested, or hides it.
        private func refresh() {
            guard let tv = textView, let project else { return dismiss() }
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return dismiss() }
            let live = list.flatMap { project.live($0, caret: sel.location) }
            // User snippets whose prefix matches the typed word come first; they show even when the engine has
            // nothing to offer (a plain word in markup).
            let range = live?.range ?? Self.typedWord(before: sel.location, in: tv.string as NSString)
            let word = (tv.string as NSString).substring(with: range)
            let mine = UserSnippetStore.shared.completions(matching: word).map { CompletionItem(kind: .syntax, label: $0.prefix, apply: $0.body, detail: $0.title) }
            guard live != nil || !mine.isEmpty else { return dismiss() }
            popup.show(mine + (live?.items ?? []), range: range, in: tv)
        }

        /// The identifier-like run ending at `caret`: what a snippet prefix is matched against.
        private static func typedWord(before caret: Int, in text: NSString) -> NSRange {
            var start = min(caret, text.length)
            while start > 0, let u = Unicode.Scalar(text.character(at: start - 1)),
                  CharacterSet.alphanumerics.contains(u) || u == "_" || u == "-" { start -= 1 }
            return NSRange(location: start, length: min(caret, text.length) - start)
        }

        func dismiss() {
            hideHover()
            requestID += 1                               // a reply still in flight must not reopen it
            list = nil
            popup.hide()
            project?.endCompletion()
        }

        private func accept(_ item: CompletionItem) {
            guard let tv = textView else { return dismiss() }
            let caret = tv.selectedRange().location
            // Without an engine list the popup held only user snippets, matched against the typed word.
            let range = list.flatMap { project?.live($0, caret: caret)?.range } ?? Self.typedWord(before: caret, in: tv.string as NSString)
            let snippet = Snippet.parse(item.apply ?? item.label).indentedKeepingGroups(by: Indent.lineIndent(in: tv.string, before: range.location))
            replace(range, with: snippet.text, selecting: snippet.selection(insertedAt: range.location), session: (snippet, range.location))
            completionInserted(at: range.location, end: range.location + (snippet.text as NSString).length)
            if CompletionPreferences.signaturesWhileTyping { requestSignatureHelp() }   // an accepted `text(` or `size: ` lands in an argument list
        }

        func selectProgrammatically(_ range: NSRange, in tv: NSTextView, scroll: Bool = true) {
            programmatic = true
            tv.setSelectedRange(range)
            programmatic = false
            if scroll { tv.scrollRangeToVisible(range) }
        }

        func textView(_ view: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            if readOnly { return false }
            foldAnimator.finish()                           // before the edit moves the offsets the motion relies on
            typed = nil
            // Only a real key press pairs: completion, find/replace and paste insert programmatically.
            if !accepting, let s = replacementString, let e = NSApp.currentEvent, e.type == .keyDown, e.characters == s,
               let buffer, buffer.handleTyped(s, replacing: range, in: view, enabled: CompletionPreferences.autoPair) {
                if s.count == 1 { typedCharacter(s.first!) }
                return false
            }
            if !accepting, !view.hasMarkedText(), let s = replacementString, s.count == 1 { typed = s.first }
            noteEdit(range, replacementString)
            return true
        }

        func textDidChange(_ notification: Notification) {
            decor?.refresh()
            refreshRainbow()
            clearStaleSpelling()
            feedSnippetSession(in: notification.object as? NSTextView ?? textView)
            guard !accepting else { return }
            defer { typed = nil }
            guard let ch = typed else { return popup.isVisible ? refresh() : () }
            typedCharacter(ch)
        }

        private func typedCharacter(_ ch: Character) {
            signatureHelpTyped(ch)
            let identifier = ch.isLetter || ch.isNumber || ch == "_" || ch == "-"
            if CompletionPreferences.suggestWhileTyping, Self.triggers.contains(ch) || (!popup.isVisible && identifier) {
                request(explicit: false)
            } else if popup.isVisible {
                refresh()
            }
        }

        // MARK: Tables

        func tableAtCaret() -> TableLookup? {
            guard let tv = textView else { return nil }
            return buffer?.table(at: tv.selectedRange().location)
        }

        /// Deferred: the selection also changes while SwiftUI is updating this view.
        func refreshCaretInTable() {
            Task { [weak self] in
                guard let self, let tables, tables.editor === self else { return }
                let inTable = tableAtCaret() != nil
                if tables.caretInTable != inTable { tables.caretInTable = inTable }
            }
        }

        /// One `insertText(_:replacementRange:)`: the storage funnel, undo, highlighting and the engine see an ordinary edit.
        func replace(_ range: NSRange, with text: String, selecting selection: NSRange, session: (snippet: Snippet, at: Int)? = nil) {
            guard !readOnly, let tv = textView else { return }
            (tv as? EditorTextView)?.clearExtras()      // completion, snippets and formatting act on the primary caret
            dismiss()
            endSnippetSession()
            tv.window?.makeFirstResponder(tv)
            accepting = true
            tv.insertText(text, replacementRange: range)
            tv.setSelectedRange(selection)
            accepting = false                            // the caret move is part of the edit: no preview sync
            tv.scrollRangeToVisible(selection)
            if let session { beginSnippetSession(session.snippet, at: session.at) }
        }

        func apply(_ model: TableModel) {
            guard let tv = textView, let e = TableCode.edit(model, in: tv.string, settings: buffer?.indentSettings ?? .standard) else { return }
            let end = e.range.location + (e.replacement as NSString).length
            replace(e.range, with: e.replacement, selecting: NSRange(location: end, length: 0))
        }

        /// Inserts text chosen by the syntax mode at the caret as one undoable edit; the caret ends after it.
        func insertText(_ make: (SyntaxMode) -> String) {
            guard let tv = textView, let buffer else { return }
            let sel = tv.selectedRange()
            let text = make(buffer.mode(at: sel.location))
            replace(sel, with: text, selecting: NSRange(location: sel.location + (text as NSString).length, length: 0))
        }

        /// Bold, italic, underline, lists and math from the bottom bar and the Format menu: one undoable edit.
        func format(_ command: Formatting.Command) {
            guard let tv = textView, let e = buffer?.formatEdit(command, selection: tv.selectedRange()) else { return }
            replace(e.range, with: e.replacement, selecting: e.selection)
        }

        /// typstyle on the document or the selected nodes: one undoable edit; the caret keeps its place in the text.
        func formatCode(selectionOnly: Bool) {
            guard let tv = textView else { return }
            let d = UserDefaults.standard
            let sel = tv.selectedRange()
            let edit = buffer?.codeFormatEdit(selection: selectionOnly ? sel : nil, width: d.object(forKey: SettingsKey.formatWidth) as? Int ?? 80,
                                              indent: d.object(forKey: SettingsKey.formatIndent) as? Int ?? 2)
            guard let r = edit else { NSSound.beep(); return }
            let new = (r.text as NSString).length, end = NSMaxRange(r.range)
            let caret = sel.location >= end ? sel.location + new - r.range.length : min(sel.location, r.range.location + new)
            replace(r.range, with: r.text, selecting: NSRange(location: max(caret, 0), length: 0))
        }

        /// Deferred: the selection also changes while SwiftUI is updating this view.
        private func refreshSelectedWords() {
            Task { [weak self] in
                guard let self, let actions, actions.editor === self, let tv = textView else { return }
                let words = tv.selectedRange().length > 0 ? buffer?.selectedWordCount(tv.selectedRange()) : nil
                if actions.selectedWords != words { actions.selectedWords = words }
            }
        }

        func insert(_ snippet: Snippet) {
            guard let tv = textView else { return }
            let sel = tv.selectedRange()
            let placed = TableCode.placement(of: snippet, in: tv.string, replacing: sel)
            replace(sel, with: placed.replacement, selecting: placed.selection, session: (placed.snippet, placed.at))
        }

        /// Deferred like the others: the jump bar's last segment follows the heading section around the caret.
        private func refreshCaretHeading() {
            Task { [weak self] in
                guard let self, isPrimary, let actions, let tv = textView, let buffer else { return }
                let caret = tv.selectedRange().location
                let heading = buffer.headingRegions.last { $0.heading <= caret && caret <= NSMaxRange($0.hidden) }?.heading
                if actions.caretHeading != heading { actions.caretHeading = heading }
            }
        }

        /// Deferred like the others: the status line shows the focused editor's caret.
        func refreshCaretStatus() {
            Task { [weak self] in
                guard let self, let actions, actions.editor === self, let tv = textView else { return }
                let status = EditorLocation.status(selection: tv.selectedRange(), in: tv.string)
                if actions.caretStatus != status { actions.caretStatus = status }
                actions.caretEpoch &+= 1
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            decor?.refresh()
            refreshCaretStatus()
            refreshBracketMatch()
            refreshOccurrences()
            refreshCaretInTable()
            refreshSelectedWords()
            refreshCaretHeading()
            signatureHelpCaretMoved()
            if popup.isVisible && !accepting { refresh() }
            checkSnippetSelection()
            typewriterScroll()
            guard let tv = textView, let file = buffer?.path else { return }
            let sel = tv.selectedRange()
            if !swapping { remember(sel) }
            if sel.length == 0, reportsCursor { project?.cursorMoved(in: file, to: sel.location, programmatic: accepting || programmatic) }
        }

        func textDidEndEditing(_ notification: Notification) { dismiss(); hideSignatureHelp() }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            if !popup.isVisible, (view as? EditorTextView)?.multiCommand(selector) == true { return true }
            if selector == #selector(NSResponder.deleteBackward(_:)), let buffer, buffer.handleBackspace(in: view, enabled: CompletionPreferences.autoPair) { return true }
            // Backspace in space indentation removes a whole level, like Shift-Tab, not one space.
            if selector == #selector(NSResponder.deleteBackward(_:)), let e = Indent.backspace(in: view.string, selection: view.selectedRange(), settings: buffer?.indentSettings ?? .standard) {
                replace(e.range, with: e.replacement, selecting: e.selection)
                return true
            }
            // A key that does not accept completions closes the list and does its normal job.
            let returnKey = selector == #selector(NSResponder.insertNewline(_:)), tabKey = selector == #selector(NSResponder.insertTab(_:))
            if popup.isVisible, (returnKey && CompletionPreferences.acceptKeys == .tabOnly) || (tabKey && CompletionPreferences.acceptKeys == .returnOnly) { dismiss() }
            guard popup.isVisible else {
                if selector == #selector(NSResponder.insertNewline(_:)), let buffer {
                    let e = buffer.newlineEdit(view.selectedRange())
                    replace(e.range, with: e.replacement, selecting: e.selection)
                    return true
                }
                if selector == #selector(NSResponder.cancelOperation(_:)), signaturePopup.isVisible { hideSignatureHelp(); return true }
                if selector == #selector(NSResponder.cancelOperation(_:)), snippetSession != nil { endSnippetSession(); return true }
                let forward = selector == #selector(NSResponder.insertTab(_:))
                let sel = view.selectedRange()
                if (forward || selector == #selector(NSResponder.insertBacktab(_:))), jumpSnippetStop(forward: forward, in: view) { return true }
                // Tab jumps between arguments, else nests; Shift-Tab outdents where it nests, else jumps back.
                if forward || selector == #selector(NSResponder.insertBacktab(_:)),
                   let r = forward ? buffer?.tabJump(from: sel, forward: true) ?? buffer?.indentAtCaret(sel)
                                   : buffer?.outdentAtCaret(sel) ?? buffer?.tabJump(from: sel, forward: false) ?? buffer?.outdentAtCaret(sel, anywhere: true) {
                    selectProgrammatically(r, in: view)
                    return true
                }
                return exitFocusOnCancel(selector)
            }
            switch selector {
            case #selector(NSResponder.moveUp(_:)): popup.move(by: -1)
            case #selector(NSResponder.moveDown(_:)): popup.move(by: 1)
            case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)): popup.move(by: -popup.pageSize)
            case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)): popup.move(by: popup.pageSize)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                guard let item = popup.selected else { return false }
                accept(item)
            case #selector(NSResponder.cancelOperation(_:)): dismiss()
            default: return false
            }
            return true
        }

        struct Mark: Equatable {
            let range: NSRange
            let severity: Diagnostic.Severity
            /// Lint hints get a quiet dotted underline; compiler errors and warnings a solid red or orange one.
            var attributes: [NSAttributedString.Key: Any] {
                if severity == .hint { return [.underlineStyle: NSUnderlineStyle.single.union(.patternDot).rawValue, .underlineColor: NSColor.secondaryLabelColor] }
                return [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: severity == .error ? NSColor.systemRed : NSColor.systemOrange]
            }
        }

        /// A word marked while it was prose keeps its mark once an edit makes it code (`$` wrapping it, a quote
        /// turning later lines into a string); nothing re-checks it. Clear the marks outside prose, in the whole
        /// document up to 200k characters, else in the caret's blank-line-delimited block.
        private func clearStaleSpelling() {
            guard let tv = textView, let buffer, tv.isContinuousSpellCheckingEnabled else { return }
            let ns = tv.string as NSString
            var block = NSRange(location: 0, length: ns.length)
            if ns.length > 200_000 {
                let sel = min(tv.selectedRange().location, ns.length)
                let before = ns.range(of: "\n\n", options: .backwards, range: NSRange(location: 0, length: sel))
                let after = ns.range(of: "\n\n", range: NSRange(location: sel, length: ns.length - sel))
                let start = before.location == NSNotFound ? 0 : NSMaxRange(before)
                block = NSRange(location: start, length: (after.location == NSNotFound ? ns.length : after.location) - start)
            }
            for gap in buffer.nonProseRanges(in: block) { tv.setSpellingState(0, range: gap) }
        }

        /// Spell check only prose: drop results inside code, math, strings and raw. Where the document declares
        /// `#set text(lang:)`, each prose piece is re-checked with that language's orthography.
        func textView(_ view: NSTextView, didCheckTextIn range: NSRange, types: NSTextCheckingTypes,
                      options: [NSSpellChecker.OptionKey: Any], results: [NSTextCheckingResult],
                      orthography: NSOrthography, wordCount: Int) -> [NSTextCheckingResult] {
            guard let buffer else { return results }
            let prose = buffer.proseRanges(in: range)
            var out = results.filter { r in
                guard r.resultType.intersection([.spelling, .grammar, .correction]).isEmpty == false else { return true }
                return prose.contains { NSIntersectionRange($0, r.range) == r.range }
            }
            let inherited = project.flatMap { p in p.main == buffer.path ? nil : p.openBuffer(p.main).flatMap { TextLanguage.documentDefault(in: $0.storage.string) } }
            let text = view.string
            let sections = TextLanguage.sections(in: text, inherited: inherited)
            guard !sections.isEmpty else { return out }
            let checker = NSSpellChecker.shared
            let available = Set(checker.availableLanguages.map { $0.replacingOccurrences(of: "-", with: "_") })
            for p in prose {
                // Cut the prose range at every section boundary, then check each piece in its own language.
                var cuts = Set([p.location, NSMaxRange(p)])
                for s in sections { for b in [s.range.location, NSMaxRange(s.range)] where b > p.location && b < NSMaxRange(p) { cuts.insert(b) } }
                let sorted = cuts.sorted()
                for (a, b) in zip(sorted, sorted.dropFirst()) {
                    let piece = NSRange(location: a, length: b - a)
                    guard let lang = sections.last(where: { NSLocationInRange(a, $0.range) })?.language else { continue }
                    let id = available.contains(lang.identifier) ? lang.identifier : lang.lang
                    out.removeAll { NSIntersectionRange($0.range, piece).length > 0 && $0.resultType.contains(.spelling) }
                    var orth: NSOrthography? = NSOrthography.defaultOrthography(forLanguage: id)
                    // `lang: "en"` names no region, so British and American spellings both count; a region picks its dictionary.
                    let regional = lang.region.map { "\(lang.lang)_\($0.uppercased())" }   // Typst writes "gb", the dictionary is en_GB
                    let dictionaries = if let regional, available.contains(regional) { [regional] }
                        else { [lang.lang] + available.filter { $0.hasPrefix(lang.lang + "_") }.sorted() }
                    out += checker.check(text, range: piece, types: NSTextCheckingResult.CheckingType.spelling.rawValue,
                                         options: [.orthography: orth as Any], inSpellDocumentWithTag: view.spellCheckerDocumentTag,
                                         orthography: &orth, wordCount: nil)
                        .filter { r in
                            guard NSIntersectionRange(r.range, piece) == r.range else { return false }
                            let word = (text as NSString).substring(with: r.range)
                            return !dictionaries.contains { checker.checkSpelling(of: word, startingAt: 0, language: $0, wrap: false,
                                                                                  inSpellDocumentWithTag: view.spellCheckerDocumentTag, wordCount: nil).location == NSNotFound }
                        }
                }
            }
            return out
        }

        /// Read-only gets an empty one: the buffer's undo would still change the text (e.g. take back a Zotero sync).
        func undoManager(for view: NSTextView) -> UndoManager? { readOnly ? noUndo : buffer?.undoManager }
        private let noUndo = UndoManager()

        /// Re-applies the diagnostic underlines that overlap `range` (the ⌘-hover underline removed them there).
        func restoreMarks(in range: NSRange, of tv: NSTextView) {
            guard let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return }
            for m in appliedMarks ?? [] where NSIntersectionRange(m.range, range).length > 0 {
                guard let r = tcs.textRange(for: m.range) else { continue }
                tlm.setRenderingAttributes(m.attributes, for: r)
            }
        }

        /// Underlines are rendering attributes: no storage edit, no undo entry, no engine message.
        /// Later marks draw over earlier ones, so lint hints come first; they get no pill.
        func apply(_ diagnostics: [Diagnostic], to tv: NSTextView) {
            let length = tv.textStorage?.length ?? 0
            let new = diagnostics.compactMap { d -> Mark? in
                guard case .project(let loc) = d.origin, loc.range.location < length else { return nil }
                return Mark(range: loc.range.clamped(within: length), severity: d.severity)
            }
            decor?.items = diagnostics.compactMap { d in
                guard case .project(let loc) = d.origin, loc.range.location <= length, d.severity != .hint else { return nil }
                return DecorationView.Item(range: loc.range, error: d.severity == .error, message: d.message, fixable: QuickFixes.mayFix(d))
            }
            guard new != appliedMarks, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return }
            appliedMarks = new
            tlm.removeRenderingAttribute(.underlineStyle, for: tcs.documentRange)
            tlm.removeRenderingAttribute(.underlineColor, for: tcs.documentRange)
            for m in new {
                guard let range = tcs.textRange(for: m.range) else { continue }
                tlm.setRenderingAttributes(m.attributes, for: range)
            }
        }
    }
}

private extension NSRange {
    /// A zero-length range gets one character so the underline is visible; the result stays inside `length`.
    func clamped(within length: Int) -> NSRange {
        let loc = min(location, length)
        var len = min(self.length, length - loc)
        if len == 0 && loc < length { len = 1 }
        if len == 0 && loc > 0 { return NSRange(location: loc - 1, length: 1) }
        return NSRange(location: loc, length: len)
    }
}

/// Line numbers for TextKit 2: one number per layout fragment (a paragraph) in the viewport.
final class LineNumberRuler: NSRulerView {
    weak var textView: NSTextView?
    weak var editor: EditorView.Coordinator?          // disclosure triangles on heading lines (design/14e)
    var relative = RelativeNumbers.off                // Vim: distance from the caret line (plain logical lines, folds count)
    private var lastCaretLine = 0
    var showsNumbers = true                           // off: only fold triangles and git bars
    var hoverY: CGFloat? { didSet { if hoverY != oldValue, hovered { needsDisplay = true } } }   // pointer row in the ruler, for the ribbon's highlighted region
    var hoverWindow: NSPoint?                         // the pointer in window coordinates, re-read when the view scrolls under it
    private var newlineOffsets: [Int]?                // offsets of every "\n" in the text; nil after an edit or a swapped storage
    private weak var indexedStorage: NSTextStorage?
    var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }   // as in Xcode, open sections show their chevron only under the pointer
    var rainbowLayers: [RainbowBarLayer] = []         // one per assistant change in view, reused while scrolling
    var rainbowHits: [RainbowHit] = []

    init(scrollView: NSScrollView, textView: NSTextView, editor: EditorView.Coordinator) {
        self.textView = textView
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 50
        let nc = NotificationCenter.default
        scrollView.contentView.postsBoundsChangedNotifications = true
        nc.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(redraw), name: NSText.didChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: textView)
        // A swapped storage changes the document height without any edit notification.
        nc.addObserver(self, selector: #selector(redraw), name: NSView.frameDidChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(textStorageEdited), name: NSTextStorage.didProcessEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(redraw), name: .bookmarksChanged, object: nil)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    /// Also moves the pointer's row: when the view scrolls under a still pointer, a different region is under it.
    @objc private func redraw() {
        if hovered, let w = hoverWindow { hoverY = convert(w, from: nil).y }
        needsDisplay = true
    }

    /// Only a move to another line changes the highlight and the relative numbers.
    @objc private func selectionChanged() {
        guard let tv = textView, let text = tv.textStorage?.string as NSString? else { return }
        let line = lineNumber(at: min(tv.selectedRange().location, text.length), in: text)
        if line != lastCaretLine { redraw() }
    }

    @objc private func textStorageEdited() { newlineOffsets = nil }

    /// 1-based line number of text offset `offset`, by binary search in the cached newline offsets.
    private func lineNumber(at offset: Int, in text: NSString) -> Int {
        let storage = textView?.textStorage
        if indexedStorage !== storage { newlineOffsets = nil; indexedStorage = storage }
        if newlineOffsets == nil {
            var out: [Int] = [], buffer = [unichar](repeating: 0, count: 4096), pos = 0
            while pos < text.length {
                let n = min(buffer.count, text.length - pos)
                text.getCharacters(&buffer, range: NSRange(location: pos, length: n))
                for i in 0..<n where buffer[i] == 10 { out.append(pos + i) }
                pos += n
            }
            newlineOffsets = out
        }
        let nl = newlineOffsets ?? []
        var lo = 0, hi = nl.count                       // count of newlines before `offset`
        while lo < hi { let mid = (lo + hi) / 2; if nl[mid] < offset { lo = mid + 1 } else { hi = mid } }
        return lo + 1
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // A theme paints the gutter like its editor, only within the ruler's own width: the rect and the ruler's
        // layer reach over the text, so a wider fill (or any draw(_:) override, which fills via super) hides it.
        if Highlighter.style.colors.background != .textBackgroundColor {
            Highlighter.style.colors.background.setFill()
            NSRect(x: 0, y: rect.minY, width: ruleThickness, height: rect.height).intersection(bounds).fill()
        }
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage,
              let text = tcs.textStorage?.string as NSString?, let viewport = tlm.textViewportLayoutController.viewportRange
        else { return }
        let pt: CGFloat = 11, colors = Highlighter.style.colors
        let font = NSFont.monospacedDigitSystemFont(ofSize: pt, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colors.ruler]
        let current: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: pt, weight: .bold),
                                                      .foregroundColor: colors.text]
        let caretLine = lineNumber(at: min(tv.selectedRange().location, text.length), in: text)
        lastCaretLine = caretLine
        let origin = tv.textContainerOrigin
        drawFoldRibbon(tv, tlm, tcs, viewport: viewport)
        tlm.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
            let start = tcs.offset(of: fragment.rangeInElement.location)
            let line = self.lineNumber(at: min(start, text.length), in: text)
            let y = self.convert(NSPoint(x: 0, y: fragment.layoutFragmentFrame.minY + origin.y), from: tv).y
            let lineTop = fragment.textLineFragments.first?.typographicBounds.minY ?? 0
            self.drawFoldMark(at: start, y: y + lineTop, height: fragment.textLineFragments.first?.typographicBounds.height ?? 0)
            self.drawGitMark(line: line, start: start, end: tcs.offset(of: fragment.rangeInElement.endLocation), y: y, height: fragment.layoutFragmentFrame.height)
            guard self.showsNumbers else { return y < self.bounds.maxY }
            let shown = self.relative == .off || (line == caretLine && self.relative == .hybrid) ? line : abs(line - caretLine)
            let label = "\(shown)" as NSString
            let style = line == caretLine ? current : attrs
            let size = label.size(withAttributes: style)
            label.draw(at: NSPoint(x: self.ruleThickness - size.width - 16, y: y + lineTop), withAttributes: style)   // 16: the fold ribbon
            return y < self.bounds.maxY
        }
        layoutRainbow(tv, tcs, viewport: viewport)
    }
}
