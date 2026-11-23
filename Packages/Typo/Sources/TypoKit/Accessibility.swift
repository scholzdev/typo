import Foundation
import TypstEngine

/// Static PDF/UA-1 pre-flight: what Typst's PDF/UA export rejects or what makes the PDF inaccessible, with source
/// ranges (the export errors mostly carry none). Hints only; conservative where the scan cannot be sure.
public enum Accessibility {
    enum Rule: CaseIterable {
        case imageAlt, headingLevel, tableHeader, documentTitle, textLanguage

        /// Messages start with this (the heading one goes on with the levels), so a fix finds its rule from the message.
        var prefix: String {
            switch self {
            case .imageAlt: "Image has no alternative text"
            case .headingLevel: "Heading level jumps"
            case .tableHeader: "Table has no header row"
            case .documentTitle: "Document has no title"
            case .textLanguage: "Text language is not set"
            }
        }
    }

    static func rule(of message: String) -> Rule? { Rule.allCases.first { message.hasPrefix($0.prefix) } }

    /// The two-letter code of the system language, for `#set text(lang:)`.
    public static var systemLanguage: String { Locale.current.language.languageCode?.identifier ?? "en" }

    private struct Finding { let file: RelPath; let range: NSRange; let message: String }

    /// Hints for the Typst files reachable from `main`, ids from `firstID`.
    static func hints(sources: [(file: RelPath, text: String)], main: RelPath, firstID: Int = 0) -> [Diagnostic] {
        let typst = sources.filter { FileKind.isTypst($0.file.raw) }
        let paths = typst.flatMap { Lint.pathArguments(in: $0.text, of: $0.file) }
        let docs = Lint.documents(typst.map(\.file), paths)
        let reachable = typst.filter { $0.file == main || docs[$0.file]?.contains(main) == true }
        var out: [Finding] = []
        var documentCalls: [(RelPath, TypstCall, Bool)] = [], langSet = false
        for (file, text) in reachable.map({ ($0.file, $0.text) }) {
            let ns = text as NSString
            let calls = TypstCalls.calls(named: ["image", "table", "figure", "document", "text"], in: text)
            func name(_ c: TypstCall) -> NSRange { NSRange(location: c.range.location, length: (c.name as NSString).length) }
            func spreads(_ c: TypstCall) -> Bool { c.args.contains { $0.name == nil && ns.substring(with: $0.range).hasPrefix("..") } }
            let altFigures = calls.filter { $0.name == "figure" && $0.arg("alt") != nil }.map(\.range)
            for c in calls {
                switch c.name {
                case "image" where c.arg("alt") == nil && !spreads(c) && !altFigures.contains { NSLocationInRange(c.range.location, $0) }:
                    out.append(Finding(file: file, range: name(c), message: Rule.imageAlt.prefix + " (PDF/UA)"))
                case "table" where !spreads(c) && !ns.substring(with: c.range).contains("table.header"):
                    out.append(Finding(file: file, range: name(c), message: Rule.tableHeader.prefix + " (PDF/UA)"))
                case "document": documentCalls.append((file, c, c.arg("title") != nil))
                case "text" where c.arg("lang") != nil && isSetRule(c, in: ns): langSet = true
                default: break
                }
            }
            var previous: Int?
            for h in headings(in: text) {
                if let p = previous, h.level > p + 1 {
                    out.append(Finding(file: file, range: h.marker, message: "\(Rule.headingLevel.prefix) from \(p) to \(h.level) (PDF/UA)"))
                }
                previous = h.level
            }
        }
        // A `#show: template` may set title and language where the scan cannot see it.
        let templated = reachable.contains { $0.text.contains(/\bshow\s*:/) }
        if !templated, let top = reachable.first(where: { $0.file == main }) {
            let first = (top.text as NSString).lineRange(for: NSRange(location: 0, length: 0))
            let line = NSRange(location: 0, length: (top.text as NSString).substring(with: first).trimmingCharacters(in: .newlines).utf16.count)
            if !documentCalls.contains(where: \.2) {
                let at = documentCalls.first.map { ($0.0, NSRange(location: $0.1.range.location, length: "document".utf16.count)) } ?? (main, line)
                out.append(Finding(file: at.0, range: at.1, message: Rule.documentTitle.prefix + " (PDF/UA)"))
            }
            if !langSet { out.append(Finding(file: main, range: line, message: Rule.textLanguage.prefix + " (PDF/UA)")) }
        }
        let sorted = out.sorted { ($0.file.raw, $0.range.location) < ($1.file.raw, $1.range.location) }
        return sorted.enumerated().map { i, f in
            Diagnostic(id: firstID + i, severity: .hint, message: f.message, hints: [], origin: .project(Location(file: f.file, range: f.range)))
        }
    }

    /// The headings of `text` as marker range and level; the syntax decides which `=` lines count.
    static func headings(in text: String) -> [(marker: NSRange, level: Int)] {
        let starts = Set(TypstSyntax.tokens(in: text).filter { $0.tag == .heading }.map(\.range.location))
        return Folding.candidates(text as NSString).filter { starts.contains($0.marker) }.map { (NSRange(location: $0.marker, length: $0.level), $0.level) }
    }

    private static func isSetRule(_ c: TypstCall, in ns: NSString) -> Bool {
        ns.substring(to: c.range.location).trimmingCharacters(in: .whitespaces).hasSuffix("set")
    }

