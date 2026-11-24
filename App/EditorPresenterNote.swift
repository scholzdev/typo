import AppKit
import TypoKit

extension EditorView.Coordinator {
    /// Add Presenter Note: an empty note on a line of its own after the caret's line, the caret between its quotes.
    func addPresenterNote() {
        guard let tv = textView, let buffer, buffer.isTypst, !readOnly else { return NSSound.beep() }
        let edit = PresenterNotes.insertion(of: PresenterNotes.written(""), afterLineAt: tv.selectedRange().location, in: tv.string)
        buffer.apply([edit], actionName: String(localized: "Add Presenter Note"))
        let caret = NSRange(location: edit.range.location + 1 + PresenterNotes.emptyCaretOffset, length: 0)
        tv.window?.makeFirstResponder(tv)
        tv.setSelectedRange(caret)
        tv.scrollRangeToVisible(caret)
        project?.preview.showsNotes = true
    }
}
