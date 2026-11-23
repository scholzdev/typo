import CoreGraphics
import Foundation

public enum CompletionKind: Sendable, Equatable {
    case syntax, function, type, parameter, constant, path, package, label, font
    case symbol(String)         // the glyph
}

public struct CompletionItem: Sendable, Equatable {
    public let kind: CompletionKind
    public let label: String
    public let apply: String?
    public let detail: String?

    public init(kind: CompletionKind, label: String, apply: String?, detail: String?) {
        self.kind = kind; self.label = label; self.apply = apply; self.detail = detail
    }

    /// `detail` is Markdown docs for functions. One line, first sentence, markup stripped.
    public var summary: String? {
        guard var s = detail?.split(separator: "\n\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) else { return nil }
        s = s.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.1) }
        s = s.replacing(/\b_([^_]+)_\b/) { String($0.1) }
        s = s.replacing(/[`*]/, with: "")
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let end = s.firstMatch(of: /[.!?](?=\s+[A-Z"(\[]|$)/) { s = String(s[..<end.range.upperBound]) }
        return s.isEmpty ? nil : s
    }
}

/// A point on a page of the shown document: 0-based page, pt from the page's top left.
public struct PreviewPosition: Equatable, Sendable {
    public var page: Int
    public var point: CGPoint
    public init(page: Int, point: CGPoint) { self.page = page; self.point = point }
}

public enum JumpTarget: Sendable, Equatable {
    case file(RelPath, Int)               // UTF-16 offset in the engine's text at `seq`
    case url(URL)
    case position(PreviewPosition)
}

/// `reply` is called exactly once, like CompletionRequest: nil when superseded, diverged, without
/// overlay, or the engine closed. A click that hits nothing answers with `target == nil`.
public struct ClickRequest: Sendable {
    let shown: Snapshot                   // the document the user clicked on, not the engine's newest
    let page: Int
    let point: CGPoint
    let reply: @Sendable (ClickAnswer?) -> Void
    public init(shown: Snapshot, page: Int, point: CGPoint, reply: @escaping @Sendable (ClickAnswer?) -> Void) { self.shown = shown; self.page = page; self.point = point; self.reply = reply }
}

public struct ClickAnswer: Sendable {
    public let seq: Seq
    public let target: JumpTarget?
}

public struct CursorRequest: Sendable {
    let file: RelPath
    let cursor: Int
    let reply: @Sendable (CursorAnswer?) -> Void
    public init(file: RelPath, cursor: Int, reply: @escaping @Sendable (CursorAnswer?) -> Void) { self.file = file; self.cursor = cursor; self.reply = reply }
}

public struct CursorAnswer: Sendable {
    let seq: Seq
    public let positions: [PreviewPosition]
}

/// `reply` is called exactly once, like CompletionRequest: nil when superseded, diverged, or the engine
/// closed. A cursor with nothing to show answers with `tip == nil`.
public struct HoverRequest: Sendable {
    let file: RelPath
    let cursor: Int
    var pixelsPerPoint: Float = 3        // for an equation crop
    let reply: @Sendable (HoverAnswer?) -> Void
    public init(file: RelPath, cursor: Int, pixelsPerPoint: Float = 3, reply: @escaping @Sendable (HoverAnswer?) -> Void) { self.file = file; self.cursor = cursor; self.pixelsPerPoint = pixelsPerPoint; self.reply = reply }
}

public struct HoverAnswer: Sendable {
    public let seq: Seq
    public let tip: RawTooltip?
    public let equation: RawEquation?
}

public struct RawEquation: Sendable {
    public let image: CGImage
    public let size: CGSize                      // points
    public let range: NSRange                    // the whole equation, UTF-16, valid at the answer's seq
}

public struct RawTooltip: Sendable {
    public let isCode: Bool
    public let text: String
    public let range: NSRange                    // the hovered leaf, UTF-16, valid at the answer's seq
}

/// `reply` is called exactly once, like HoverRequest: nil when superseded, diverged, or the engine closed.
public struct DefinitionRequest: Sendable {
    let file: RelPath
    let cursor: Int
    let reply: @Sendable (DefinitionAnswer?) -> Void
    public init(file: RelPath, cursor: Int, reply: @escaping @Sendable (DefinitionAnswer?) -> Void) { self.file = file; self.cursor = cursor; self.reply = reply }
}

public struct DefinitionAnswer: Sendable {
    public let seq: Seq
    public let definition: RawDefinition?
}

public struct RawDefinition: Sendable {
    public enum Kind: Sendable { case span, file, std, package }
    public let kind: Kind
    public let path: String
    public let range: NSRange                    // UTF-16 in `path`, valid at the answer's seq
    public let name: String
    public var docs = ""
    public var url = ""
    /// The function at the cursor with every parameter and its types; empty when it is no function.
    public var signature = ""
}

/// The JSON of `tb_syntax_bindings`, decoded.
public struct RawBindings: Decodable, Sendable {
    public struct Def: Decodable, Sendable {
        public let name: String
        public let range: [Int]
        public let kind: String
        public let scope: [Int]
        public let top: Bool
        public let implicit: Bool?
    }
    public struct Use: Decodable, Sendable {
        public let name: String
        public let range: [Int]
    }
    public struct Field: Decodable, Sendable {
        public let module: String
        public let name: String
        public let range: [Int]
    }
    public struct Item: Decodable, Sendable {
        public let name: String
        public let nameRange: [Int]
        let alias: String?
        public let aliasRange: [Int]?
    }
    public struct Alias: Decodable, Sendable {
        let name: String
        public let range: [Int]
    }
    public struct Import: Decodable, Sendable {
        public let path: String
        public let pathRange: [Int]
        public let items: [Item]
        public let wildcard: Bool
        public let scope: [Int]
        public let moduleAlias: Alias?
    }
    public var defs: [Def] = []
    public var uses: [Use] = []
    public var fields: [Field] = []
    public var imports: [Import] = []
    init() {}
}

/// The function whose argument list holds the caret, with every parameter and the one the argument at the caret fills.
public struct SignatureHelp: Sendable, Equatable, Decodable {
    public struct Parameter: Sendable, Equatable, Decodable {
        /// As Quick Help writes it: `size: length`, `..children: content`, `loud: false`.
        public let label: String
        public let name: String
        /// Markdown, built-ins only.
        public let docs: String
        public let positional: Bool
        public let named: Bool
        public let variadic: Bool
    }

    public let name: String
    public let params: [Parameter]
    public let active: Int?

    public var activeParameter: Parameter? { active.flatMap { params.indices.contains($0) ? params[$0] : nil } }
}

/// `reply` is called exactly once, like DefinitionRequest: nil when superseded, diverged, or the engine closed.
public struct SignatureHelpRequest: Sendable {
    let file: RelPath
    let cursor: Int
    let reply: @Sendable (SignatureHelpAnswer?) -> Void
    public init(file: RelPath, cursor: Int, reply: @escaping @Sendable (SignatureHelpAnswer?) -> Void) { self.file = file; self.cursor = cursor; self.reply = reply }
}

public struct SignatureHelpAnswer: Sendable {
    public let help: SignatureHelp?
}
