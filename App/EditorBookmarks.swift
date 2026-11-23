import AppKit
import TypoKit

extension EditorView.Coordinator {
    /// 0-based lines of the shown file that carry a bookmark.
    var bookmarkedLines: Set<Int> {
        guard let project, let b = buffer else { return [] }
        return project.bookmarkedLines(in: b.path)
    }

    /// Start offsets of the bookmarked lines, for the editor's line tint.
    var bookmarkStarts: Set<Int> {
        guard let tv = textView else { return [] }
        let text = tv.string as NSString
        return Set(bookmarkedLines.map { text.lineRange(for: NSRange(location: EditorLocation.offset(ofLine: $0 + 1, in: tv.string), length: 0)).location })
    }

    /// The caret's 0-based line.
    var caretLine: Int? {
        guard let tv = textView else { return nil }
        return CodeBookmark.line(at: tv.selectedRange().location, in: tv.string as NSString)
    }

    func isBookmarked(at offset: Int) -> Bool? {
        guard let tv = textView, buffer != nil else { return nil }
        return bookmarkedLines.contains(CodeBookmark.line(at: offset, in: tv.string as NSString))
    }

    func toggleBookmark(at offset: Int) {
        guard let project, let b = buffer, let tv = textView else { return NSSound.beep() }
        project.toggleBookmark(b.path, line: CodeBookmark.line(at: offset, in: tv.string as NSString))
    }

    func toggleBookmarkAtCaret() {
        guard let tv = textView else { return NSSound.beep() }
        toggleBookmark(at: tv.selectedRange().location)
    }
}
