import Foundation
import TypstEngine

/// A color written in Typst source; `range` covers the whole literal, e.g. `rgb("#ff8800")`.
public struct ColorLiteral: Equatable, Sendable {
    public let range: NSRange
    public let red, green, blue, alpha: Double   // 0...1
}

public enum ColorLiterals {
    // shortcut: named colors and percentage rgb() are not detected, add when asked
    private static let regex = try! NSRegularExpression(pattern: #"""
        (?<![-_\p{L}\p{N}])(?:
          rgb\(\s*"\x23([0-9a-fA-F]{3,8})"\s*\)
        | rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*(\d{1,3})\s*)?\)
        | luma\(\s*(\d{1,3}%?)\s*\)
        )
        """#, options: [.allowCommentsAndWhitespace])

    public static func scan(_ text: String) -> [ColorLiteral] {
        scan(text) { TypstSyntax.tokens(in: text).map { ($0.tag, $0.range) } }
    }

    /// `tokens` is only called when the regex found something. A real literal starts in a `function` token
    /// (`rgb`); text in comments, raw blocks, strings and markup has none.
    static func scan(_ text: String, tokens: () -> [(tag: SyntaxTag, range: NSRange)]) -> [ColorLiteral] {
        let ns = text as NSString
        let found = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !found.isEmpty else { return [] }
        let functions = tokens().filter { $0.tag == .function }.map(\.range)
        return found.compactMap { m in
            guard functions.contains(where: { NSLocationInRange(m.range.location, $0) }) else { return nil }
            func group(_ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            if let hex = group(1) { return literal(m.range, hex: hex) }
            if let r = group(2).flatMap({ Int($0) }), let g = group(3).flatMap({ Int($0) }), let b = group(4).flatMap({ Int($0) }) {
                let a = group(5).flatMap { Int($0) } ?? 255
                guard [r, g, b, a].allSatisfy({ $0 <= 255 }) else { return nil }
                return ColorLiteral(range: m.range, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: Double(a) / 255)
            }
            guard let l = group(6) else { return nil }
            let v = l.hasSuffix("%") ? Double(l.dropLast()).map { $0 / 100 } : Double(l).map { $0 / 255 }
            guard let v, v <= 1 else { return nil }
            return ColorLiteral(range: m.range, red: v, green: v, blue: v, alpha: 1)
        }
    }

    private static func literal(_ range: NSRange, hex: String) -> ColorLiteral? {
        let digits = hex.compactMap { $0.hexDigitValue }
        guard [3, 4, 6, 8].contains(digits.count) else { return nil }
        let bytes = digits.count <= 4 ? digits.map { $0 * 17 } : stride(from: 0, to: digits.count, by: 2).map { digits[$0] * 16 + digits[$0 + 1] }
        let c = bytes.map { Double($0) / 255 }
        return ColorLiteral(range: range, red: c[0], green: c[1], blue: c[2], alpha: c.count == 4 ? c[3] : 1)
    }

    /// `rgb("#rrggbb")`, with the alpha pair appended when the color is not opaque.
    public static func source(red: Double, green: Double, blue: Double, alpha: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let a = byte(alpha)
        return String(format: "rgb(\"#%02x%02x%02x%@\")", byte(red), byte(green), byte(blue), a < 255 ? String(format: "%02x", a) : "")
    }
}
