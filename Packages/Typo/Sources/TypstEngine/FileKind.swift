import Foundation

/// What the Files tab shows for a path: icon, and whether a click opens the editor or Quick Look.
public enum FileKind: Sendable, Equatable {
    case folder, typst, pdf, image, bib, package, data, font, other

    public init(path: String, isDirectory: Bool = false) {
        let name = (path as NSString).lastPathComponent.lowercased()
        if isDirectory { self = .folder }
        else if name == "typst.toml" { self = .package }
        else {
            switch (name as NSString).pathExtension {
            case "typ": self = .typst
            case "pdf": self = .pdf
            case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "tiff", "tif", "bmp": self = .image
            case "bib": self = .bib
            case "csv", "json", "yaml", "yml", "toml", "xml": self = .data
            case "ttf", "otf", "ttc", "woff", "woff2": self = .font
            default: self = .other
            }
        }
    }

    /// SF Symbol; nil for `.typst`, which has its own drawn glyph.
    public var symbol: String? {
        switch self {
        case .folder: "folder.fill"
        case .typst: nil
        case .pdf: "doc.richtext.fill"
        case .image: "photo"
        case .bib: "book.closed.fill"
        case .package: "shippingbox.fill"
        case .data: "tablecells"
        case .font: "textformat"
        case .other: "doc"
        }
    }

    /// Quick Look instead of the editor.
    public var isPreviewOnly: Bool { self == .pdf || self == .image }
}

extension FileKind {
    /// Text files the editor opens, the search covers, and the compiler may read: the spec's list
    /// (.typ .bib .toml .csv .json .yaml .yml .txt .md .xml). SVG is an image here, not text.
    public static func isText(_ path: String) -> Bool {
        ["typ", "bib", "toml", "csv", "json", "yaml", "yml", "txt", "md", "xml"].contains((path as NSString).pathExtension.lowercased())
    }

    /// Highlighting is only for Typst; every other text file is plain.
    public static func isTypst(_ path: String) -> Bool { (path as NSString).pathExtension.lowercased() == "typ" }
}
