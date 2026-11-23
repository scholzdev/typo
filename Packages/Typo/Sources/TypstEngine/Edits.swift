import Foundation

/// Monotonic across all files of one project. Edit n happened after every edit < n.
public struct Seq: Comparable, Hashable, Sendable {
    public let raw: UInt64
    public init(raw: UInt64) { self.raw = raw }
    public static func < (a: Seq, b: Seq) -> Bool { a.raw < b.raw }
}

/// One mutation of one file, in UTF-16 units of the pre-edit text.
public struct Edit: Sendable {
    public let seq: Seq
    public let file: RelPath
    public let range: NSRange          // pre-edit range that was replaced
    public let replacement: String
    public let newLength: Int          // file's UTF-16 length after the edit (mirror integrity check)
    public init(seq: Seq, file: RelPath, range: NSRange, replacement: String, newLength: Int) { self.seq = seq; self.file = file; self.range = range; self.replacement = replacement; self.newLength = newLength }
}

/// One replacement in a file's current text (UTF-16 range).
public struct Replacement: Sendable, Equatable {
    public var range: NSRange
    public var text: String
    public init(range: NSRange, text: String) { self.range = range; self.text = text }
}
