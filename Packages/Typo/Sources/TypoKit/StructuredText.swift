import Foundation
import TypstEngine

/// Plain-text formats with their own lightweight highlighter (pure: text in, spans out).
enum StructuredLang {
    case toml, bib

    init?(path: String) {
        switch (path as NSString).pathExtension.lowercased() {
        case "toml": self = .toml
        case "bib": self = .bib
        default: return nil
        }
    }

    func spans(_ text: String) -> [SyntaxSpan] {
        var s = Scanner16(Array(text.utf16))
        switch self {
        case .toml: s.toml()
        case .bib: s.bib()
        }
        return s.out
    }
}

/// Spans are emitted in document order and never overlap, so two scans can be compared span by span.
struct Scanner16 {
    let u: [UInt16]
    var i = 0
    var out: [SyntaxSpan] = []

    init(_ u: [UInt16]) { self.u = u }

    private func c(_ s: Unicode.Scalar) -> UInt16 { UInt16(s.value) }
    private var atEnd: Bool { i >= u.count }
    private func at(_ k: Int) -> UInt16 { k < u.count ? u[k] : 0 }
    private func isSpace(_ x: UInt16) -> Bool { x == 32 || x == 9 || x == 10 || x == 13 }
    private func isDigit(_ x: UInt16) -> Bool { x >= 48 && x <= 57 }
    private func isBare(_ x: UInt16) -> Bool {
        isDigit(x) || (x >= 65 && x <= 90) || (x >= 97 && x <= 122) || x == 95 || x == 45
    }

    private mutating func emit(_ from: Int, _ to: Int, _ tag: SyntaxTag) {
        if to > from { out.append(SyntaxSpan(range: NSRange(location: from, length: to - from), tag: tag)) }
    }
    private mutating func skipSpace() { while !atEnd, isSpace(u[i]) { i += 1 } }
    private mutating func skipLine() { while !atEnd, u[i] != 10 { i += 1 } }
    private mutating func punct(_ n: Int = 1) { emit(i, min(i + n, u.count), .punctuation); i += n }

    // MARK: TOML

    mutating func toml() {
        var stack: [UInt16] = []        // open `[` (array) and `{` (inline table)
        var keyPos = true
        while !atEnd {
            let ch = u[i]
            if ch == 10 { i += 1; if stack.isEmpty { keyPos = true }; continue }
            if ch == 32 || ch == 9 || ch == 13 { i += 1; continue }
            if ch == c("#") { let s = i; skipLine(); emit(s, i, .comment); continue }
            if keyPos {
                if stack.isEmpty, ch == c("[") { tomlHeader(); keyPos = false; continue }
                if ch == c("}") { stack.removeLast(); punct(); keyPos = false; continue }
                tomlKey()
                skipSpaceInLine()
                if at(i) == c("=") { emit(i, i + 1, .operator); i += 1 }
                keyPos = false
                continue
            }
            switch ch {
            case c("["), c("{"):
                stack.append(ch); punct(); keyPos = ch == c("{")
            case c("]"), c("}"):
                if !stack.isEmpty { stack.removeLast() }
                punct()
            case c(","):
                punct(); keyPos = stack.last == c("{")
            case c("\""), c("'"): tomlString()
            default: tomlBare()
            }
        }
    }

    private mutating func skipSpaceInLine() { while !atEnd, u[i] == 32 || u[i] == 9 { i += 1 } }

    private mutating func tomlHeader() {
        let double = at(i + 1) == c("[")
        punct(double ? 2 : 1)
        while !atEnd, u[i] != 10, u[i] != c("]"), u[i] != c("#") {
            if u[i] == 32 || u[i] == 9 { i += 1 }
            else if u[i] == c(".") { punct() }
            else if u[i] == c("\"") || u[i] == c("'") { let s = i; tomlString(tag: nil); emit(s, i, .heading) }
            else { let s = i; while !atEnd, isBare(u[i]) { i += 1 }; if i == s { i += 1 } else { emit(s, i, .heading) } }
        }
        if at(i) == c("]") { punct(double && at(i + 1) == c("]") ? 2 : 1) }
    }

    private mutating func tomlKey() {
        while !atEnd, u[i] != 10, u[i] != c("="), u[i] != c("#"), u[i] != c("}"), u[i] != c(",") {
            if u[i] == 32 || u[i] == 9 { i += 1 }
            else if u[i] == c(".") { punct() }
            else if u[i] == c("\"") || u[i] == c("'") { let s = i; tomlString(tag: nil); emit(s, i, .function) }
            else { let s = i; while !atEnd, isBare(u[i]) { i += 1 }; if i == s { i += 1 } else { emit(s, i, .function) } }
        }
    }

