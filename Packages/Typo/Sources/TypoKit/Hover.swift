import Foundation
import TypstEngine
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

public enum Tooltip: Sendable {
    case text(AttributedString)
    case code(AttributedString)
}

public struct HoverInfo: Sendable {
    public let range: NSRange             // in the current text; anchors the panel
    public let diagnostics: [Diagnostic]
    public let tooltip: Tooltip?
    public let equation: EquationImage?
}

/// The equation under the pointer as the compiled document shows it.
public struct EquationImage: Sendable {
    public let image: CGImage
    public let size: CGSize               // points
}

/// Rendering of tooltip strings.
@MainActor public enum HoverText {
    private static let linkSchemes: Set<String> = ["http", "https", "mailto"]
    private static var size: CGFloat { Highlighter.fontSize - 1 }   // the editor size follows the setting

    private static func attributed(_ ns: NSAttributedString) -> AttributedString {
        #if canImport(AppKit)
        (try? AttributedString(ns, including: \.appKit)) ?? AttributedString(ns.string)
        #else
        (try? AttributedString(ns, including: \.uiKit)) ?? AttributedString(ns.string)
        #endif
    }

    /// Inline Markdown with paragraphs kept as newlines. typst-ide docs link to internal destinations like
    /// `$text`; only web and mail links stay links, the rest is plain text.
    public static func markdown(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var parsed = try? AttributedString(markdown: s, options: options) else { return AttributedString(s) }
        for run in parsed.runs {
            if let url = run.link, !linkSchemes.contains(url.scheme?.lowercased() ?? "") { parsed[run.range].link = nil }
        }
        let out = NSMutableAttributedString(parsed)        // the presentation intents survive the conversion
        let all = NSRange(location: 0, length: out.length)
        out.addAttributes([.font: PlatformFont.systemFont(ofSize: size), .foregroundColor: Highlighter.label], range: all)
        out.enumerateAttribute(.init("NSInlinePresentationIntent"), in: all) { value, range, _ in
            guard let raw = value as? Int else { return }
            let intent = InlinePresentationIntent(rawValue: UInt(raw))
            if intent.contains(.code) { out.addAttribute(.font, value: PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular), range: range) }
            if intent.contains(.stronglyEmphasized) { out.addAttribute(.font, value: PlatformFont.systemFont(ofSize: size, weight: .bold), range: range) }
            if intent.contains(.emphasized) { out.addAttribute(.obliqueness, value: 0.2, range: range) }
        }
        return attributed(out)
    }

    /// Typst code, monospaced and colored by the syntax mirror. The mirror parses markup, so the code is
    /// wrapped in `#{ }` to be read as code, and only the code's own range is kept.
    public static func code(_ s: String) -> AttributedString {
        let wrapped = "#{" + s + "}"
        let storage = NSTextStorage(string: wrapped)
        Highlighter.recolor(storage, SyntaxMirror(wrapped), NSRange(location: 0, length: storage.length))
        return attributed(storage.attributedSubstring(from: NSRange(location: 2, length: (s as NSString).length)))
    }
}
