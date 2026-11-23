import Foundation
import TypstEngine

public struct SearchOptions: Sendable, Equatable {
    public var caseSensitive = false
    public var wholeWord = false
    public var regex = false
    public init(caseSensitive: Bool = false, wholeWord: Bool = false, regex: Bool = false) {
        self.caseSensitive = caseSensitive; self.wholeWord = wholeWord; self.regex = regex
    }
}

public struct SearchHit: Identifiable, Sendable, Equatable {
    public let file: RelPath
    public let range: NSRange          // in the file's text when searched
    public let line: Int               // 1-based
    public let context: String         // the line, trimmed and shortened around the match
    public let contextMatch: NSRange   // the match inside `context`
    public var id: String { "\(file.raw):\(range.location)" }
}

public struct SearchFileResult: Identifiable, Sendable, Equatable {
    public let id: RelPath
    public let hits: [SearchHit]
}

public struct SearchOutcome: Sendable, Equatable {
    public let files: [SearchFileResult]
    public let error: String?          // an invalid regular expression
    public let truncated: Bool
    public var matchCount: Int { files.reduce(0) { $0 + $1.hits.count } }
}

enum SearchSource: Sendable {
    case text(RelPath, String)         // an open buffer: its in-memory text wins over disk
    case disk(RelPath, URL)
}

enum ProjectSearch {
    static let hitLimit = 2000
    private static let maxFileBytes = 4 << 20

    static func matcher(_ query: String, _ o: SearchOptions) throws -> NSRegularExpression {
        var pattern = o.regex ? query : NSRegularExpression.escapedPattern(for: query)
        if o.wholeWord { pattern = "\\b(?:\(pattern))\\b" }
        return try NSRegularExpression(pattern: pattern, options: o.caseSensitive ? [] : [.caseInsensitive])
    }

    /// Matches line by line (so `^`/`$` mean the line and a match never spans lines). Empty matches are skipped.
    static func hits(in text: String, file: RelPath, regex: NSRegularExpression, limit: Int) -> [SearchHit] {
        let ns = text as NSString
        let bridged = ns as String            // NSString-backed, so each enumerateMatches call below bridges back in O(1)
        var out: [SearchHit] = []
        var pos = 0, line = 0
        while pos < ns.length, out.count < limit {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: pos, length: 0))
            line += 1
            let range = NSRange(location: start, length: contentsEnd - start)
            regex.enumerateMatches(in: bridged, options: [.withTransparentBounds], range: range) { m, _, stop in
                guard let m, m.range.length > 0 else { return }
                out.append(context(ns, line: line, lineRange: range, match: m.range, file: file))
                if out.count >= limit { stop.pointee = true }
            }
            pos = end
        }
        return out
    }

    private static func context(_ ns: NSString, line: Int, lineRange: NSRange, match: NSRange, file: RelPath) -> SearchHit {
        var lo = lineRange.location, hi = NSMaxRange(lineRange)
        while lo < match.location, let c = Unicode.Scalar(ns.character(at: lo)), CharacterSet.whitespaces.contains(c) { lo += 1 }
        lo = max(lo, match.location - 40)
        hi = min(hi, NSMaxRange(match) + 120)
        let ctx = ns.substring(with: NSRange(location: lo, length: hi - lo))
        return SearchHit(file: file, range: match, line: line, context: ctx,
                         contextMatch: NSRange(location: match.location - lo, length: match.length))
    }

    /// Nil when cancelled. Reads disk files here, off the main actor.
    @concurrent static func run(_ sources: [SearchSource], query: String, options: SearchOptions) async -> SearchOutcome? {
        guard !query.isEmpty else { return SearchOutcome(files: [], error: nil, truncated: false) }
        let regex: NSRegularExpression
        do { regex = try matcher(query, options) } catch {
            return SearchOutcome(files: [], error: (error as NSError).localizedDescription, truncated: false)
        }
        var files: [SearchFileResult] = []
        var total = 0
        for source in sources {
            if Task.isCancelled { return nil }
            let file: RelPath, text: String
            switch source {
            case .text(let f, let t): (file, text) = (f, t)
            case .disk(let f, let url):
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= maxFileBytes,
                      let t = String(data: data, encoding: .utf8) else { continue }
                (file, text) = (f, t)
            }
            let found = hits(in: text, file: file, regex: regex, limit: hitLimit - total)
            if !found.isEmpty { files.append(SearchFileResult(id: file, hits: found)) }
            total += found.count
            if total >= hitLimit { return SearchOutcome(files: files, error: nil, truncated: true) }
        }
        return Task.isCancelled ? nil : SearchOutcome(files: files, error: nil, truncated: false)
    }
}

