import Foundation
import TypstEngine

/// Fixes for compiler diagnostics, derived from the messages and the project's labels, bindings and files.
public enum QuickFixes {
    /// What a diagnostic is about, read from its message.
    enum Kind: Equatable {
        case unknownLabel(String)
        case unknownVariable(String)
        case fileNotFound
        case unknownFont(String)
        case accessibility(Accessibility.Rule)
        case packageUpdate(name: String, version: String)
    }

    static func kind(of message: String) -> Kind? {
        if message.hasPrefix("unknown variable: ") {
            let name = message.dropFirst("unknown variable: ".count).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : .unknownVariable(name)
        }
        if let name = missingFont(in: message) { return .unknownFont(name) }
        if message.hasPrefix("file not found") { return .fileNotFound }
        if let u = PackageUpdates.parseHint(message) { return .packageUpdate(name: u.name, version: u.version) }
        if message.hasSuffix("(PDF/UA)"), let rule = Accessibility.rule(of: message) { return .accessibility(rule) }
        if (message.hasPrefix("label `") || message.hasPrefix("key `")), message.contains(" does not exist in the "),
           let a = message.firstIndex(of: "`"), let b = message[message.index(after: a)...].firstIndex(of: "`") {
            var name = String(message[message.index(after: a)..<b])
            if name.hasPrefix("<"), name.hasSuffix(">"), name.count > 2 { name = String(name.dropFirst().dropLast()) }
            return name.isEmpty ? nil : .unknownLabel(name)
        }
        return nil
    }

    /// The family of a compiler "unknown font family: <name>" warning.
    public static func missingFont(in message: String) -> String? {
        guard message.hasPrefix("unknown font family: ") else { return nil }
        let name = message.dropFirst("unknown font family: ".count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// The distinct missing families named by `diagnostics`, in order.
    public static func missingFonts(in diagnostics: [Diagnostic]) -> [String] {
        var seen = Set<String>()
        return diagnostics.compactMap { missingFont(in: $0.message) }.filter { seen.insert($0.lowercased()).inserted }
    }

    /// Installed families starting with `name` (case-insensitive) first, then the closest by edit distance; at most 3.
    static func fontSuggestions(_ name: String, installed: [String]) -> [String] {
        let lower = name.lowercased()
        let prefixed = Array(installed.filter { $0.lowercased().hasPrefix(lower) && $0 != name }.sorted { ($0.count, $0) < ($1.count, $1) }.prefix(3))
        let ordered = prefixed + closest(name, in: installed.filter { !prefixed.contains($0) }, limit: 3)
        return Array(ordered.prefix(3))
    }

    /// Cheap, message-only: whether `d` is a kind we may fix (for the lightbulb).
    public static func mayFix(_ d: Diagnostic) -> Bool {
        guard case .project = d.origin else { return false }
        return kind(of: d.message) != nil
    }

    /// Optimal-string-alignment distance (Levenshtein plus adjacent transpositions), case-insensitive.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a.lowercased()), b = Array(b.lowercased())
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev2 = [Int](repeating: 0, count: b.count + 1), prev = Array(0...b.count), cur = prev
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { cur[j] = min(cur[j], prev2[j - 2] + 1) }
            }
            (prev2, prev, cur) = (prev, cur, prev2)
        }
        return prev[b.count]
    }

    /// Closest names: distance <= max(1, name.count / 3), nearest first, at most `limit`. Never `name` itself.
    static func closest(_ name: String, in candidates: some Sequence<String>, limit: Int = 3) -> [String] {
        let maxDistance = max(1, name.count / 3)
        var seen = Set<String>()
        let scored = candidates.compactMap { c -> (String, Int)? in
            guard c != name, seen.insert(c).inserted else { return nil }
            let d = distance(name, c)
            return d <= maxDistance ? (c, d) : nil
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }.prefix(limit).map(\.0)
    }
}

extension Project {
    /// Fixes for `d`, best first; empty when none applies. Never a fix that changes nothing.
    public func quickFixes(for d: Diagnostic) async -> [QuickFix] {
        guard case .project(let loc) = d.origin, let kind = QuickFixes.kind(of: d.message) else { return [] }
        if case .accessibility = kind { _ = try? await open(loc.file) }      // hints name files that may not be open yet
        guard let text = buffer(for: loc.file)?.storage.string as NSString?,
              NSMaxRange(loc.range) <= text.length else { return [] }
        let shown = text.substring(with: loc.range)
        switch kind {
        case .unknownLabel(let name): return await labelFixes(name, loc, shown)
        case .unknownVariable(let name): return await variableFixes(name, loc, text)
        case .fileNotFound: return pathFixes(loc, shown)
        case .unknownFont(let name):
            guard shown.count >= 3, shown.hasPrefix("\""), shown.hasSuffix("\"") else { return [] }
            let inner = NSRange(location: loc.range.location + 1, length: loc.range.length - 2)
            let installed = await fontFamilyNames(host: loc.file).filter { !$0.hasPrefix(".") && !$0.contains("\"") }
            return QuickFixes.fontSuggestions(name, installed: installed).map {
                QuickFix(title: "Use \u{201C}\($0)\u{201D}", edits: [loc.file: [Replacement(range: inner, text: $0)]])
            }
        case .packageUpdate(let name, let version):
            let sources = textSources(where: FileKind.isTypst).compactMap(\.loaded)
            return await Task.detached { PackageUpdates.fixes(name: name, to: version, at: loc, sources: sources) }.value
        case .accessibility(let rule): return Accessibility.fixes(rule, file: loc.file, range: loc.range, text: text as String, language: Accessibility.systemLanguage)
        }
    }

