import Foundation
import TypstEngine
#if canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
#else
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
#endif

public struct Style {
    public var color: PlatformColor
    public var bold = false
    public var italic = false
    public init(_ color: PlatformColor, bold: Bool = false, italic: Bool = false) {
        self.color = color; self.bold = bold; self.italic = italic
    }
}

/// Writes theme attributes into a storage from the mirror's spans. Dynamic colors follow light/dark.
@MainActor public enum Highlighter {
    /// The editor theme and font size the app configured (`configure`); the defaults match the system.
    public internal(set) static var style = EditorTheme.standard
    public internal(set) static var fontSize = PlatformFont.systemFontSize
    public internal(set) static var fontFamily: String?
    public internal(set) static var fontStyles: [SyntaxTag: FontStyle] = [:]
    public internal(set) static var baseFont = font(size: PlatformFont.systemFontSize)
    static var faces = Dictionary(uniqueKeysWithValues: FontStyle.allCases.map { ($0, face($0, size: PlatformFont.systemFontSize, family: nil)) })
    static var boldFont: PlatformFont { faces[.bold]!.font }
    /// Bumped by every effective `configure`: views compare it to know they must refresh their own surfaces.
    public internal(set) static var revision = 0
    static var label: PlatformColor { style.colors.text }
    public static var base: [NSAttributedString.Key: Any] { [.font: baseFont, .foregroundColor: label] }

    /// The current theme's map; `configure` replaces it.
    public internal(set) static var theme: [SyntaxTag: Style] = EditorTheme.standard.syntax

    /// Number part and unit suffix of a Numeric token. Hex, octal and binary literals have no unit.
    static func numberSplit(_ u: [UInt16]) -> Int {
        var i = 0
        let digit = { (k: Int) in k < u.count && u[k] >= 48 && u[k] <= 57 }
        if u.count > 1, u[0] == 48, [120, 111, 98].contains(u[1]) { return u.count }
        while digit(i) { i += 1 }
        if i < u.count, u[i] == 46 { i += 1; while digit(i) { i += 1 } }
        if i < u.count, u[i] == 101 || u[i] == 69 {
            var j = i + 1
            if j < u.count, u[j] == 43 || u[j] == 45 { j += 1 }
            if digit(j) { while digit(j) { j += 1 }; i = j }
        }
        return i
    }

    /// `text` in the editor's font and colors, for a file of this name: Typst is highlighted, anything else is plain.
    public static func attributed(_ text: String, path: String) -> NSAttributedString {
        let s = NSTextStorage(string: text)
        if FileKind.isTypst(path) { recolor(s, SyntaxMirror(text), NSRange(location: 0, length: s.length)) } else { s.setAttributes(base, range: NSRange(location: 0, length: s.length)) }
        return s
    }

    /// Resets `range` to the base attributes, then paints the mirror's spans over it.
    static func recolor(_ s: NSTextStorage, _ mirror: SyntaxMirror, _ range: NSRange) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: s.length))
        guard range.length > 0 else { return }
        var spans = mirror.spans(in: range)
        let text = s.string
        for c in spans where c.tag == .comment {
            for m in TodoScan.marker.matches(in: text, range: c.range) { spans.append(SyntaxSpan(range: m.range, tag: .todo)) }
        }
        paint(s, spans, range)
    }

    /// Resets `range` to the base attributes, then paints `spans` (any that reach into it) over it.
    static func paint(_ s: NSTextStorage, _ spans: [SyntaxSpan], _ range: NSRange) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: s.length))
        guard range.length > 0 else { return }
        s.setAttributes(base, range: range)
        func add(_ tag: SyntaxTag, _ span: NSRange) {
            guard let style = theme[tag] else { return }
            let r = NSIntersectionRange(span, range)
            guard r.length > 0 else { return }
            var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: style.color]
            if style.bold || style.italic, let face = faces[FontStyle(bold: style.bold, italic: style.italic)] {
                attrs[.font] = face.font
                if face.oblique { attrs[.obliqueness] = 0.2 }
            }
            s.addAttributes(attrs, range: r)
        }
        let text = s.string as NSString
        for span in spans where NSIntersectionRange(span.range, range).length > 0 {
            if span.tag == .number {
                let u = Array(text.substring(with: span.range).utf16)
                let n = numberSplit(u)
                add(.number, NSRange(location: span.range.location, length: n))
                add(.unit, NSRange(location: span.range.location + n, length: u.count - n))
            } else {
                add(span.tag, span.range)
            }
        }
    }
}
