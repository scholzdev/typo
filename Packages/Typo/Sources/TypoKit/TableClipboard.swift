import Foundation

/// Cell ranges on the pasteboard: TSV out, TSV or CSV in (as Numbers, Excel and Google Sheets write them).
public enum TableClipboard {
    /// Rows of fields. Tabs win over commas; a single line without tabs is one field, so "Hello, world" stays whole.
    /// Quoted fields (RFC 4180) may hold the delimiter, line breaks and doubled quotes.
    public static func parse(_ text: String) -> [[String]] {
        var text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasSuffix("\n") { text.removeLast() }
        guard !text.isEmpty else { return [] }
        let delimiter: Character? = text.contains("\t") ? "\t" : text.contains("\n") && text.contains(",") ? "," : nil
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, atStart = true
        let it = Array(text)
        var i = 0
        while i < it.count {
            let c = it[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < it.count, it[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" && atStart && delimiter != nil {
                quoted = true
            } else if c == delimiter {
                row.append(field); field = ""; atStart = true; i += 1; continue
            } else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""; atStart = true; i += 1; continue
            } else {
                field.append(c)
            }
            atStart = false
            i += 1
        }
        row.append(field)
        rows.append(row)
        return rows
    }

    /// Tab-separated rows; fields with tabs, line breaks or quotes are quoted.
    public static func tsv(_ rows: [[String]]) -> String {
        rows.map { $0.map(quote).joined(separator: "\t") }.joined(separator: "\n")
    }

    static func quote(_ s: String) -> String {
        s.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\"" || $0 == "\r" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Plain text as cell markup: characters Typst reads as markup are escaped, so `$12.50` stays text. Line breaks become `\`.
    public static func markup(_ plain: String) -> String {
        var out = ""
        for c in plain {
            if c == "\n" { out += " \\ "; continue }
            let lineStart = out.isEmpty || out.hasSuffix(" \\ ")
            if "\\#$*_@<>[]`~/".contains(c) || (lineStart && "=-+".contains(c)) { out.append("\\") }
            out.append(c)
        }
        // `1. ` at the start is a numbered list item.
        if let m = out.prefixMatch(of: /\d+\./) { out.insert("\\", at: out.index(before: m.output.endIndex)) }
        return out
    }
}
