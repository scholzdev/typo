import AppKit
import SwiftUI
import TypoKit
import TypstEngine

/// What the editor keeps for multiple cursors: the extra selections (the text view's own selection stays the
/// primary one), and the hooks that tie it to the buffer and the decoration layer.
struct MultiCursorState {
    var extras: [MultiCursor.Sel] = []
    /// The buffer edits go to; nil when the editor is read-only.
    var buffer: (() -> Buffer?)?
    var onChange: (() -> Void)?
    /// True while our own edit runs, so the storage observer does not take it for a foreign change.
    var applying = false
    var observing = false
}

extension EditorTextView {
    var hasExtras: Bool { !multi.extras.isEmpty }

    func setExtras(_ sels: [MultiCursor.Sel]) {
        guard sels != multi.extras else { return }
        multi.extras = sels
        multi.onChange?()
    }

    func clearExtras() { setExtras([]) }

    /// Any change to the text that is not ours leaves the extra selections pointing at the wrong place: drop them.
    func observeStorageForMultiCursor() {
        guard !multi.observing else { return }
        multi.observing = true
        NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: nil, queue: .main) { [weak self] n in
            let source = (n.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let storage = self.textStorage, source == ObjectIdentifier(storage), storage.editedMask.contains(.editedCharacters), !self.multi.applying else { return }
                self.clearExtras()
            }
        }
    }

    /// Primary plus extras, sorted and merged.
    var allRanges: [NSRange] { MultiCursor.merge(multi.extras.map(\.range) + [selectedRange()]) }

    /// Makes `ranges` the cursors with `primary` (one of them) as the text view's own selection.
    func setCursors(_ ranges: [NSRange], primary: NSRange) {
        setExtras(ranges.filter { $0 != primary }.map { MultiCursor.Sel($0) })
        setSelectedRange(primary)
        scrollRangeToVisible(primary)
        multi.onChange?()
    }

    /// Folds extras that the primary selection now covers into it.
    private func absorbExtras() {
        var u = selectedRange()
        var keep = multi.extras
        var changed = true
        while changed {
            changed = false
            for e in keep where (e.range.location < NSMaxRange(u) && u.location < NSMaxRange(e.range)) || e.range.location == u.location {
                u = MultiCursor.merge([u, e.range])[0]
                keep.removeAll { $0 == e }
                changed = true
                break
            }
        }
        if u != selectedRange() { setSelectedRange(u) }
        setExtras(keep)
    }

    // MARK: Edits

    /// Applies a fan-out result as one undo step; the cursor that was primary stays primary. Undo and redo bring
    /// the cursors back with the text.
    private func commit(_ r: (edits: [Replacement], ranges: [NSRange]), _ buffer: Buffer) {
        guard !r.edits.isEmpty else { return }
        let before = allRanges
        let pi = before.firstIndex { NSIntersectionRange($0, selectedRange()).length > 0 || $0.location == selectedRange().location } ?? before.count - 1
        let ranges = r.ranges
        let primary = ranges[min(pi, ranges.count - 1)]
        let um = buffer.undoManager
        um.beginUndoGrouping()                   // so the cursor entry and the edit are one group, run loop event or not
        registerCursorRestore(to: (multi.extras, selectedRange()), then: (ranges.filter { $0 != primary }.map { MultiCursor.Sel($0) }, primary), in: um)
        multi.applying = true
        buffer.apply(r.edits)
        multi.applying = false
        um.endUndoGrouping()
        setCursors(ranges, primary: primary)
    }

    /// Undo puts the cursors back as `to`, redo as `then`. Deferred a turn: the text is restored by the entries
    /// that run around this one, and the storage observer drops cursors on such a change.
    private func registerCursorRestore(to: (extras: [MultiCursor.Sel], primary: NSRange), then: (extras: [MultiCursor.Sel], primary: NSRange), in um: UndoManager) {
        um.registerUndo(withTarget: self) { tv in
            MainActor.assumeIsolated {
                DispatchQueue.main.async { tv.restoreCursors(to) }
                tv.registerCursorRestore(to: then, then: to, in: um)
            }
        }
    }

    private func restoreCursors(_ c: (extras: [MultiCursor.Sel], primary: NSRange)) {
        let length = (string as NSString).length
        guard NSMaxRange(c.primary) <= length else { return }
        setExtras(c.extras.filter { NSMaxRange($0.range) <= length })
        setSelectedRange(c.primary)
    }

    /// Typing and pasting at several cursors. False means: not ours, let the text view do it.
    func multiInsert(_ any: Any, _ replacementRange: NSRange) -> Bool {
        guard hasExtras else { return false }
        guard replacementRange.location == NSNotFound, !hasMarkedText(), let buffer = multi.buffer?(),
              let s = (any as? NSAttributedString)?.string ?? any as? String else { clearExtras(); return false }
        // Pairs close only for a real key press, as with one caret.
        let key = NSApp.currentEvent.map { $0.type == .keyDown && $0.characters == s } ?? false
        let t = buffer.typedAtCursors(s, allRanges, enabled: key && CompletionPreferences.autoPair)
        commit((t.edits, t.ranges), buffer)
        buffer.trackAutoClosers(t.closers)
        return true
    }

    private static let moves: [Selector: (MultiCursor.Move, Bool)] = {
        var m: [Selector: (MultiCursor.Move, Bool)] = [:]
        let table: [(String, MultiCursor.Move)] = [
            ("moveLeft", .left), ("moveRight", .right), ("moveUp", .up), ("moveDown", .down),
            ("moveWordLeft", .wordLeft), ("moveWordRight", .wordRight),
            ("moveToLeftEndOfLine", .lineStart), ("moveToRightEndOfLine", .lineEnd),
            ("moveToBeginningOfLine", .lineStart), ("moveToEndOfLine", .lineEnd),
            ("moveToBeginningOfParagraph", .lineStart), ("moveToEndOfParagraph", .lineEnd),
            ("moveToBeginningOfDocument", .docStart), ("moveToEndOfDocument", .docEnd),
        ]
        for (name, move) in table {
            m[Selector(name + ":")] = (move, false)
            m[Selector(name + "AndModifySelection:")] = (move, true)
        }
        return m
    }()

    /// A key command with several cursors: applies it to all of them. False when it is not one we handle.
    func multiCommand(_ selector: Selector) -> Bool {
        guard hasExtras else { return false }
        if selector == #selector(NSResponder.cancelOperation(_:)) || selector == #selector(NSTextView.complete(_:)) {
            clearExtras()
            return true
        }
        if let (move, extend) = Self.moves[selector] {
            let moved = MultiCursor.move(multi.extras, in: string as NSString, move, extend: extend)
            perform(selector, with: nil)          // the primary selection: the text view's own movement
            setExtras(moved)
            absorbExtras()
            return true
        }
        guard let buffer = multi.buffer?() else { return false }
        let text = string as NSString
        let ranges = allRanges
        switch selector {
        case #selector(NSResponder.deleteToBeginningOfLine(_:)), #selector(NSResponder.deleteToBeginningOfParagraph(_:)):
            commit(MultiCursor.deleteToLineEdge(in: text, at: ranges, forward: false), buffer)
        case #selector(NSResponder.deleteToEndOfLine(_:)), #selector(NSResponder.deleteToEndOfParagraph(_:)):
            commit(MultiCursor.deleteToLineEdge(in: text, at: ranges, forward: true), buffer)
        case #selector(NSResponder.transpose(_:)):
            commit(MultiCursor.transpose(in: text, at: ranges), buffer)
        case #selector(NSResponder.insertBacktab(_:)):
            commit(MultiCursor.outdent(in: text, at: ranges, width: buffer.indentSettings.indentWidth), buffer)
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)),
             #selector(NSResponder.deleteWordBackward(_:)), #selector(NSResponder.deleteWordForward(_:)):
            let forward = selector == #selector(NSResponder.deleteForward(_:)) || selector == #selector(NSResponder.deleteWordForward(_:))
            let word = selector == #selector(NSResponder.deleteWordBackward(_:)) || selector == #selector(NSResponder.deleteWordForward(_:))
            let settings = buffer.indentSettings
            commit(MultiCursor.delete(in: text, at: ranges, forward: forward, word: word) { r in
                if let e = buffer.pairBackspaceEdit(r, enabled: CompletionPreferences.autoPair) { return e }
                return Indent.backspace(in: text as String, selection: r, settings: settings).map { MultiCursor.Edit(range: $0.range, text: $0.replacement, caret: $0.selection) }
            }, buffer)
        case #selector(NSResponder.insertNewline(_:)):
            commit(MultiCursor.fanOut(ranges) { r in
                let e = buffer.newlineEdit(r)
                return MultiCursor.Edit(range: e.range, text: e.replacement, caret: e.selection)
            }, buffer)
        case #selector(NSResponder.insertTab(_:)):
            commit(MultiCursor.insert(buffer.indentSettings.unit(for: ""), at: ranges), buffer)
        default:
            return false
        }
        return true
    }

    // MARK: Pasteboard

    func multiCopy() -> Bool {
        let ranges = allRanges
        guard hasExtras, ranges.contains(where: { $0.length > 0 }) else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MultiCursor.copied(string as NSString, ranges), forType: .string)
        return true
    }

    func multiCut() -> Bool {
        guard multiCopy(), let buffer = multi.buffer?() else { return hasExtras }
        commit(MultiCursor.insert("", at: allRanges), buffer)
        return true
    }

    func multiPaste() -> Bool {
        guard hasExtras, let s = NSPasteboard.general.string(forType: .string), let buffer = multi.buffer?() else { return false }
        commit(MultiCursor.paste(s, at: allRanges), buffer)
        return true
    }

    // MARK: Adding cursors

    @objc func addCaretAbove(_ sender: Any?) { addCaretOnAdjacentLine(up: true) }
    @objc func addCaretBelow(_ sender: Any?) { addCaretOnAdjacentLine(up: false) }

    private func addCaretOnAdjacentLine(up: Bool) {
        let text = string as NSString
        let all = allRanges
        let edge = up ? all.first! : all.last!
        guard let p = MultiCursor.caretOnAdjacentLine(in: text, from: up ? edge.location : NSMaxRange(edge), up: up) else { return NSSound.beep() }
        setCursors(all + [NSRange(location: p, length: 0)], primary: NSRange(location: p, length: 0))
    }

    @objc func selectNextOccurrence(_ sender: Any?) {
        guard let r = MultiCursor.selectNext(in: string as NSString, selected: allRanges, primary: selectedRange()) else { return NSSound.beep() }
        setCursors(r.ranges, primary: r.primary)
    }

    @objc func selectAllOccurrences(_ sender: Any?) {
        guard let r = MultiCursor.selectAll(in: string as NSString, selected: allRanges, primary: selectedRange()) else { return NSSound.beep() }
        setCursors(r.ranges, primary: r.primary)
    }

    /// A caret at `i`, or off again when there is one already; the new caret becomes the primary.
    private func toggleCaret(at i: Int) {
        let here = NSRange(location: i, length: 0)
        if let k = multi.extras.firstIndex(where: { $0.range == here }) {
            var e = multi.extras
            e.remove(at: k)
            setExtras(e)
        } else if selectedRange() == here, let last = multi.extras.last {
            setExtras(Array(multi.extras.dropLast()))
            setSelectedRange(last.range)
        } else {
            setCursors(allRanges + [here], primary: here)
        }
    }

    /// ⌥-click adds a caret, ⌥-drag makes a column selection, ⌃⇧-click adds a caret; any other click drops the extras.
    /// True when the click was handled here.
    func multiMouseDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let start = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if mods == [.control, .shift] { toggleCaret(at: start); return true }
        guard mods == .option else { clearExtras(); return false }
        let text = string as NSString
        let keep = allRanges                      // a plain ⌥-click adds to them; a drag starts a new column
        var dragged = false
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true), e.type != .leftMouseUp {
            dragged = true
            let end = characterIndexForInsertion(at: convert(e.locationInWindow, from: nil))
            let col = MultiCursor.column(in: text, from: start, to: end)
            setCursors(col, primary: col.last ?? NSRange(location: end, length: 0))
            autoscroll(with: e)
        }
        if !dragged { setExtras(MultiCursor.merge(keep).map { MultiCursor.Sel($0) }); toggleCaret(at: start) }
        return true
    }
}

extension DecorationView {
    /// The extra cursors: their selections; the carets are layers (`updateExtraCarets`).
    func drawMultiCursors(tv: NSTextView, tlm: NSTextLayoutManager, tcs: NSTextContentStorage, viewport: NSTextRange, origin: NSPoint) {
        guard let tv = tv as? EditorTextView, tv.hasExtras else { return }
        let length = tcs.textStorage?.length ?? 0
        let lo = tcs.offset(of: viewport.location), hi = tcs.offset(of: viewport.endLocation)
        for s in tv.multi.extras where NSMaxRange(s.range) <= length && NSMaxRange(s.range) >= lo && s.range.location <= hi {
            if s.range.length > 0 { drawSelection(s.range, tv: tv, tlm: tlm, tcs: tcs, viewport: viewport, origin: origin) }
        }
    }
}

/// Edit > Select Next Occurrence, Select All Occurrences and the caret-adding commands (`AppCommands.multiCursor`).
struct MultiCursorCommands: Commands {
    @ObservedObject private var shortcuts = ShortcutStore.shared   // rebuilds the menu when a shortcut changes

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            AppCommands.items(AppCommands.multiCursor())
        }
    }
}