    private func labelFixes(_ name: String, _ loc: Location, _ shown: String) async -> [QuickFix] {
        let index = await labelIndex()
        let at = (shown as NSString).range(of: name)
        guard at.location != NSNotFound else { return [] }
        let target = NSRange(location: loc.range.location + at.location, length: at.length)
        let asRef = shown.hasPrefix("@")
        return QuickFixes.closest(name, in: Array(index.definitions.keys) + Array(index.bibKeys.keys)).map { new in
            QuickFix(title: "Change to \(asRef ? "@" : "<")\(new)\(asRef ? "" : ">")", edits: [loc.file: [Replacement(range: target, text: new)]])
        }
    }

    private func variableFixes(_ name: String, _ loc: Location, _ text: NSString) async -> [QuickFix] {
        guard text.substring(with: loc.range) == name else { return [] }
        let index = await bindingIndex()
        var fixes: [QuickFix] = []
        let sites = index.importSites(in: loc.file)
        for other in allFiles where other != loc.file && FileKind.isTypst(other.raw) && index.exportedNames(in: other).contains(name) {
            let path = ImageInsert.relativePath(from: loc.file, to: other)
            guard !path.contains("\""), !path.contains("\\") else { continue }
            let edit: Replacement
            if let end = sites.first(where: { $0.target == other && !$0.wildcard && $0.itemsEnd != nil })?.itemsEnd {
                edit = Replacement(range: NSRange(location: end, length: 0), text: ", \(name)")
            } else {
                let top = sites.map(\.scopeEnd).max()
                let last = sites.filter { $0.scopeEnd == top }.max { $0.pathEnd < $1.pathEnd }
                var at = 0, line = "#import \"\(path)\": \(name)\n"
                if let last {
                    at = NSMaxRange(text.lineRange(for: NSRange(location: max(last.itemsEnd ?? last.pathEnd, 1) - 1, length: 0)))
                    if at > 0, text.character(at: at - 1) != 10 { line = "\n" + line }
                }
                edit = Replacement(range: NSRange(location: at, length: 0), text: line)
            }
            fixes.append(QuickFix(title: "Import `\(name)` from \"\(path)\"", edits: [loc.file: [edit]]))
        }
        for new in QuickFixes.closest(name, in: index.visibleNames(in: loc.file, at: loc.range.location)) {
            fixes.append(QuickFix(title: "Change to `\(new)`", edits: [loc.file: [Replacement(range: loc.range, text: new)]]))
        }
        return fixes
    }

    private func pathFixes(_ loc: Location, _ shown: String) -> [QuickFix] {
        guard shown.count >= 3, shown.hasPrefix("\""), shown.hasSuffix("\"") else { return [] }
        let content = String(shown.dropFirst().dropLast())
        guard !content.isEmpty, !content.hasPrefix("@"), !content.contains("\\"), !content.contains("://") else { return [] }
        let rooted = content.hasPrefix("/")
        let wantName = (content as NSString).lastPathComponent, wantExt = (content as NSString).pathExtension.lowercased()
        let maxDistance = max(1, wantName.count / 3)
        var scored: [(String, Int, Int)] = []
        for f in allFiles where f != loc.file {
            let rel = rooted ? "/" + f.raw : ImageInsert.relativePath(from: loc.file, to: f)
            guard rel != content, !rel.contains("\""), !rel.contains("\\") else { continue }
            let d = min(QuickFixes.distance(content, rel), QuickFixes.distance(wantName, f.name))
            if d <= maxDistance { scored.append((rel, d, (f.name as NSString).pathExtension.lowercased() == wantExt ? 0 : 1)) }
        }
        scored.sort { ($0.2, $0.1, $0.0) < ($1.2, $1.1, $1.0) }
        let inner = NSRange(location: loc.range.location + 1, length: loc.range.length - 2)
        return scored.prefix(3).map { QuickFix(title: "Change to \"\($0.0)\"", edits: [loc.file: [Replacement(range: inner, text: $0.0)]]) }
    }
}
