import AppKit

extension NSTextContentManager {
    func location(at offset: Int) -> NSTextLocation? { location(documentRange.location, offsetBy: offset) }

    func offset(of location: NSTextLocation) -> Int { offset(from: documentRange.location, to: location) }

    func textRange(for range: NSRange) -> NSTextRange? {
        guard let start = location(at: range.location), let end = location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }
}

extension NSTextView {
    /// The first rect of a character range in this view's coordinates (`firstRect` answers in screen space).
    func viewRect(forCharacterRange range: NSRange) -> NSRect {
        let screen = firstRect(forCharacterRange: range, actualRange: nil)
        return convert(window?.convertFromScreen(screen) ?? screen, from: nil)
    }
}
