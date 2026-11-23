import Foundation
import TypstEngine

/// A ready-made building block of the library (⇧⌘L).
public struct LibrarySnippet: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    /// One of `LibrarySnippets.categories`.
    public let category: String
    /// SF Symbol name for the tile.
    public let symbol: String
    /// Markup-mode source in `Snippet` syntax, starting with "#" for function calls.
    public let apply: String
    /// Goes on its own lines (`TableCode.place`) rather than inline at the caret.
    public let isBlock: Bool
    /// Which placeholder a selected text replaces (wraps).
    public let selectionStop: Int

    public init(id: String, title: String, summary: String, category: String, symbol: String, apply: String, isBlock: Bool, selectionStop: Int = 0) {
        self.id = id; self.title = title; self.summary = summary; self.category = category; self.symbol = symbol
        self.apply = apply; self.isBlock = isBlock; self.selectionStop = selectionStop
    }

    /// The code for a caret in `mode`: code mode drops a leading "#", math mode the outer `$` delimiters (and a trailing label);
    /// a non-empty `selected` text replaces the `selectionStop`th placeholder, which stays selected.
    public func snippet(mode: SyntaxMode, selected: String = "") -> Snippet {
        var source = apply
        switch mode {
        case .code where source.hasPrefix("#"): source.removeFirst()
        case .math:
            if let m = source.wholeMatch(of: /\$ ?(.*?) ?\$( <.*>)?/.dotMatchesNewlines()) { source = String(m.output.1) }
        default: break
        }
        let parsed = Snippet.parse(source)
        guard !selected.isEmpty, parsed.placeholders.indices.contains(selectionStop) else { return parsed }
        let target = parsed.placeholders[selectionStop]
        let delta = (selected as NSString).length - target.length
        let text = (parsed.text as NSString).replacingCharacters(in: target, with: selected)
        let stops = parsed.placeholders.enumerated().map { i, r in
            i == selectionStop ? NSRange(location: r.location, length: r.length + delta)
                : NSRange(location: i > selectionStop ? r.location + delta : r.location, length: r.length)
        }
        return Snippet(text: text, placeholders: stops, groups: parsed.groups)
    }

    /// Text for dragging: placeholders resolved to their defaults.
    public var plainText: String { Snippet.parse(apply).text }
}

/// The library's snippet catalog (⇧⌘L).
public enum LibrarySnippets {
    public static let categories = ["Text", "Figures", "Math", "Layout", "Document"]

    private static func s(_ id: String, _ title: String, _ category: String, _ symbol: String, _ summary: String, _ apply: String, block: Bool = true, stop: Int = 0) -> LibrarySnippet {
        LibrarySnippet(id: id, title: title, summary: summary, category: category, symbol: symbol, apply: apply, isBlock: block, selectionStop: stop)
    }

    private static let cells = "[${}], [${}], [${}]"

