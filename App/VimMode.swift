import AppKit
import TypoKit

extension SettingsKey {
    static let vimMode = "vimMode"
    static let relativeNumbers = "vimRelativeNumbers"       // RelativeNumbers raw value; applies only while Vim mode is on
}

/// Vim mode for one editor: turns key presses into `VimState` input and applies what it returns (the replacement as
/// one undo step, the selection, the register on the pasteboard, save and close). Insert mode leaves every key but Esc
/// to AppKit, so completion, snippets and IME work as usual.
@MainActor final class VimController {
    private(set) var state = VimState()
    private weak var textView: EditorTextView?
    private weak var coordinator: EditorView.Coordinator?
    private var undoGroup: UndoManager?
    private var undoObservers: [NSObjectProtocol] = []
    private var pasteboardCount = -1
    private var message: String?
    private var wasEnabled = false
    private var blockApplied = false
    private var searchApplied: [NSRange] = []

    init(textView: EditorTextView, coordinator: EditorView.Coordinator) {
        self.textView = textView
        self.coordinator = coordinator
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.vimMode) }

    static var relativeNumbers: RelativeNumbers {
        isEnabled ? RelativeNumbers(rawValue: UserDefaults.standard.string(forKey: SettingsKey.relativeNumbers) ?? "") ?? .off : .off
    }

    /// A block in every mode but Insert; the user's cursor style there.
    func caretShape(_ base: CaretShape) -> CaretShape {
        blockApplied = Self.isEnabled && state.mode != .insert
        return blockApplied ? .block : base
    }

    /// Runs with every settings change: turning Vim mode off drops its state and its mode line.
    func settingsChanged() {
        let on = Self.isEnabled
        if on != wasEnabled {
            wasEnabled = on
            if !on { endUndoGroup(); state = VimState(); message = nil; applySearch([]) }
        }
        publishStatus()
    }

    private func publishStatus() {
        Task { [weak self] in
            guard let self, let c = coordinator, let a = c.actions, a.editor === c else { return }
            let s = Self.isEnabled ? state.badge(message: message) : nil
            if a.vimStatus != s { a.vimStatus = s }
        }
    }

    // MARK: Keys

    /// True when the key was Vim's.
    func handle(_ event: NSEvent, in tv: EditorTextView) -> Bool {
        guard Self.isEnabled, let c = coordinator else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.contains(.command), let key = Self.key(from: event, mods) else { return false }
        if state.mode == .insert {
            // Insert mode leaves the typing to AppKit; Ctrl-o, Ctrl-w and Ctrl-u are Vim's.
            guard key == .escape || key == .ctrl("[") || key == .ctrl("o") || key == .ctrl("w") || key == .ctrl("u") else { return false }
            if tv.hasMarkedText() { return false }         // Esc belongs to the input method
            // Esc first closes the completion list, the signature help or the snippet's tab stops.
            if key == .escape || key == .ctrl("["), c.completionVisible || c.signaturePopup.isVisible || c.snippetSession != nil { return false }
        }
        syncPasteboard()
        let prev = state.mode
        let r = state.handle(key: key, in: tv.string, selection: tv.selectedRange(), indent: c.buffer?.indentSettings ?? .standard, pageLines: pageLines(tv),
                                visibleLines: needsVisibleLines(event, key) ? visibleLines(tv) : nil)
        guard r.handled else { return false }               // e.g. Esc with nothing to cancel goes on to the app
        message = r.message
        if let ranges = r.searchRanges { applySearch(ranges) }
        if r.mode == .insert, prev != .insert { beginUndoGroup() }
        if let e = r.edits.first {
            tv.breakUndoCoalescing()                       // typing before it must not merge with this change
            c.replace(e.range, with: e.text, selecting: r.selection)
        } else if r.selection != tv.selectedRange() {
            tv.setSelectedRange(r.selection)
        }
        tv.scrollRangeToVisible(NSRange(location: min(state.cursor, tv.string.utf16.count), length: 0))
        for command in r.commands { run(command, tv, c) }
        if let reg = r.register { writePasteboard(reg) }
        if prev == .insert, r.mode != .insert { endUndoGroup(); tv.breakUndoCoalescing() }
        if blockApplied != (state.mode != .insert), let scroll = tv.enclosingScrollView { c.applyAppearanceSettings(tv, scroll) }
        publishStatus()
        return true
    }

    private static func key(from event: NSEvent, _ mods: NSEvent.ModifierFlags) -> VimKey? {
        switch event.keyCode {
        case 53: return .escape
        case 123: return .left
        case 124: return .right
        case 125: return .down
        case 126: return .up
        case 36, 76: return .returnKey
        case 51: return .backspace
        case 48: return .tab
        default: break
        }
        // A key without a character (a dead key such as ^ or ´) is an unknown key, which Normal mode swallows:
        // passed on, it would start marked text and every later key would type into the file.
        if mods.contains(.control) { return .ctrl(event.charactersIgnoringModifiers?.lowercased().first ?? "\u{0}") }
        guard let ch = (event.characters?.isEmpty == false ? event.characters : event.charactersIgnoringModifiers)?.first else { return .char("\u{0}") }
        if let v = ch.unicodeScalars.first?.value, (0xF700...0xF8FF).contains(v) { return nil }   // function keys
        return .char(ch)
    }

    /// H, M, L and Ctrl-e/Ctrl-y need the window's lines.
    private func needsVisibleLines(_ event: NSEvent, _ key: VimKey) -> Bool {
        if key == .ctrl("e") || key == .ctrl("y") { return true }
        guard case .char(let ch) = key else { return false }
        return "HML".contains(ch)
    }

    /// The lines (0-based) the text view shows.
    private func visibleLines(_ tv: NSTextView) -> Range<Int>? {
        let r = tv.visibleRect, ns = tv.string as NSString
        func line(at p: NSPoint) -> Int {
            let loc = min(tv.characterIndexForInsertion(at: p), ns.length)
            var n = 0, i = 0
            while i < loc {
                let f = ns.range(of: "\n", range: NSRange(location: i, length: loc - i))
                if f.location == NSNotFound { break }
                n += 1; i = NSMaxRange(f)
            }
            return n
        }
        let top = line(at: NSPoint(x: r.minX + 1, y: r.minY + 1)), bottom = line(at: NSPoint(x: r.minX + 1, y: r.maxY - 1))
        return top..<(max(top, bottom) + 1)
    }

    /// The matches of the active search get a light background (a rendering attribute: no edit, no undo entry).
    private func applySearch(_ ranges: [NSRange]) {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return }
        for r in searchApplied { if let t = tcs.textRange(for: r) { tlm.removeRenderingAttribute(.backgroundColor, for: t) } }
        let length = tv.string.utf16.count
        searchApplied = ranges.filter { NSMaxRange($0) <= length }
        for r in searchApplied { if let t = tcs.textRange(for: r) { tlm.addRenderingAttribute(.backgroundColor, value: NSColor.findHighlightColor.withAlphaComponent(0.45), for: t) } }
    }

    private func pageLines(_ tv: NSTextView) -> Int {
        max(4, Int(tv.visibleRect.height / (tv.font?.boundingRectForFont.height ?? 16)))
    }

    // MARK: Undo: an Insert session (and the change that started it) is one step

    private func beginUndoGroup() {
        guard undoGroup == nil, let um = coordinator?.buffer?.undoManager else { return }
        um.groupsByEvent = false
        um.beginUndoGrouping()
        undoGroup = um
        // An undo or redo from the menu closes the open group by itself: let go of it then.
        undoObservers = [Notification.Name.NSUndoManagerWillUndoChange, Notification.Name.NSUndoManagerWillRedoChange].map {
            NotificationCenter.default.addObserver(forName: $0, object: um, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.endUndoGroup() }
            }
        }
    }

    private func endUndoGroup() {
        undoObservers.forEach(NotificationCenter.default.removeObserver)
        undoObservers = []
        guard let um = undoGroup else { return }
        undoGroup = nil
        if um.groupingLevel > 0 { um.endUndoGrouping() }
        um.groupsByEvent = true
    }

    // MARK: Register

    private func syncPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != pasteboardCount else { return }
        pasteboardCount = pb.changeCount
        if let s = pb.string(forType: .string) { state.register = s }
    }

    private func writePasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        pasteboardCount = pb.changeCount
    }

    // MARK: Commands for the app

    private func run(_ command: VimCommand, _ tv: EditorTextView, _ c: EditorView.Coordinator) {
        switch command {
        case .undo(let n), .redo(let n):
            endUndoGroup()
            guard let um = c.buffer?.undoManager else { return }
            for _ in 0..<n {
                if case .undo = command { if um.canUndo { um.undo() } } else if um.canRedo { um.redo() }
            }
            tv.setSelectedRange(NSRange(location: min(tv.selectedRange().location, tv.string.utf16.count), length: 0))
        case .lineNumbers(let n): UserDefaults.standard.set(n.rawValue, forKey: SettingsKey.relativeNumbers)
        case .save:
            if let p = c.project { Task { await Self.save(p) } }
        case .close: close(tv, c)
        case .saveAndClose:
            guard let p = c.project else { return close(tv, c) }
            Task { await Self.save(p); close(tv, c) }
        case .scroll(.line(let n)): scrollLines(n, tv)
        case .scroll(let how): scroll(how, tv)
        }
    }

    /// What File > Save does.
    private static func save(_ project: Project) async {
        let d = UserDefaults.standard
        let format = d.bool(forKey: SettingsKey.formatOnSave)
            ? (width: d.object(forKey: SettingsKey.formatWidth) as? Int ?? 80, indent: d.object(forKey: SettingsKey.formatIndent) as? Int ?? 2) : nil
        project.prepareDirtyBuffersForSave(format: format, trimBlankLines: FilePreferences.trimBlankLines())
        try? await project.saveAll()
    }

    /// What File > Close Tab does for this pane.
    private func close(_ tv: EditorTextView, _ c: EditorView.Coordinator) {
        guard let project = c.project, let f = c.buffer?.path else { return tv.window?.performClose(nil) ?? () }
        if c.isPrimary, project.tabs.contains(f) { project.closeTab(f) }
        else if !c.isPrimary, let l = c.layout, l.tabs.contains(f) { l.closeSecondTab(f, in: project) }
        else { tv.window?.performClose(nil) }
    }

    /// Ctrl-e (n > 0) and Ctrl-y: the text moves by whole lines.
    private func scrollLines(_ n: Int, _ tv: EditorTextView) {
        guard let scroll = tv.enclosingScrollView else { return }
        let clip = scroll.contentView, h = (tv.font?.boundingRectForFont.height ?? 16) * CGFloat(n)
        let maxY = max(0, tv.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, clip.bounds.minY + h), maxY)))
        scroll.reflectScrolledClipView(clip)
    }

    private func scroll(_ how: VimScroll, _ tv: EditorTextView) {
        guard let window = tv.window, let scroll = tv.enclosingScrollView else { return }
        let caret = tv.convert(window.convertFromScreen(tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)), from: nil)
        let clip = scroll.contentView
        let y = switch how {
        case .center: caret.midY - clip.bounds.height / 2
        case .top: caret.minY
        case .bottom: caret.maxY - clip.bounds.height
        case .line: clip.bounds.minY
        }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, y)))
        scroll.reflectScrolledClipView(clip)
    }
}
