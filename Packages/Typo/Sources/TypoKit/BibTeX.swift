import Foundation
import TypstEngine

/// One BibTeX entry, field by field, for the bibliography form. It carries its source range, so an edit rewrites only
/// this entry and leaves comments, `@string` definitions and the other entries' formatting alone.
public struct BibTeXEntry: Equatable, Sendable {
    public struct Field: Equatable, Sendable {
        public var name: String
        public var value: String
        /// A bare number, `@string` macro or `#` concatenation: written back verbatim, without braces.
        public var isRaw: Bool

        public init(name: String, value: String, isRaw: Bool = false) {
            self.name = name
            self.value = value
            self.isRaw = isRaw
        }
    }

    public var type: String
    public var key: String
    public var fields: [Field]
    /// UTF-16 range in the file, from `@` through the closing delimiter; empty for an entry not yet in the file.
    public let range: NSRange

    public init(type: String, key: String, fields: [Field], range: NSRange = NSRange(location: 0, length: 0)) {
        self.type = type
        self.key = key
        self.fields = fields
        self.range = range
    }

    public func value(_ name: String) -> String? { fields.first { $0.name.lowercased() == name }?.value }
}

public enum BibTeX {
    /// The form edits `.bib` files; hayagriva YAML stays text.
    public static func isFormEditable(_ path: String) -> Bool { (path as NSString).pathExtension.lowercased() == "bib" }

    public static let types = ["article", "book", "booklet", "inbook", "incollection", "inproceedings", "manual", "mastersthesis",
                               "misc", "online", "phdthesis", "proceedings", "techreport", "unpublished"]

    /// The fields an entry of `type` usually has, in their usual order.
    public static func typicalFields(for type: String) -> [String] {
        switch type.lowercased() {
        case "article": ["author", "title", "journal", "year", "volume", "number", "pages"]
        case "book": ["author", "editor", "title", "publisher", "year", "address", "edition"]
        case "inproceedings", "conference": ["author", "title", "booktitle", "year", "pages", "publisher"]
        case "incollection": ["author", "title", "booktitle", "editor", "publisher", "year", "pages"]
        case "inbook": ["author", "title", "chapter", "pages", "publisher", "year"]
        case "phdthesis", "mastersthesis", "thesis": ["author", "title", "school", "year"]
        case "techreport", "report": ["author", "title", "institution", "number", "year"]
        case "online": ["author", "title", "url", "urldate", "year"]
        case "misc": ["author", "title", "howpublished", "year"]
        default: ["author", "title", "year"]
        }
    }

    /// The fields the classic BibTeX styles require, as groups of alternatives (`author` or `editor`).
    public static func requiredFields(for type: String) -> [[String]] {
        switch type.lowercased() {
        case "article": [["author"], ["title"], ["journal"], ["year", "date"]]
        case "book": [["author", "editor"], ["title"], ["publisher"], ["year", "date"]]
        case "inproceedings", "conference": [["author"], ["title"], ["booktitle"], ["year", "date"]]
        case "incollection": [["author"], ["title"], ["booktitle"], ["publisher"], ["year", "date"]]
        case "inbook": [["author", "editor"], ["title"], ["chapter", "pages"], ["publisher"], ["year", "date"]]
        case "phdthesis", "mastersthesis", "thesis": [["author"], ["title"], ["school", "institution"], ["year", "date"]]
        case "techreport", "report": [["author"], ["title"], ["institution"], ["year", "date"]]
        case "online": [["title"], ["url"]]
        case "misc": []
        default: [["title"]]
        }
    }

    /// Required fields an entry of `type` lacks; a group counts as one, named by its first field.
    public static func missingRequired(type: String, present: Set<String>) -> Set<String> {
        Set(requiredFields(for: type).filter { $0.allSatisfy { !present.contains($0) } }.flatMap { $0 })
    }

    /// Fields any type may have, after its typical ones.
    public static func optionalFields(for type: String) -> [String] {
        let typical = typicalFields(for: type)
        return ["doi", "url", "isbn", "month", "note", "abstract", "keywords", "language"].filter { !typical.contains($0) }
    }

    /// The fields the Add Field menu offers, typical ones first.
    public static func suggestedFields(for type: String) -> [String] { typicalFields(for: type) + optionalFields(for: type) }

    /// A key in the usual `surname` + `year` style, e.g. `knuth1984`, from a BibTeX author list; nil without an author.
    public static func suggestedKey(author: String, year: String) -> String? {
        guard let first = author.components(separatedBy: " and ").first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        let surname = first.contains(",") ? String(first[..<first.firstIndex(of: ",")!]) : String(first.split(separator: " ").last ?? "")
        let ascii = surname.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard !ascii.isEmpty else { return nil }
        return ascii + (year.firstMatch(of: /\d{4}/).map { String($0.output) } ?? "")
    }

