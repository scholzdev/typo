import Foundation

/// The language a Typst source declares with `#set text(lang: "de", region: "CH")` or `#text(lang: "fr")[...]`.
/// Used to point the spell checker at the right dictionary.
public struct TextLanguage: Equatable, Sendable {
    public var lang: String
    public var region: String?
    public init(lang: String, region: String?) { self.lang = lang; self.region = region }

    /// `de_CH` style identifier when there is a region.
    public var identifier: String { region.map { "\(lang)_\($0)" } ?? lang }

    /// A stretch of the source that has `language`; a later section wins over an earlier one where they overlap.
    public struct Section: Equatable, Sendable {
        public var range: NSRange
        public var language: TextLanguage
    }

    /// shortcut: a `#set text` applies to the end of the file (not just its enclosing block), upgrade when scoped sets matter.
    public static func sections(in source: String, inherited: TextLanguage? = nil) -> [Section] {
        let u = Array(source.utf16)
        var out: [Section] = []
        if let inherited { out.append(Section(range: NSRange(location: 0, length: u.count), language: inherited)) }
        var i = 0
        var current = inherited
        while i < u.count {
            switch u[i] {
            case 0x2F where i + 1 < u.count && u[i + 1] == 0x2F:                   // //
                while i < u.count, u[i] != 0x0A { i += 1 }
            case 0x2F where i + 1 < u.count && u[i + 1] == 0x2A:                   // /* */
                var depth = 1; i += 2
                while i < u.count, depth > 0 {
                    if u[i] == 0x2F, i + 1 < u.count, u[i + 1] == 0x2A { depth += 1; i += 2 }
                    else if u[i] == 0x2A, i + 1 < u.count, u[i + 1] == 0x2F { depth -= 1; i += 2 }
                    else { i += 1 }
                }
            case 0x22: _ = string(u, &i)
            case 0x23:                                                              // #
                var j = i + 1
                var k = j
                let isSet = word(u, &k) == "set"
                if isSet { j = k; skipSpace(u, &j) }
                guard word(u, &j) == "text", j < u.count, u[j] == 0x28 else { i += 1; continue }
                guard let args = arguments(u, open: j) else { i += 1; continue }
                let next = args.close + 1
                if args.lang == nil && args.region == nil { i = next; continue }
                let lang = args.lang ?? current?.lang ?? "en"
                let region = args.lang == nil ? (args.region ?? current?.region) : args.region
                let value = TextLanguage(lang: lang, region: region)
                if isSet {
                    out.append(Section(range: NSRange(location: next, length: u.count - next), language: value))
                    current = value
                } else if next < u.count, u[next] == 0x5B, let close = matching(u, open: next) {   // #text(lang: ..)[content]
                    out.append(Section(range: NSRange(location: next + 1, length: close - next - 1), language: value))
                }
                i = next
                continue
            default: break
            }
            i += 1
        }
        return out
    }

    /// The language in force at `offset`, nil when the source declares none there.
    public static func at(_ offset: Int, in source: String, inherited: TextLanguage? = nil) -> TextLanguage? {
        sections(in: source, inherited: inherited).last { NSLocationInRange(offset, $0.range) }?.language
    }

    /// The language of the first top-level `#set text(lang:)`: what an included file without its own inherits.
    public static func documentDefault(in source: String) -> TextLanguage? {
        sections(in: source).first { $0.range.upperBound == source.utf16.count }?.language
    }

    // MARK: scanning

    private static func isIdent(_ c: UInt16) -> Bool { (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x5F || c == 0x2D }

    private static func word(_ u: [UInt16], _ i: inout Int) -> String {
        let s = i
        while i < u.count, isIdent(u[i]) { i += 1 }
        return String(utf16CodeUnits: Array(u[s..<i]), count: i - s)
    }

    private static func skipSpace(_ u: [UInt16], _ i: inout Int) { while i < u.count, u[i] == 0x20 || u[i] == 0x09 || u[i] == 0x0A { i += 1 } }

    /// Reads the string literal at `i` (on the opening quote); leaves `i` after the closing one.
    @discardableResult private static func string(_ u: [UInt16], _ i: inout Int) -> String {
        i += 1
        let s = i
        while i < u.count, u[i] != 0x22 { i += u[i] == 0x5C ? 2 : 1 }
        let v = String(utf16CodeUnits: Array(u[s..<min(i, u.count)]), count: min(i, u.count) - s)
        i += 1
        return v
    }

    /// The `lang:` / `region:` string arguments of the call opening at `open`, and its closing paren.
    private static func arguments(_ u: [UInt16], open: Int) -> (lang: String?, region: String?, close: Int)? {
        var i = open + 1, depth = 1
        var lang: String?, region: String?
        while i < u.count {
            let c = u[i]
            if c == 0x22 { string(u, &i); continue }
            if c == 0x28 || c == 0x5B || c == 0x7B { depth += 1 }
            else if c == 0x29 || c == 0x5D || c == 0x7D { depth -= 1; if depth == 0 { return (lang, region, i) } }
            else if depth == 1, isIdent(c), !isIdent(u[i - 1]) {
                let name = word(u, &i)
                if name == "lang" || name == "region" {
                    skipSpace(u, &i)
                    if i < u.count, u[i] == 0x3A { i += 1; skipSpace(u, &i) }
                    else { continue }
                    if i < u.count, u[i] == 0x22 { let v = string(u, &i); if name == "lang" { lang = v } else { region = v } }
                }
                continue
            }
            i += 1
        }
        return nil
    }

    /// The closer of the `[` at `open`, skipping strings.
    private static func matching(_ u: [UInt16], open: Int) -> Int? {
        var i = open + 1, depth = 1
        while i < u.count {
            if u[i] == 0x22 { string(u, &i); continue }
            if u[i] == 0x5C { i += 2; continue }
            if u[i] == 0x5B { depth += 1 } else if u[i] == 0x5D { depth -= 1; if depth == 0 { return i } }
            i += 1
        }
        return nil
    }
}
