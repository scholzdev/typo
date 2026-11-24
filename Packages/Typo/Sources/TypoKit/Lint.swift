import Foundation
import TypstEngine

/// Hints the compiler does not give: unused or duplicate labels, uncited bibliography entries, missing files.
/// Conservative: whatever the scan cannot judge for sure gets no hint.
public enum Lint {
    /// `sources`: the project's Typst and bibliography texts. `existing`: its files and folders. `compiler`: places
    /// of the current compiler diagnostics, where no missing-file hint is added.
    static func hints(_ index: LabelIndex, sources: [(file: RelPath, text: String)], existing: Set<RelPath>, compiler: [Location]) -> [Diagnostic] {
        let texts = Dictionary(sources.map { ($0.file, $0.text) }, uniquingKeysWith: { a, _ in a })
        let typst = sources.filter { FileKind.isTypst($0.file.raw) }
        let paths = typst.flatMap { pathArguments(in: $0.text, of: $0.file) }
        func matches(_ re: NSRegularExpression) -> Bool { typst.contains { re.firstMatch(in: $0.text, range: NSRange(location: 0, length: ($0.text as NSString).length)) != nil } }
        let dynamic = matches(dynamicLabel)       // names built at run time: nothing can be called unused
        var out: [(LabelSite, String)] = []
        func place(_ s: LabelSite) -> String { "\(s.file.raw):\(line(of: s.token.location, in: texts[s.file] ?? ""))" }

        if !dynamic {
            for (name, defs) in index.definitions where index.references[name] == nil {
                out += defs.map { ($0, Self.unusedLabelMessage(name)) }
            }
        }
        let docs = documents(typst.map(\.file), paths)
        for (name, defs) in index.definitions where defs.count > 1 {
            for d in defs {
                let others = defs.filter { $0 != d && !docs[$0.file, default: [$0.file]].isDisjoint(with: docs[d.file, default: [d.file]]) }
                if !others.isEmpty { out.append((d, String(localized: "Label <\(name)> is also defined at \(others.map(place).joined(separator: ", "))", bundle: .module))) }
            }
        }
        // Only files a `bibliography(…)` names: other .yml files are data.
        let bibs = Set(paths.filter { $0.function == "bibliography" }.map { $0.target.raw.lowercased() })
        if !dynamic, !matches(fullBibliography) {
            for (key, sites) in index.bibKeys where index.references[key] == nil {
                out += sites.filter { bibs.contains($0.file.raw.lowercased()) }.map { ($0, String(localized: "Bibliography entry “\(key)” is never cited", bundle: .module)) }
            }
        }
        let present = Set(existing.map { $0.raw.lowercased() })      // the file system is case-insensitive
        for p in paths where !present.contains(p.target.raw.lowercased()) {
            guard !compiler.contains(where: { $0.file == p.file && (NSIntersectionRange($0.range, p.range).length > 0 || NSLocationInRange($0.range.location, p.range)) }) else { continue }
            out.append((LabelSite(file: p.file, token: p.range, name: p.range), String(localized: "File “\(p.target.raw)” does not exist", bundle: .module)))
        }
        return out.sorted { ($0.0.file.raw, $0.0.token.location) < ($1.0.file.raw, $1.0.token.location) }.enumerated().map { i, h in
            Diagnostic(id: i, severity: .hint, message: h.1, hints: [], origin: .project(Location(file: h.0.file, range: h.0.token)))
        }
    }

    private static let dynamicLabel = try! NSRegularExpression(pattern: #"\blabel\((?!\s*"[^"\\]*"\s*\))"#)
    private static let fullBibliography = try! NSRegularExpression(pattern: #"\bfull\s*:\s*true\b"#)
    private static let pathFunctions: Set<String> = ["image", "read", "csv", "json", "yaml", "toml", "xml", "bibliography", "include", "import"]

    /// A string literal that is the whole first argument of a file-reading call, or what `include`/`import` names.
    struct PathArgument { let function: String; let file: RelPath; let range: NSRange; let target: RelPath }

    static func pathArguments(in text: String, of file: RelPath) -> [PathArgument] {
        let ns = text as NSString
        func char(_ i: Int) -> Character? { i >= 0 && i < ns.length ? Character(UnicodeScalar(ns.character(at: i)) ?? " ") : nil }
        func skip(_ i: Int, _ step: Int, lines: Bool = true) -> Int {
            var i = i
            while let c = char(i), c == " " || c == "\t" || lines && c.isNewline { i += step }
            return i
        }
        func word(endingAt i: Int) -> (String, Int) {
            var j = i
            while let c = char(j), c.isLetter || c.isNumber || c == "_" || c == "-" { j -= 1 }
            return (ns.substring(with: NSRange(location: j + 1, length: i - j)), j)
        }
        return TypstSyntax.tokens(in: text).compactMap { t in
            guard t.tag == .string, t.range.length >= 2 else { return nil }
            var j = skip(t.range.location - 1, -1)
            let call = char(j) == "("
            if call { j -= 1 }
            let (name, before) = word(endingAt: j)
            let keyword = name == "include" || name == "import"
            guard pathFunctions.contains(name), call != keyword, char(before) != "." else { return nil }
            // The literal must be the whole argument: `image("figs/" + n)` names no file.
            let k = skip(NSMaxRange(t.range), 1, lines: call)
            if call {
                guard char(k) == ")" || char(k) == "," else { return nil }
            } else {
                guard char(k).map({ $0.isNewline || ":;])}".contains($0) }) ?? true || ns.substring(from: k).hasPrefix("as ") else { return nil }
            }
            let s = ns.substring(with: NSRange(location: t.range.location + 1, length: t.range.length - 2))
            // Hidden files are not in the scanned tree.
            guard !s.split(separator: "/").contains(where: { $0.hasPrefix(".") && $0 != "." && $0 != ".." }),
                  let target = PathReferences.resolve(s, in: file.parent) else { return nil }
            return PathArgument(function: name, file: file, range: t.range, target: target)
        }
    }

    /// For each Typst file, the files that are not included or imported anywhere and reach it (itself if none):
    /// two labels clash only inside one document.
    static func documents(_ files: [RelPath], _ paths: [PathArgument]) -> [RelPath: Set<RelPath>] {
        var edges: [RelPath: [RelPath]] = [:]
        for p in paths where p.function == "include" || p.function == "import" { edges[p.file, default: []].append(p.target) }
        let included = Set(paths.filter { ($0.function == "include" || $0.function == "import") && $0.target != $0.file }.map(\.target))
        var docs: [RelPath: Set<RelPath>] = [:]
        for root in files where !included.contains(root) {
            var stack = [root], seen: Set<RelPath> = []
            while let f = stack.popLast() {
                guard seen.insert(f).inserted else { continue }
                docs[f, default: []].insert(root)
                stack += edges[f] ?? []
            }
        }
        for f in files where docs[f] == nil { docs[f] = [f] }
        return docs
    }

    static func line(of offset: Int, in text: String) -> Int {
        let ns = text as NSString
        var line = 1
        for i in 0..<min(offset, ns.length) where ns.character(at: i) == 10 { line += 1 }
        return line
    }
}