    /// `base`, or `base2`, `base3`… whichever is not in `used`.
    public static func uniqueKey(_ base: String, used: Set<String>) -> String {
        if !used.contains(base) { return base }
        return (2...).lazy.map { "\(base)\($0)" }.first { !used.contains($0) }!
    }

    /// Braces must pair up inside a braced value, or the entry would swallow the rest of the file.
    public static func isBalanced(_ s: String) -> Bool {
        var depth = 0
        var escaped = false
        for c in s {
            if escaped { escaped = false; continue }
            switch c {
            case "\\": escaped = true
            case "{": depth += 1
            case "}": depth -= 1; if depth < 0 { return false }
            default: break
            }
        }
        return depth == 0
    }

    // MARK: Writing

    /// The entry as the fixture files write it: one field per line, names padded so the `=` line up.
    public static func format(_ e: BibTeXEntry) -> String {
        let width = e.fields.map(\.name.count).max() ?? 0
        let lines = e.fields.map { f in
            let name = f.name.padding(toLength: width, withPad: " ", startingAt: 0)
            return "  \(name) = \(f.isRaw ? f.value : "{\(f.value)}"),\n"
        }
        return "@\(e.type){\(e.key),\n" + lines.joined() + "}"
    }

    /// Rewrites `e` in place.
    public static func update(_ e: BibTeXEntry) -> Replacement { Replacement(range: e.range, text: format(e)) }

    /// Appends `e` after a blank line.
    public static func append(_ e: BibTeXEntry, to text: String) -> Replacement {
        let lead = text.isEmpty ? "" : text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n"
        return Replacement(range: NSRange(location: (text as NSString).length, length: 0), text: lead + format(e) + "\n")
    }

    /// Removes `e` together with the blank lines after it, so its neighbours keep one blank line between them.
    public static func removal(_ e: BibTeXEntry, in text: String) -> Replacement {
        let s = text as NSString
        var end = NSMaxRange(e.range)
        while end < s.length, isSpace(s.character(at: end)) { end += 1 }
        var start = e.range.location
        if end == s.length {       // the last entry: drop the gap before it instead, keep one final newline
            while start > 0, isSpace(s.character(at: start - 1)) { start -= 1 }
            return Replacement(range: NSRange(location: start, length: end - start), text: start > 0 ? "\n" : "")
        }
        return Replacement(range: NSRange(location: start, length: end - start), text: "")
    }

    // MARK: Reading

    /// The regular entries of `text` in file order. `@comment`, `@string`, `@preamble` and entries that don't parse are
    /// skipped; they stay in the file untouched.
    public static func entries(in text: String) -> [BibTeXEntry] {
        var scanner = EntryScanner(Array(text.utf16))
        var result: [BibTeXEntry] = []
        while let e = scanner.nextEntry() { if let e { result.append(e) } }
        return result
    }

