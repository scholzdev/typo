import Foundation

/// The indentation keys of `.editorconfig` files (https://editorconfig.org): `indent_style`, `indent_size`, `tab_width`.
/// Other keys are parsed but unused here.
public enum EditorConfig {
    struct File {
        var root = false
        var sections: [(glob: String, properties: [String: String])] = []
    }

    static func parse(_ text: String) -> File {
        var f = File()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") { f.sections.append((String(line.dropFirst().dropLast()), [:])); continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces).lowercased()
            if f.sections.isEmpty { if key == "root" { f.root = value == "true" } }
            else { f.sections[f.sections.count - 1].properties[key] = value }
        }
        return f
    }

    /// Whether section `glob` matches `path` (relative to the `.editorconfig`'s folder). A glob without `/` matches
    /// a file name in any folder. Supports `*`, `**`, `?`, `[abc]`, `[!abc]` and `{a,b}`.
    /// shortcut: no numeric ranges `{1..3}`; add them if someone needs them.
    static func matches(_ glob: String, _ path: String) -> Bool {
        let chars = Array(glob.hasPrefix("/") ? String(glob.dropFirst()) : glob)
        var re = glob.contains("/") ? "" : "(?:.*/)?", i = 0, braces = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*" where i + 1 < chars.count && chars[i + 1] == "*": re += ".*"; i += 1
            case "*": re += "[^/]*"
            case "?": re += "[^/]"
            case "[":
                if let close = chars[(i + 1)...].firstIndex(of: "]") {
                    var set = String(chars[(i + 1)..<close]).replacingOccurrences(of: "\\", with: "\\\\")
                    if set.hasPrefix("!") { set = "^" + set.dropFirst() }
                    re += "[" + set + "]"; i = close
                } else { re += "\\[" }
            case "{": braces += 1; re += "(?:"
            case "}" where braces > 0: braces -= 1; re += ")"
            case "," where braces > 0: re += "|"
            case "\\" where i + 1 < chars.count: i += 1; re += NSRegularExpression.escapedPattern(for: String(chars[i]))
            default: re += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }
        guard let rx = try? NSRegularExpression(pattern: "^" + re + "$") else { return false }
        return rx.firstMatch(in: path, range: NSRange(location: 0, length: (path as NSString).length)) != nil
    }

    /// Properties from `files`, nearest folder first: (the file's path relative to that folder, its contents).
    /// Nearer files and later sections win; a file with `root = true` ends the search.
    static func properties(_ files: [(path: String, text: String)]) -> [String: String] {
        var chain: [(path: String, file: File)] = []
        for (path, text) in files {
            let f = parse(text)
            chain.append((path, f))
            if f.root { break }
        }
        var props: [String: String] = [:]
        for (path, f) in chain.reversed() {
            for s in f.sections where matches(s.glob, path) { props.merge(s.properties) { $1 } }
        }
        return props
    }

    /// Properties for `file` from the `.editorconfig` files in its folder and every parent up to `root`.
    public static func properties(for file: URL, root: URL) -> [String: String] {
        let filePath = file.standardizedFileURL.path, rootPath = root.standardizedFileURL.path
        var dir = file.standardizedFileURL.deletingLastPathComponent()
        var files: [(path: String, text: String)] = []
        while dir.path.hasPrefix(rootPath) {
            if let text = try? String(contentsOf: dir.appendingPathComponent(".editorconfig"), encoding: .utf8) {
                files.append((String(filePath.dropFirst(dir.path.count).drop { $0 == "/" }), text))
            }
            if dir.path.count <= rootPath.count { break }
            dir = dir.deletingLastPathComponent()
        }
        return properties(files)
    }
}

extension IndentSettings {
    /// These settings with the `.editorconfig` keys applied, following the spec's defaults: `indent_size = tab` and a
    /// tab style without a size use the tab width, and a size without `tab_width` is also the tab width.
    public func applying(editorConfig p: [String: String]) -> IndentSettings {
        var s = self
        func number(_ key: String) -> Int? { p[key].flatMap { Int($0) }.map { min(max($0, 1), 16) } }
        if let style = p["indent_style"], style == "tab" || style == "space" { s.useTabs = style == "tab"; s.explicitStyle = true }
        if let t = number("tab_width") ?? number("indent_size") { s.tabWidth = t }
        if let i = number("indent_size") { s.indentWidth = i }
        else if p["indent_size"] == "tab" || (p["indent_size"] == nil && p["indent_style"] == "tab") { s.indentWidth = s.tabWidth }
        return s
    }

    /// The settings for one file of a project: with `.editorconfig` applied when preferred.
    public func resolved(for file: URL, root: URL) -> IndentSettings {
        preferEditorConfig ? applying(editorConfig: EditorConfig.properties(for: file, root: root)) : self
    }
}
