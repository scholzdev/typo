import Foundation

/// One highlighted token of a Typst source (UTF-16 range, delimiters included: `<intro>`, `@intro`, `"a.typ"`).
public struct SyntaxToken: Sendable, Equatable {
    public let tag: SyntaxTag
    public let range: NSRange
}

/// Whole-file token scans for project-wide features (labels and references, path strings, comments), on text
/// that need not be open in an editor. Parses afresh each call.
public enum TypstSyntax {
    public static func tokens(in text: String) -> [SyntaxToken] {
        SyntaxMirror(text).spans(in: NSRange(location: 0, length: (text as NSString).length)).map { SyntaxToken(tag: $0.tag, range: $0.range) }
    }
}