    /// Basic or literal string, single or multi-line. `tag` nil: the caller tags the span.
    private mutating func tomlString(tag: SyntaxTag? = .string) {
        let s = i, q = u[i]
        let multi = at(i + 1) == q && at(i + 2) == q
        i += multi ? 3 : 1
        while !atEnd {
            if multi {
                if u[i] == q, at(i + 1) == q, at(i + 2) == q {
                    i += 3
                    for _ in 0..<2 where at(i) == q { i += 1 }   // up to two extra quotes belong to the string
                    break
                }
            } else if u[i] == q || u[i] == 10 { if u[i] == q { i += 1 }; break }
            if q == c("\""), u[i] == c("\\") { i += 1 }
            i += 1
        }
        i = min(i, u.count)
        if let tag { emit(s, i, tag) }
    }

    private mutating func tomlBare() {
        let s = i
        // Dates and times carry `:` and `.`; a date-time separated by one space is two tokens, both numbers.
        while !atEnd, isBare(u[i]) || u[i] == c(".") || u[i] == c(":") || u[i] == c("+") { i += 1 }
        if i == s { i += 1; return }
        let word = String(decoding: u[s..<i], as: UTF16.self)
        if word == "true" || word == "false" { emit(s, i, .keyword) }
        else if let f = word.unicodeScalars.first, f.properties.numericType != nil || f == "+" || f == "-" || word == "inf" || word == "nan" { emit(s, i, .number) }
    }

    // MARK: BibTeX

    mutating func bib() {
        while !atEnd {
            let ch = u[i]
            if ch == c("%") { let s = i; skipLine(); emit(s, i, .comment) }
            else if ch == c("@") { bibEntry() }
            else { i += 1 }       // text outside entries is a comment to BibTeX; left plain
        }
    }

    private mutating func bibEntry() {
        let s = i
        i += 1
        while !atEnd, isBare(u[i]) || u[i] == c(":") { i += 1 }
        let type = String(decoding: u[(s + 1)..<i], as: UTF16.self).lowercased()
        emit(s, i, .keyword)
        skipSpace()
        guard at(i) == c("{") || at(i) == c("(") else { return }
        let close = at(i) == c("{") ? c("}") : c(")")
        punct()
        if type == "comment" {
            let b = i
            var depth = 1
            while !atEnd {
                if u[i] == c("{") { depth += 1 } else if u[i] == c("}") { depth -= 1; if depth == 0 { break } }
                i += 1
            }
            emit(b, i, .comment)
            if at(i) == close { punct() }
            return
        }
        skipSpace()
        if type != "string", type != "preamble" {
            let k = i
            while !atEnd, !isSpace(u[i]), u[i] != c(","), u[i] != close { i += 1 }
            emit(k, i, .label)
        }
        while !atEnd {
            skipSpace()
            if atEnd { break }
            let ch = u[i]
            if ch == close { punct(); return }
            if ch == c(",") { punct(); continue }
            if ch == c("%") { let s = i; skipLine(); emit(s, i, .comment); continue }
            if ch == c("@") { return }      // an unfinished entry ends where the next one starts
            if type != "preamble" {
                let f = i
                while !atEnd, !isSpace(u[i]), u[i] != c("="), u[i] != c(","), u[i] != close { i += 1 }
                emit(f, i, .function)
                skipSpace()
                guard at(i) == c("=") else { if i == f { i += 1 }; continue }
                emit(i, i + 1, .operator); i += 1
            }
            bibValue(close)
        }
    }

    /// `{..}`, `"..."` or a bare number or macro, joined by `#`.
    private mutating func bibValue(_ close: UInt16) {
        while true {
            skipSpace()
            let ch = at(i)
            if ch == c("{") {
                punct()
                let b = i
                var depth = 1
                while !atEnd {
                    if u[i] == c("\\") { i += 1 }
                    else if u[i] == c("{") { depth += 1 }
                    else if u[i] == c("}") { depth -= 1; if depth == 0 { break } }
                    i += 1
                }
                i = min(i, u.count)
                emit(b, i, .string)
                if at(i) == c("}") { punct() }
            } else if ch == c("\"") {
                punct()
                let b = i
                var depth = 0
                while !atEnd {
                    if u[i] == c("\\") { i += 1 }
                    else if u[i] == c("{") { depth += 1 }
                    else if u[i] == c("}") { depth -= 1 }
                    else if u[i] == c("\""), depth <= 0 { break }
                    i += 1
                }
                i = min(i, u.count)
                emit(b, i, .string)
                if at(i) == c("\"") { punct() }
            } else {
                let b = i
                while !atEnd, !isSpace(u[i]), u[i] != c(","), u[i] != c("#"), u[i] != close { i += 1 }
                emit(b, i, u[b..<i].allSatisfy(isDigit) ? .number : .interpolated)
            }
            skipSpace()
            if at(i) == c("#") { emit(i, i + 1, .operator); i += 1 } else { return }
        }
    }
}