    // MARK: Fixes

    /// The fix for the hint of `rule` at `range` in `file`, computed from the file's current `text`; empty when it cannot be applied.
    static func fixes(_ rule: Rule, file: RelPath, range: NSRange, text: String, language: String) -> [QuickFix] {
        let ns = text as NSString
        guard NSMaxRange(range) <= ns.length else { return [] }
        func fix(_ title: String, _ edit: Replacement, caret: String) -> QuickFix {
            let inside = (edit.text as NSString).range(of: caret)
            return QuickFix(title: title, edits: [file: [edit]], selection: NSRange(location: edit.range.location + inside.location + inside.length, length: 0))
        }
        func call(_ name: String) -> TypstCall? { TypstCalls.calls(named: [name], in: text).first { $0.range.location == range.location } }
        switch rule {
        case .imageAlt:
            guard let c = call("image") else { return [] }
            return [fix("Add `alt: \"\"`", addArg("alt: \"\"", to: c), caret: "alt: \"")]
        case .headingLevel:
            let all = headings(in: text)
            guard let i = all.firstIndex(where: { $0.marker == range }), i > 0 else { return [] }
            let level = all[i - 1].level + 1
            return [QuickFix(title: "Change to level \(level)", edits: [file: [Replacement(range: range, text: String(repeating: "=", count: level))]])]
        case .tableHeader:
            guard let c = call("table"), let wrap = wrapFirstRow(c, in: ns) else { return [] }
            return [QuickFix(title: "Wrap the first row in `table.header`", edits: [file: [wrap]])]
        case .documentTitle:
            if let c = call("document") { return [fix("Add `title: []`", addArg("title: []", to: c), caret: "title: [")] }
            return [fix("Insert `#set document(title: [])`", insertAfterLeadingSets("#set document(title: [])\n", in: ns), caret: "title: [")]
        case .textLanguage:
            let line = "#set text(lang: \"\(language)\")\n"
            let edit = insertAfterLeadingSets(line, in: ns)
            let at = (edit.text as NSString).range(of: language, options: .backwards)
            return [QuickFix(title: "Insert `#set text(lang: \"\(language)\")`", edits: [file: [edit]],
                             selection: NSRange(location: edit.range.location + at.location, length: at.length))]
        }
    }

    private static func addArg(_ arg: String, to c: TypstCall) -> Replacement {
        guard let last = c.args.last else { return Replacement(range: NSRange(location: c.close, length: 0), text: arg) }
        return Replacement(range: NSRange(location: NSMaxRange(last.range), length: 0), text: ", " + arg)
    }

    /// Where a new `#set` rule goes: behind the leading `#set` lines (and the blank and comment lines among them), else at the top.
    private static func insertAfterLeadingSets(_ line: String, in ns: NSString) -> Replacement {
        var i = 0, end = 0
        while i < ns.length {
            let l = ns.lineRange(for: NSRange(location: i, length: 0))
            let s = ns.substring(with: l).trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty || s.hasPrefix("//") { i = NSMaxRange(l); continue }
            guard s.hasPrefix("#set ") else { break }
            // shortcut: brackets inside strings and comments count, so a set rule with an unbalanced one in a string ends late.
            var depth = 0, j = i
            repeat {
                let part = ns.lineRange(for: NSRange(location: j, length: 0))
                for c in ns.substring(with: part).unicodeScalars {
                    if "([{".unicodeScalars.contains(c) { depth += 1 } else if ")]}".unicodeScalars.contains(c) { depth -= 1 }
                }
                j = NSMaxRange(part)
            } while depth > 0 && j < ns.length
            end = j; i = j
        }
        let lead = end > 0 && ns.character(at: end - 1) != 10 ? "\n" : ""
        return Replacement(range: NSRange(location: end, length: 0), text: lead + line)
    }

    /// `table.header(` … `)` around the first row: as many leading cells as there are columns (an integer or a parenthesised list).
    private static func wrapFirstRow(_ c: TypstCall, in ns: NSString) -> Replacement? {
        var columns = 1
        if let a = c.arg("columns") {
            let v = ns.substring(with: a.value)
            if let n = Int(v) { columns = n } else if v.hasPrefix("("), v.hasSuffix(")"), !v.dropFirst().dropLast().contains(where: { "()".contains($0) }) {
                columns = v.dropFirst().dropLast().split(separator: ",").filter { !$0.allSatisfy(\.isWhitespace) }.count
            } else { return nil }
        }
        let cells = c.args.indices.filter { c.args[$0].name == nil }
        guard columns >= 1, cells.count >= columns else { return nil }
        let row = Array(cells.prefix(columns))
        guard row.last! - row.first! == columns - 1 else { return nil }     // a named argument inside the row
        for i in row {
            let s = ns.substring(with: c.args[i].range)
            guard !s.hasPrefix(".."), !s.hasPrefix("table.hline"), !s.hasPrefix("table.vline"), !s.contains("colspan"), !s.contains("rowspan") else { return nil }
        }
        let range = NSRange(location: c.args[row.first!].range.location, length: NSMaxRange(c.args[row.last!].range) - c.args[row.first!].range.location)
        return Replacement(range: range, text: "table.header(\(ns.substring(with: range)))")
    }
}
