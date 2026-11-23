import Foundation

public enum FontSource: Int, Sendable { case system, project, builtin }
public enum FontDesign: Sendable { case serif, sans, other }

/// One style of a family, as the platform lists it.
public struct FontFace: Hashable, Sendable {
    public var family: String
    public var style: String
    public var weight: Int          // CSS scale, 100...900
    public var italic: Bool
    public var monospaced: Bool
    public var design: FontDesign
    public var source: FontSource

    public init(family: String, style: String, weight: Int = 400, italic: Bool = false, monospaced: Bool = false,
                design: FontDesign = .other, source: FontSource = .system) {
        self.family = family; self.style = style; self.weight = weight; self.italic = italic
        self.monospaced = monospaced; self.design = design; self.source = source
    }

    /// CoreText's weight trait (-1...1) on the CSS scale, by the nearest of its named stops.
    public static func weight(fromTrait t: Double) -> Int {
        let stops: [(Double, Int)] = [(-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900)]
        return stops.min { abs($0.0 - t) < abs($1.0 - t) }!.1
    }

    /// CoreText's class mask (the top nibble of the symbolic traits): the serif classes are 1-5 and 7, sans is 8.
    public static func design(fromClass c: Int) -> FontDesign {
        switch c { case 1...5, 7: .serif; case 8: .sans; default: .other }
    }
}

public struct FontFamily: Identifiable, Hashable, Sendable {
    public var name: String
    public var source: FontSource
    public var faces: [FontFace]
    public var id: String { name }

    public var isMonospaced: Bool { faces.contains(where: \.monospaced) }
    public var design: FontDesign { faces.first(where: { $0.weight == 400 && !$0.italic })?.design ?? faces.first?.design ?? .other }
    public var weights: [Int] { Array(Set(faces.map(\.weight))).sorted() }
    public var hasItalic: Bool { faces.contains(where: \.italic) }
}

public enum FontCategory: String, CaseIterable, Sendable {
    case all, serif, sans, mono, project
    public var title: String { rawValue.capitalized }
}

/// The font browser's pure part: grouping, classifying and the `font:` source text.
public enum FontCatalog {
    /// The families Typst ships; they are usable on every machine.
    public static let builtInNames = ["Libertinus Serif", "Libertinus Math", "New Computer Modern", "New Computer Modern Math", "DejaVu Sans Mono"]

    public static func weightName(_ w: Int) -> String {
        switch w {
        case ..<150: "Thin"
        case ..<250: "Extra Light"
        case ..<350: "Light"
        case ..<450: "Regular"
        case ..<550: "Medium"
        case ..<650: "Semibold"
        case ..<750: "Bold"
        case ..<850: "Extra Bold"
        default: "Black"
        }
    }

    public static func group(_ faces: [FontFace]) -> [FontFamily] {
        Dictionary(grouping: faces, by: \.family)
            .map { FontFamily(name: $0.key, source: $0.value[0].source, faces: $0.value.sorted { ($0.weight, $0.italic ? 1 : 0) < ($1.weight, $1.italic ? 1 : 0) }) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Keeps the system families Typst lists, spelled as Typst spells them (the names `font:` matches). Only the built-in
    /// families get stand-in faces when the platform has none. Without Typst's names (no engine yet) every system family
    /// stays, with the built-ins added.
    public static func reconcile(system: [FontFamily], typstNames: [String]) -> [FontFamily] {
        let builtIn = Set(builtInNames.map { $0.lowercased() })
        let byName = Dictionary(system.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        func make(_ name: String, _ found: FontFamily?) -> FontFamily {
            var f = found ?? FontFamily(name: name, source: .system, faces: [])
            f.name = name
            if builtIn.contains(name.lowercased()) {
                f.source = .builtin
                if f.faces.isEmpty { f.faces = placeholderFaces(name) }
            }
            return f
        }
        guard !typstNames.isEmpty else {
            let extra = builtInNames.filter { byName[$0.lowercased()] == nil }
            return (system.map { make($0.name, $0) } + extra.map { make($0, nil) }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return typstNames.filter { !$0.hasPrefix(".") }.map { make($0, byName[$0.lowercased()]) }
    }

    /// Regular, bold and italics for a built-in family without platform data.
    private static func placeholderFaces(_ name: String) -> [FontFace] {
        let mono = name.contains("Mono"), design: FontDesign = mono ? .sans : name.contains("Math") ? .other : .serif
        return [(400, false), (700, false), (400, true), (700, true)].map {
            FontFace(family: name, style: weightName($0.0) + ($0.1 ? " Italic" : ""), weight: $0.0, italic: $0.1, monospaced: mono, design: design, source: .builtin)
        }
    }

    /// The families in display order; a system family of a project family's name yields to it, since the project's is the one Typst uses.
    public static func merge(project: [FontFamily], system: [FontFamily]) -> [FontFamily] {
        let own = Set(project.map { $0.name.lowercased() })
        return project + system.filter { !own.contains($0.name.lowercased()) }
    }

    public static func filter(_ families: [FontFamily], query: String, category: FontCategory) -> [FontFamily] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return families.filter { f in
            guard q.isEmpty || f.name.localizedCaseInsensitiveContains(q) else { return false }
            return switch category {
            case .all: true
            case .serif: f.design == .serif && !f.isMonospaced
            case .sans: f.design == .sans && !f.isMonospaced
            case .mono: f.isMonospaced
            case .project: f.source == .project
            }
        }
    }

    // MARK: Source text

    private static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The value after `font:`: a string for one family, a fallback list for several.
    public static func value(_ names: [String]) -> String {
        names.count == 1 ? quoted(names[0]) : "(" + names.map(quoted).joined(separator: ", ") + ")"
    }

    public static func setRule(_ names: [String]) -> String { "#set text(font: \(value(names)))" }

    /// The range of the `font:` value (a string or a parenthesized list) the caret (UTF-16) is in or right at the ends of.
    public static func valueRange(at caret: Int, in text: String) -> NSRange? {
        let s = text as NSString, n = s.length
        guard let re = try? NSRegularExpression(pattern: #"(?<![\w-])font\s*:\s*(?=["(])"#) else { return nil }
        for m in re.matches(in: text, range: NSRange(location: 0, length: n)) {
            let start = NSMaxRange(m.range)
            guard start <= caret else { continue }
            var i = start, depth = 0, end: Int?
            scan: while i < n {
                switch s.character(at: i) {
                case 0x22:                                     // a string: skip to its closing quote
                    i += 1
                    while i < n, s.character(at: i) != 0x22 { i += s.character(at: i) == 0x5C ? 2 : 1 }
                    if i >= n { break scan }
                    if depth == 0 { end = i + 1; break scan }
                case 0x28: depth += 1
                case 0x29:
                    depth -= 1
                    if depth == 0 { end = i + 1; break scan }
                default: break
                }
                i += 1
            }
            if let end, caret <= end { return NSRange(location: start, length: end - start) }
        }
        return nil
    }

    /// Replaces the `font:` value under the caret, else inserts a `#set text(font: …)` rule at it.
    public static func insertion(of names: [String], in text: String, caret: Int) -> Replacement? {
        guard !names.isEmpty else { return nil }
        if let r = valueRange(at: caret, in: text) { return Replacement(range: r, text: value(names)) }
        return Replacement(range: NSRange(location: caret, length: 0), text: setRule(names))
    }
}
