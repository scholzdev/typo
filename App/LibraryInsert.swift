import AppKit
import TypoKit

extension EditorView.Coordinator {
    /// Inserts a library snippet at the selection as one undoable edit: block snippets on their own lines, inline ones at the caret; selected text goes into the snippet's wrapping placeholder.
    func insertLibrary(_ s: LibrarySnippet) {
        guard let tv = textView, let buffer else { return }
        let sel = tv.selectedRange()
        let selected = sel.length > 0 ? (tv.string as NSString).substring(with: sel) : ""
        let snip = s.snippet(mode: buffer.mode(at: sel.location), selected: selected)
        if s.isBlock { insert(snip) } else { replace(sel, with: snip.text, selecting: snip.selection(insertedAt: sel.location), session: (snip, sel.location)) }
    }

    /// Inserts the image file's code at the selection (files outside the project are copied in).
    func insertLibraryImage(_ url: URL) {
        guard let tv = textView else { return }
        insertImages(.files([url]), replacing: tv.selectedRange())
    }
}