    private static func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }

    private struct EntryScanner {
        let u: [UInt16]
        var i = 0

        init(_ u: [UInt16]) { self.u = u }

        private static let at = UInt16(UInt8(ascii: "@")), lbrace = UInt16(UInt8(ascii: "{")), rbrace = UInt16(UInt8(ascii: "}"))
        private static let lparen = UInt16(UInt8(ascii: "(")), rparen = UInt16(UInt8(ascii: ")")), comma = UInt16(UInt8(ascii: ","))
        private static let equals = UInt16(UInt8(ascii: "=")), quote = UInt16(UInt8(ascii: "\"")), hash = UInt16(UInt8(ascii: "#"))
        private static let backslash = UInt16(UInt8(ascii: "\\"))

        private func string(_ r: Range<Int>) -> String { String(decoding: u[r], as: UTF16.self) }

        private mutating func skipSpace() { while i < u.count, BibTeX.isSpace(u[i]) { i += 1 } }

        private mutating func identifier() -> String {
            let start = i
            while i < u.count, let s = Unicode.Scalar(u[i]), s.isASCII,
                  s.properties.isAlphabetic || ("0"..."9").contains(s) || "_-:.+/".unicodeScalars.contains(s) { i += 1 }
            return string(start..<i)
        }

        /// Past the group opened at `i` (a `{` or `(`); false if the file ends first.
        private mutating func skipGroup() -> Bool {
            let open = u[i], close = open == Self.lbrace ? Self.rbrace : Self.rparen
            var depth = 0
            while i < u.count {
                if u[i] == open { depth += 1 } else if u[i] == close { depth -= 1; if depth == 0 { i += 1; return true } }
                i += 1
            }
            return false
        }

        /// The next entry: `.some(nil)` for something skipped, nil at the end of the file.
        mutating func nextEntry() -> BibTeXEntry?? {
            while i < u.count, u[i] != Self.at { i += 1 }
            guard i < u.count else { return nil }
            let start = i
            i += 1
            skipSpace()
            let type = identifier()
            skipSpace()
            guard !type.isEmpty, i < u.count, u[i] == Self.lbrace || u[i] == Self.lparen else { return .some(nil) }
            if ["comment", "string", "preamble"].contains(type.lowercased()) { _ = skipGroup(); return .some(nil) }
            let close = u[i] == Self.lbrace ? Self.rbrace : Self.rparen
            i += 1
            skipSpace()
            let keyStart = i
            while i < u.count, u[i] != Self.comma, u[i] != close, !BibTeX.isSpace(u[i]) { i += 1 }
            let key = string(keyStart..<i)
            var fields: [BibTeXEntry.Field] = []
            while true {
                skipSpace()
                guard i < u.count else { return .some(nil) }
                if u[i] == close { i += 1; break }
                if u[i] == Self.comma { i += 1; continue }
                let name = identifier()
                skipSpace()
                guard !name.isEmpty, i < u.count, u[i] == Self.equals else { return .some(nil) }
                i += 1
                guard let field = value(named: name, close: close) else { return .some(nil) }
                fields.append(field)
            }
            return .some(BibTeXEntry(type: type, key: key, fields: fields, range: NSRange(location: start, length: i - start)))
        }

        /// A field value: `{…}`, `"…"`, a bare token, or `#` concatenations of those.
        private mutating func value(named name: String, close: UInt16) -> BibTeXEntry.Field? {
            skipSpace()
            let valueStart = i
            var parts: [(inner: Range<Int>, delimited: Bool)] = []
            while true {
                guard i < u.count else { return nil }
                if u[i] == Self.lbrace {
                    let open = i
                    guard skipGroup() else { return nil }
                    parts.append((open + 1..<i - 1, true))
                } else if u[i] == Self.quote {
                    let open = i
                    i += 1
                    var depth = 0
                    while i < u.count, !(u[i] == Self.quote && depth == 0) {
                        if u[i] == Self.backslash { i += 1 } else if u[i] == Self.lbrace { depth += 1 } else if u[i] == Self.rbrace { depth -= 1 }
                        i += 1
                    }
                    guard i < u.count else { return nil }
                    i += 1
                    parts.append((open + 1..<i - 1, true))
                } else {
                    let start = i
                    while i < u.count, u[i] != Self.comma, u[i] != close, u[i] != Self.hash, !BibTeX.isSpace(u[i]) { i += 1 }
                    guard i > start else { return nil }
                    parts.append((start..<i, false))
                }
                let end = i
                skipSpace()
                if i < u.count, u[i] == Self.hash { i += 1; skipSpace(); continue }
                if parts.count == 1, parts[0].delimited { return .init(name: name, value: string(parts[0].inner)) }
                return .init(name: name, value: string(valueStart..<end), isRaw: true)
            }
        }
    }
}

// MARK: Duplicates

extension BibTeXEntry {
    /// What identifies the work whatever its key: the DOI (an arXiv DOI as its arXiv ID), the arXiv eprint, the ISBN-13,
    /// and the title with the year.
    var identities: Set<String> {
        var ids: Set<String> = []
        let arxivDOI = "10.48550/arxiv."
        if let raw = value("doi") {
            let doi = raw.trimmingCharacters(in: .whitespaces).lowercased().replacing(/^(?:https?:\/\/(?:dx\.)?doi\.org\/|doi:\s*)/, with: "")
            if doi.hasPrefix(arxivDOI) { ids.insert("arxiv:" + doi.dropFirst(arxivDOI.count)) } else if !doi.isEmpty { ids.insert("doi:" + doi) }
        }
        if let e = value("eprint"), let id = ReferenceID.arxivID(e.trimmingCharacters(in: .whitespaces)) { ids.insert("arxiv:" + id.lowercased()) }
        if let i = value("isbn"), case .isbn(let d)? = ReferenceID.parse(i) { ids.insert("isbn:" + ReferenceID.isbn13(d)) }
        let title = (value("title") ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased().filter { $0.isLetter || $0.isNumber }
        let year = (value("year") ?? value("date")).flatMap { $0.firstMatch(of: /\d{4}/).map { String($0.output) } } ?? ""
        if title.count >= 8 { ids.insert("title:\(title)|\(year)") }   // short titles ("Notes") say too little
        return ids
    }
}

extension BibTeX {
    /// For each entry that repeats an earlier one, by key or by identity (DOI, arXiv ID, ISBN, title and year), the
    /// earlier entry's key.
    public static func duplicates(_ entries: [BibTeXEntry]) -> [Int: String] {
        var seen: [String: String] = [:]
        var result: [Int: String] = [:]
        for (i, e) in entries.enumerated() {
            let ids = ["key:" + e.key] + e.identities.sorted()
            if let first = ids.lazy.compactMap({ seen[$0] }).first { result[i] = first }
            for id in ids where seen[id] == nil { seen[id] = e.key }
        }
        return result
    }
}
