import Foundation

public enum TableFill {
    public typealias RGBA = (red: Double, green: Double, blue: Double, alpha: Double)

    static let named: [String: String] = [
        "black": "000000", "gray": "aaaaaa", "silver": "dddddd", "white": "ffffff", "navy": "001f3f", "blue": "0074d9",
        "aqua": "7fdbff", "teal": "39cccc", "eastern": "239dad", "purple": "b10dc9", "fuchsia": "f012be", "maroon": "85144b",
        "red": "ff4136", "orange": "ff851b", "yellow": "ffdc00", "olive": "3d9970", "green": "2ecc40", "lime": "01ff70",
    ]

    /// Nil unless the fill is one colour: named, `rgb(…)` or `luma(…)`, then any `.lighten(n%)` / `.darken(n%)`.
    public static func color(_ fill: String) -> RGBA? {
        var base = Substring(fill.trimmingCharacters(in: .whitespaces))
        var steps: [(lighten: Bool, by: Double)] = []
        while let m = base.firstMatch(of: /\.(lighten|darken)\(\s*(\d+(?:\.\d+)?)%\s*\)$/), let p = Double(m.output.2) {
            steps.insert((m.output.1 == "lighten", min(p, 100) / 100), at: 0)
            base = base[..<m.range.lowerBound]
        }
        var c: RGBA
        if let hex = named[String(base)], let v = Int(hex, radix: 16) {
            c = (Double(v >> 16) / 255, Double(v >> 8 & 0xff) / 255, Double(v & 0xff) / 255, 1)
        } else {
            let code = "#" + base
            guard let l = ColorLiterals.scan(code).first, l.range == NSRange(location: 1, length: (code as NSString).length - 1) else { return nil }
            c = (l.red, l.green, l.blue, l.alpha)
        }
        for s in steps {
            func f(_ v: Double) -> Double { s.lighten ? v + (1 - v) * s.by : v * (1 - s.by) }
            c = (f(c.red), f(c.green), f(c.blue), c.alpha)
        }
        return c
    }
}

extension TableModel {
    public var tableFill: String? {
        for case .verbatim(let v) in slots where v.hasPrefix("fill:") { return String(v.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        return nil
    }

    /// The cell's own fill, else the table's when it is one colour (or the Striped preset's odd rows).
    public func shownFill(row: Int, column: Int) -> String? {
        if let own = fill(row: row, column: column) { return own }
        guard let t = tableFill else { return nil }
        if "fill: \(t)" == TableStyle.striped.arguments.first { return row % 2 == 1 ? "luma(240)" : nil }
        return TableFill.color(t) == nil ? nil : t
    }
}
