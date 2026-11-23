import AppKit
import TypoKit

extension EditorView.Coordinator {
    /// Move Section Up/Down: swaps the caret's section with its sibling; beeps without one.
    func moveSectionAtCaret(up: Bool) {
        guard let tv = textView, let buffer, let caret = buffer.moveSection(at: tv.selectedRange().location, up: up) else { return NSSound.beep() }
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        tv.scrollRangeToVisible(NSRange(location: caret, length: 0))
    }
}
