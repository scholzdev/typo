import Foundation

public enum PDFStandard: UInt8, Sendable, CaseIterable {
    case plain = 0, pdfA2b = 1, pdfA3b = 2, ua1 = 3

    public var title: String {
        switch self {
        case .plain: "PDF"
        case .pdfA2b: "PDF/A-2b"
        case .pdfA3b: "PDF/A-3b"
        case .ua1: String(localized: "PDF/UA-1 (Accessible)", bundle: .module)
        }
    }
}

/// Words of one heading's section; `level` 0 and an empty title mark the text before the first heading.
public struct SectionWords: Codable, Sendable, Equatable {
    public let title: String
    public let level: Int
    public let words: Int
    public let page: Int
    public init(title: String, level: Int, words: Int, page: Int) { self.title = title; self.level = level; self.words = words; self.page = page }
}

/// What the Rust parse found, with no `Tb*` types so the model can be built and tested anywhere.
public struct RawTable {
    public struct Arg { public var name: String; public var value: String; public var shape: Int; public var items: [String] }    // shape: 0 other, 1 int, 2 array, 3 alignment
    public struct Cell { public var isContent: Bool; public var source: String; public var inner: String }
    public var callee: String
    public var range: NSRange
    public var unsupported: String?
    public var args: [Arg] = []
    public var headerArgs: [Arg] = []
    public var header: [Cell]?
    public var cells: [Cell] = []
}

/// One entry of typst's `sym` or `emoji` module, variants included (`arrow.r.long`).
public struct TypstSymbol: Identifiable, Sendable, Hashable {
    public let name: String
    public let text: String
    public let isEmoji: Bool
    public var id: String { (isEmoji ? "emoji." : "sym.") + name }
}

public struct BibEntry: Identifiable, Sendable, Equatable {
    public let key: String
    public let title: String
    public let authors: String
    public let year: Int?
    public let kind: String
    public var id: String { key }

    public init(key: String, title: String, authors: String, year: Int?, kind: String) {
        self.key = key
        self.title = title
        self.authors = authors
        self.year = year
        self.kind = kind
    }
}

/// One suggested change for a diagnostic: edits per file, applied together.
public struct QuickFix: Sendable, Equatable, Identifiable {
    public let title: String
    public let edits: [RelPath: [Replacement]]
    /// Where to put the selection once the edits are applied (in the one edited file); nil leaves it.
    public var selection: NSRange?
    public init(title: String, edits: [RelPath: [Replacement]], selection: NSRange? = nil) { self.title = title; self.edits = edits; self.selection = selection }
    public var id: String { title }
}
