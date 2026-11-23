import AppKit
import TypoKit

/// Tab stops of the last inserted snippet: Tab / Shift-Tab between them, mirrored typing, a subtle highlight.
/// The session ends on an edit outside the stops, Esc, undo/redo, a buffer switch, a selection outside the stops, or after the last Tab.
extension EditorView.Coordinator {
    func beginSnippetSession(_ snippet: Snippet, at start: Int) {
        guard snippet.needsSession, let tv = textView else { return }
        var session = SnippetSession(snippet: snippet, insertedAt: start)
        _ = session.select(tv.selectedRange())
        snippetSession = session
        pendingEdit = nil
        updateSnippetHighlight()
    }

    func endSnippetSession() {
        guard snippetSession != nil else { return }
        snippetSession = nil
        pendingEdit = nil
        updateSnippetHighlight()
    }

    /// Records the user's edit for `feedSnippetSession`; undo and redo end the session.
    func noteEdit(_ range: NSRange, _ replacement: String?) {
        guard snippetSession != nil, !accepting else { return }
        if let um = buffer?.undoManager, um.isUndoing || um.isRedoing { return endSnippetSession() }
        pendingEdit = replacement.map { (range, $0.utf16.count) }
    }

    /// Called from `textDidChange`: shifts the stops for the user's edit and writes the mirrored text into the other occurrences
    /// (inside the keystroke's undo group, without pairing or completion side effects).
    func feedSnippetSession(in tv: NSTextView?) {
        guard var session = snippetSession, !accepting else { return }
        guard let tv, let edit = pendingEdit else { return endSnippetSession() }       // undo, redo or an edit we did not see
        pendingEdit = nil
        guard let replacements = session.textDidChange(at: edit.range, replacementLength: edit.length, in: tv.string as NSString) else { return endSnippetSession() }
        snippetSession = session
        if !replacements.isEmpty {
            var caret = edit.range.location + edit.length
            accepting = true
            for r in replacements {                     // last location first, so the ranges stay valid
                tv.insertText(r.text, replacementRange: r.range)
                if r.range.location < edit.range.location { caret += (r.text as NSString).length - r.range.length }
            }
            tv.setSelectedRange(NSRange(location: caret, length: 0))
            accepting = false
        }
        updateSnippetHighlight()
    }

    /// The caret left the stops (click, arrow keys): the session is over. Moving between stops makes that one current.
    func checkSnippetSelection() {
        guard var session = snippetSession, !accepting, !programmatic, pendingEdit == nil, let tv = textView else { return }
        if session.select(tv.selectedRange()) {
            snippetSession = session
            updateSnippetHighlight()
        } else {
            endSnippetSession()
        }
    }

    /// Tab / Shift-Tab inside a stop: selects the next / previous one, after the last the exit. False when no session applies.
    func jumpSnippetStop(forward: Bool, in view: NSTextView) -> Bool {
        guard var session = snippetSession else { return false }
        guard session.select(view.selectedRange()), let target = forward ? session.next() : session.previous() else {
            endSnippetSession()
            return false
        }
        snippetSession = session.isFinished ? nil : session
        selectProgrammatically(target, in: view)
        updateSnippetHighlight()
        return true
    }

    /// Stops are tinted with the accent colour (rendering attributes: no storage edit, diagnostics use underlines only).
    func updateSnippetHighlight() {
        guard let tv = textView, let tlm = tv.textLayoutManager, let tcs = tv.textContentStorage else { return }
        tlm.removeRenderingAttribute(.backgroundColor, for: tcs.documentRange)
        guard let session = snippetSession else { return }
        let length = tv.textStorage?.length ?? 0
        let current = Set(session.current.map(\.location))
        for r in session.allStops where r.length > 0 && NSMaxRange(r) <= length {
            guard let range = tcs.textRange(for: r) else { continue }
            let alpha: CGFloat = current.contains(r.location) ? 0.32 : 0.15
            tlm.setRenderingAttributes([.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(alpha)], for: range)
        }
    }
}
