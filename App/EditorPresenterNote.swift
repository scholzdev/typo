import AppKit
import TypoKit

extension EditorView.Coordinator {
    /// Add Presenter Note: an empty note card on a line of its own after the caret's line, ready to type in.
    func addPresenterNote() {
        guard let buffer, buffer.isTypst, !readOnly else { return NSSound.beep() }
        noteCards.add()
        // The strip comes with the first note; a deck's own Hide choice turns back to automatic, not to always on.
        project?.preview.automaticNotes = true
        if project?.preview.showsNotes == false { project?.preview.showsNotes = nil }
    }
}