// MARK: Replace

extension ProjectSearch {
    /// The matches `hits(in:)` reports, unlimited: line by line, empty ones skipped.
    static func matches(in text: String, regex: NSRegularExpression) -> [NSTextCheckingResult] {
        let ns = text as NSString
        let bridged = ns as String
        var out: [NSTextCheckingResult] = []
        var pos = 0
        while pos < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: pos, length: 0))
            regex.enumerateMatches(in: bridged, options: [.withTransparentBounds], range: NSRange(location: start, length: contentsEnd - start)) { m, _, _ in
                if let m, m.range.length > 0 { out.append(m) }
            }
            pos = end
        }
        return out
    }

    /// A regex template may use `$1`, `$0` and `\$`; otherwise the replacement is literal.
    static func replacement(for m: NSTextCheckingResult, in text: String, regex: NSRegularExpression, template: String, options: SearchOptions) -> String {
        options.regex ? regex.replacementString(for: m, in: text, offset: 0, template: template) : template
    }
}

extension SearchHit {
    /// What this hit becomes, for the result list's preview. A regex is re-run on the matched text alone, so lookaround
    /// context is lost; the real replacement sees the whole line.
    public func replacement(query: String, options: SearchOptions, template: String) -> String {
        guard options.regex, let regex = try? ProjectSearch.matcher(query, options) else { return template }
        let matched = (context as NSString).substring(with: contextMatch)
        guard let m = regex.firstMatch(in: matched, range: NSRange(location: 0, length: (matched as NSString).length)) else { return template }
        return regex.replacementString(for: m, in: matched, offset: 0, template: template)
    }
}

extension Project {
    /// Replaces the search's matches in every text file, or only `hits` when given. Matches are found again in each
    /// file's current text and a hit is replaced only if one still starts at its range, so stale hits are skipped.
    /// Only files with matches are opened. One undo step per file; autosave writes them. Returns the number replaced.
    public func replace(_ query: String, options: SearchOptions, with template: String, only hits: [SearchHit]? = nil) async throws(ProjectError) -> Int {
        guard !query.isEmpty, let regex = try? ProjectSearch.matcher(query, options) else { return 0 }
        let wanted = hits.map { Dictionary(grouping: $0, by: \.file).mapValues { Set($0.map(\.range.location)) } }
        let files = allFiles.filter { f in wanted.map { $0[f] != nil } ?? FileKind.isText(f.raw) }
        var count = 0
        for f in files {
            if buffers[f] == nil {
                guard let text = try? await Self.readText(url(for: f), settings: textFileSettings()), !ProjectSearch.matches(in: text, regex: regex).isEmpty else { continue }
            }
            let b = try await open(f)
            let text = b.storage.string
            let edits = ProjectSearch.matches(in: text, regex: regex)
                .filter { m in wanted.map { $0[f]?.contains(m.range.location) == true } ?? true }
                .map { Replacement(range: $0.range, text: ProjectSearch.replacement(for: $0, in: text, regex: regex, template: template, options: options)) }
            b.apply(edits, actionName: "Replace")
            count += edits.count
        }
        return count
    }
}
