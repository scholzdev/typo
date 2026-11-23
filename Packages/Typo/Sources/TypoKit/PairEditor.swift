import TypstEngine
#if canImport(AppKit)
import AppKit

/// Executes auto-closing pair decisions against a text view that shows this buffer.
@MainActor public extension Buffer {
    /// True if the typed key was handled here and the text view must not insert it again.
    /// Not re-entrant: the edit it performs passes through the view's own delegate hooks.
    func handleTyped(_ s: String, replacing range: NSRange, in tv: NSTextView, enabled: Bool = true) -> Bool {
        guard !executingPair, range == tv.selectedRange() else { return false }
        let action = PairEdit.decide(typed: s, text: storage.string, selection: range, mode: syntax.mode(at: range.location),
                                     autoInserted: autoClosers, marked: tv.hasMarkedText(), enabled: enabled)
        return perform(action, in: tv)
    }

    func handleBackspace(in tv: NSTextView, enabled: Bool = true) -> Bool {
        guard !executingPair else { return false }
        return perform(PairEdit.decideBackspace(text: storage.string, selection: tv.selectedRange(),
                                                autoInserted: autoClosers, marked: tv.hasMarkedText(), enabled: enabled), in: tv)
    }

    /// Several cursors typing `s`: the single-caret pairing decision for each, as one edit set (not applied here).
    /// Pass the closers it reports to `trackAutoClosers` after applying.
    func typedAtCursors(_ s: String, _ ranges: [NSRange], enabled: Bool) -> (edits: [Replacement], ranges: [NSRange], closers: [Int]) {
        let text = storage.string
        return MultiCursor.typed(s, at: ranges) { r in
            PairEdit.decide(typed: s, text: text, selection: r, mode: self.syntax.mode(at: r.location), autoInserted: self.autoClosers, enabled: enabled)
        }
    }

    func trackAutoClosers(_ closers: [Int]) { autoClosers.formUnion(closers) }

    /// Backspace of one cursor between an auto-inserted empty pair, as a multi-cursor edit; nil otherwise.
    func pairBackspaceEdit(_ r: NSRange, enabled: Bool) -> MultiCursor.Edit? {
        guard case .edit(let range, let text, let sel, _) = PairEdit.decideBackspace(text: storage.string, selection: r, autoInserted: autoClosers, enabled: enabled) else { return nil }
        return MultiCursor.Edit(range: range, text: text, caret: sel)
    }

    private func perform(_ action: PairAction, in tv: NSTextView) -> Bool {
        switch action {
        case .none:
            return false
        case .stepOver:
            tv.setSelectedRange(NSRange(location: tv.selectedRange().location + 1, length: 0))
        case .edit(let range, let replacement, let selection, let closer):
            executingPair = true
            defer { executingPair = false }
            guard tv.shouldChangeText(in: range, replacementString: replacement) else { return true }
            tv.textStorage?.replaceCharacters(in: range, with: replacement)
            tv.didChangeText()
            tv.setSelectedRange(selection)
            if let closer { autoClosers.insert(closer) }
        }
        return true
    }
}
#endif
