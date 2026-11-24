import Foundation
import TypstEngine

/// A place the editor was at: a file and, when the visit came with a position, the offset in it.
public struct NavPlace: Equatable, Sendable {
    public var file: RelPath
    public var offset: Int?
    public init(file: RelPath, offset: Int? = nil) { self.file = file; self.offset = offset }
}

/// Xcode-style back/forward over visited places. Only navigation records a visit (a different file, or a jump of
/// more than `minLines` lines within one); the history is created at the first visit, from the file the user was on.
public struct NavigationHistory: Sendable {
    public static let minLines = 3
    private var visits: VisitHistory<NavPlace>?

    public init() {}

    public var canGoBack: Bool { visits?.canGoBack ?? false }
    public var canGoForward: Bool { visits?.canGoForward ?? false }

    /// `text` is the destination file's text, for measuring a jump within the same file; nil counts as far.
    public mutating func record(from file: RelPath?, to place: NavPlace, text: String?) {
        if visits == nil { visits = VisitHistory(start: NavPlace(file: file ?? place.file)) }
        let current = visits!.current
        if current.file == place.file {
            guard let to = place.offset else { return }       // re-selecting the open file moves nothing
            if let from = current.offset, let text, EditorLocation.lines(between: from, and: to, in: text) <= Self.minLines { return }
        }
        visits!.visit(place)
    }

    public mutating func back() -> NavPlace? { visits?.back() }
    public mutating func forward() -> NavPlace? { visits?.forward() }
}

/// Caret arithmetic for the status line. Offsets are UTF-16 (NSRange), columns and counts are characters.
public enum EditorLocation {
    public struct LineColumn: Equatable, Sendable { public var line: Int; public var column: Int }

    /// Line breaks: LF, CRLF (one break) and a lone CR. Returns the 1-based line and the UTF-16 start of that line.
    static func line(at offset: Int, in text: String) -> (line: Int, start: Int) {
        let ns = text as NSString
        let end = min(max(offset, 0), ns.length)
        var line = 1, start = 0, i = 0
        while i < end {
            let c = ns.character(at: i)
            if c == 10 || (c == 13 && !(i + 1 < ns.length && ns.character(at: i + 1) == 10)) { line += 1; start = i + 1 }
            i += 1
        }
        return (line, start)
    }

    static func lines(between a: Int, and b: Int, in text: String) -> Int {
        abs(line(at: a, in: text).line - line(at: b, in: text).line)
    }

    public static func position(of offset: Int, in text: String) -> LineColumn {
        let (line, start) = line(at: offset, in: text)
        let ns = text as NSString
        let end = min(max(offset, 0), ns.length)
        return LineColumn(line: line, column: ns.substring(with: NSRange(location: start, length: end - start)).count + 1)
    }

    /// "Line 3, Col 7", or with a selection "2 lines, 14 characters selected".
    public static func status(selection: NSRange, in text: String) -> String {
        let ns = text as NSString
        let loc = min(max(selection.location, 0), ns.length)
        guard selection.length > 0 else {
            let p = position(of: loc, in: text)
            return String(localized: "Line \(p.line), Col \(p.column)", bundle: .module)
        }
        let end = min(NSMaxRange(selection), ns.length)
        let first = line(at: loc, in: text).line
        let last = line(at: end, in: text)
        // A selection that ends at the start of a line does not include that line.
        let lines = last.line - first + (last.start == end && last.line > first ? 0 : 1)
        let chars = ns.substring(with: NSRange(location: loc, length: end - loc)).count
        let l = String(localized: "\(lines) lines", bundle: .module), c = String(localized: "\(chars) characters", bundle: .module)
        return String(localized: "\(l), \(c) selected", bundle: .module)
    }

    /// The UTF-16 offset of the start of 1-based `line`, clamped to the first and last line.
    public static func offset(ofLine line: Int, in text: String) -> Int {
        let ns = text as NSString
        var current = 1, i = 0
        while current < line, i < ns.length {
            let c = ns.character(at: i)
            if c == 10 || (c == 13 && !(i + 1 < ns.length && ns.character(at: i + 1) == 10)) { current += 1 }
            i += 1
        }
        return i
    }
}
