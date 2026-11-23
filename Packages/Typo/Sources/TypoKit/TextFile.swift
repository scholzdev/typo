import Foundation
import TypstEngine

public enum LineEnding: String, Sendable, CaseIterable {
    case lf, crlf, cr
    var separator: String { switch self { case .lf: "\n"; case .crlf: "\r\n"; case .cr: "\r" } }
}

/// Typst reads UTF-8 only; the others exist so a file saved by another tool still opens and is written back unchanged.
public enum TextEncoding: String, Sendable, CaseIterable {
    case utf8, latin1, windows1252, macRoman, utf16
    var string: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .latin1: .isoLatin1
        case .windows1252: .windowsCP1252
        case .macRoman: .macOSRoman
        case .utf16: .utf16
        }
    }
}

/// How a file looked on disk. The buffer text is always LF; this is what saving puts back.
public struct FileFormat: Sendable, Equatable {
    public var encoding: TextEncoding = .utf8
    public var bom = false                       // UTF-8 byte order mark
    public var lineEnding: LineEnding = .lf
}

/// The user's choices, passed in by the app.
public struct TextFileSettings: Sendable, Equatable {
    public var fallback: TextEncoding = .utf8    // used when a file is not valid UTF-8
    public var lineEnding: LineEnding = .lf      // new files, and conversion
    public var convertOnSave = false
    public init(fallback: TextEncoding = .utf8, lineEnding: LineEnding = .lf, convertOnSave: Bool = false) {
        self.fallback = fallback; self.lineEnding = lineEnding; self.convertOnSave = convertOnSave
    }
}

public enum TextFile {
    /// The most frequent ending wins (CRLF, lone LF, lone CR counted separately); a tie goes to LF, then CRLF.
    /// nil when the text has no line break.
    public static func detectLineEnding(_ text: String) -> LineEnding? {
        var crlf = 0, lf = 0, cr = 0
        var prevCR = false
        for u in text.utf8 {
            if u == 0x0A { if prevCR { crlf += 1; cr -= 1 } else { lf += 1 } }
            else if u == 0x0D { cr += 1 }
            prevCR = u == 0x0D
        }
        guard crlf + lf + cr > 0 else { return nil }
        if lf >= crlf && lf >= cr { return .lf }
        return crlf >= cr ? .crlf : .cr
    }

    /// CRLF and lone CR become LF.
    public static func normalize(_ text: String) -> String {
        guard text.utf8.contains(0x0D) else { return text }
        var out = String.UnicodeScalarView()
        var prevCR = false
        for u in text.unicodeScalars {
            if u == "\r" { out.append("\n") } else if !(u == "\n" && prevCR) { out.append(u) }
            prevCR = u == "\r"
        }
        return String(out)
    }

    /// LF text in the given ending.
    public static func apply(_ ending: LineEnding, to text: String) -> String {
        ending == .lf ? text : text.replacingOccurrences(of: "\n", with: ending.separator)
    }

    /// UTF-8 (with or without BOM) first, else the fallback encoding; nil when neither decodes.
    public static func decode(_ data: Data, settings: TextFileSettings) -> (text: String, format: FileFormat)? {
        var format = FileFormat()
        var raw: String
        let bom = data.starts(with: [0xEF, 0xBB, 0xBF])
        if let s = String(data: bom ? data.dropFirst(3) : data, encoding: .utf8) {
            raw = s
            format.bom = bom
        } else if let s = String(data: data, encoding: settings.fallback.string) {
            raw = s
            format.encoding = settings.fallback
        } else { return nil }
        format.lineEnding = detectLineEnding(raw) ?? settings.lineEnding
        return (normalize(raw), format)
    }

    /// The bytes to write and the format they are in. Converting writes plain UTF-8 with the default ending. Text the
    /// file's encoding cannot hold is written as UTF-8 instead, so nothing is lost.
    public static func encode(_ text: String, format: FileFormat, settings: TextFileSettings) -> (data: Data, format: FileFormat) {
        let f = settings.convertOnSave ? FileFormat(encoding: .utf8, bom: false, lineEnding: settings.lineEnding) : format
        let body = apply(f.lineEnding, to: text)
        if f.encoding != .utf8, let d = body.data(using: f.encoding.string) { return (d, f) }
        var out = f.encoding == .utf8 && f.bom ? Data([0xEF, 0xBB, 0xBF]) : Data()
        out.append(Data(body.utf8))
        return (out, FileFormat(encoding: .utf8, bom: f.encoding == .utf8 && f.bom, lineEnding: f.lineEnding))
    }
}

/// Trailing whitespace on save, as pure edits.
public enum WhitespaceTrim {
    /// Removes trailing spaces and tabs from every line that has content; whitespace-only lines are emptied only with
    /// `blankLines`. A line break that sits inside a raw block or a string (raw tokens include their line breaks) is left alone (`tokens` are the file's syntax tokens,
    /// empty for plain text).
    public static func edits(in text: String, tokens: [SyntaxToken], blankLines: Bool) -> [Replacement] {
        let ns = text as NSString
        let multiline = tokens.filter { $0.tag == .raw || $0.tag == .string }
        var edits: [Replacement] = []
        var lineStart = 0
        while lineStart <= ns.length {
            var end = lineStart
            while end < ns.length, ns.character(at: end) != 0x0A { end += 1 }
            var s = end
            while s > lineStart, [0x20, 0x09].contains(ns.character(at: s - 1)) { s -= 1 }
            let blank = s == lineStart
            if s < end, !blank || blankLines, !multiline.contains(where: { NSLocationInRange(end, $0.range) }) {
                edits.append(Replacement(range: NSRange(location: s, length: end - s), text: ""))
            }
            lineStart = end + 1
        }
        return edits
    }
}