    public static let all: [LibrarySnippet] = [
        s("heading", "Heading", "Text", "textformat.size", "A top-level section heading.", "= ${Title}"),
        s("subheading", "Subheading", "Text", "textformat.size.smaller", "A second-level heading.", "== ${Title}"),
        s("bullet-list", "Bullet List", "Text", "list.bullet", "An unordered list.", "- ${}\n- ${}"),
        s("numbered-list", "Numbered List", "Text", "list.number", "An automatically numbered list.", "+ ${}\n+ ${}"),
        s("term-list", "Term List", "Text", "list.bullet.indent", "A list of terms with their descriptions.", "/ ${Term}: ${Description}"),
        s("strong", "Strong", "Text", "bold", "Bold text for emphasis.", "*${text}*", block: false),
        s("emphasis", "Emphasis", "Text", "italic", "Italic text for emphasis.", "_${text}_", block: false),
        s("footnote", "Footnote", "Text", "text.append", "A note at the bottom of the page.", "#footnote[${}]", block: false),
        s("link", "Link", "Text", "link", "A hyperlink with its own text.", "#link(\"${https://typst.app}\")[${text}]", block: false, stop: 1),
        s("reference", "Reference", "Text", "at", "A reference to a labeled element.", "@${label}", block: false),
        s("quote", "Quote", "Text", "quote.opening", "A block quote with an attribution.", "#quote(block: true, attribution: [${Author}])[\n  ${}\n]", stop: 1),
        s("raw-inline", "Inline Code", "Text", "chevron.left.forwardslash.chevron.right", "Monospaced code within a line.", "`${code}`", block: false),
        s("code-block", "Code Block", "Text", "curlybraces", "A block of code with syntax highlighting.", "```${typst}\n${}\n```"),

        s("figure-image", "Figure with Image", "Figures", "photo", "An image with a caption and a label to reference it.", "#figure(\n  image(\"${images/file.png}\", width: 80%),\n  caption: [${}],\n) <fig:${label}>"),
        s("table", "Table", "Figures", "tablecells", "A table with a header row and three columns.", "#table(\n  columns: 3,\n  table.header(\(cells)),\n  \(cells),\n  \(cells),\n)"),
        s("figure-table", "Figure with Table", "Figures", "tablecells.badge.ellipsis", "A table with a caption.", "#figure(\n  table(\n    columns: 3,\n    table.header(\(cells)),\n    \(cells),\n    \(cells),\n  ),\n  caption: [${}],\n)"),
        s("figure-code", "Figure with Code", "Figures", "doc.plaintext", "A code listing with a caption.", "#figure(\n  ```${typst}\n  ${}\n  ```,\n  caption: [${}],\n)"),

        s("inline-math", "Inline Math", "Math", "function", "A formula within a line of text.", "$${x}$", block: false),
        s("equation", "Equation", "Math", "sum", "A centered display equation.", "$ ${} $"),
        s("labeled-equation", "Labeled Equation", "Math", "number", "A display equation you can reference.", "$ ${} $ <eq:${label}>"),
        s("fraction", "Fraction", "Math", "divide", "A fraction of two expressions.", "$(${a}) / (${b})$", block: false),
        s("matrix", "Matrix", "Math", "square.grid.2x2", "A two by two matrix.", "$ mat(${1:1}, ${2:0}; ${3:0}, ${4:1}) $"),
        s("cases", "Cases", "Math", "curlybraces.square", "A function defined by cases.", "$ f(x) = cases(${1:1} \"if\" ${2:x > 0}, ${3:0} \"otherwise\") $"),

        s("page-break", "Page Break", "Layout", "doc.badge.plus", "Starts a new page.", "#pagebreak()"),
        s("vertical-space", "Vertical Space", "Layout", "arrow.up.and.down", "Empty space between lines.", "#v(${1em})"),
        s("horizontal-space", "Horizontal Space", "Layout", "arrow.left.and.right", "Empty space within a line.", "#h(${1em})", block: false),
        s("columns", "Columns", "Layout", "rectangle.split.2x1", "Two columns separated by a column break.", "#columns(2)[\n  ${}\n  #colbreak()\n  ${}\n]"),
        s("grid", "Grid", "Layout", "square.grid.2x2", "Content arranged in a grid of two columns.", "#grid(\n  columns: (1fr, 1fr),\n  gutter: 1em,\n  [${}],\n  [${}],\n)"),
        s("centered", "Centered", "Layout", "text.aligncenter", "Centers its content.", "#align(center)[${}]"),
        s("box", "Box", "Layout", "rectangle", "A shaded box around content.", "#block(fill: luma(240), inset: 8pt, radius: 4pt)[${}]"),

        s("outline", "Table of Contents", "Document", "list.bullet.rectangle", "An outline of all headings.", "#outline()"),
        s("bibliography", "Bibliography", "Document", "books.vertical", "The list of cited works from a .bib file.", "#bibliography(\"${refs.bib}\")"),
        s("page-setup", "Page Setup", "Document", "doc", "Paper size and margins.", "#set page(paper: \"${a4}\", margin: ${2.5cm})"),
        s("text-setup", "Text Setup", "Document", "textformat", "Font, size and language of the text.", "#set text(font: \"${New Computer Modern}\", size: ${11pt}, lang: \"${en}\")"),
        s("heading-numbering", "Heading Numbering", "Document", "textformat.123", "Numbers the headings.", "#set heading(numbering: \"${1.1}\")"),
        s("document-info", "Document Info", "Document", "info.circle", "Title and author of the document.", "#set document(title: [${Title}], author: \"${Author}\")"),
        s("import-package", "Import Package", "Document", "shippingbox", "Imports a package from the Typst universe.", "#import \"@preview/${package}:${0.1.0}\": ${*}"),
    ]

    /// Ranked like the command palette (title, then category); empty query keeps catalog order with `recent` first.
    public static func filter(_ query: String, recent: [String] = []) -> [LibrarySnippet] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = all.map { PaletteEntry(id: $0.id, title: $0.title, menu: $0.category) }
        return CommandPalette.filter(entries, query: query, recent: recent).compactMap { byID[$0.id] }
    }
}
