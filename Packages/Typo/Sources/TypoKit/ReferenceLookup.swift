import Foundation
import TypstEngine

/// What the user typed in the "DOI, arXiv ID or ISBN" field.
public enum ReferenceID: Equatable, Sendable {
    case doi(String)
    case arxiv(String)      // without version, e.g. `2101.00001` or `hep-th/9901001`
    case isbn(String)       // digits (a trailing X for ISBN-10), checksum-valid

    /// A bare DOI, `doi:…`, a doi.org / dx.doi.org URL, an arXiv ID (`arXiv:…`, an arxiv.org abs/pdf URL, any version),
    /// or an ISBN-10/13 with hyphens or spaces.
    public static func parse(_ input: String) -> ReferenceID? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = arxivID(s) { return .arxiv(id) }
        if let m = s.firstMatch(of: /^(?i:https?:\/\/(?:dx\.)?doi\.org\/|doi:\s*)/) { s = String(s[m.range.upperBound...]) }
        s = s.removingPercentEncoding ?? s
        if s.wholeMatch(of: /10\.\d{4,9}\/\S+/) != nil { return .doi(s) }
        let digits = s.replacing(/^(?i:isbn(?:-1[03])?:?)\s*/, with: "").filter { $0 != "-" && !$0.isWhitespace }.uppercased()
        return isValidISBN(digits) ? .isbn(digits) : nil
    }

    /// The versionless arXiv ID in `s`, new style (`YYMM.NNNNN`) or old style (`archive[.XX]/YYMMNNN`).
    static func arxivID(_ s: String) -> String? {
        let pattern = /(?i:(?:https?:\/\/(?:www\.|export\.)?arxiv\.org\/(?:abs|pdf)\/|arxiv:\s*))?(\d{4}\.\d{4,5}|[a-z\-]+(?:\.[A-Z]{2})?\/\d{7})(?i:v\d+)?(?i:\.pdf)?\/?/
        return s.wholeMatch(of: pattern).map { String($0.output.1) }
    }

    static func isValidISBN(_ d: String) -> Bool {
        let c = Array(d)
        if c.count == 13, c.allSatisfy(\.isASCII), c.allSatisfy(\.isNumber) {
            let sum = c.enumerated().reduce(0) { $0 + Int(String($1.element))! * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
            return sum % 10 == 0
        }
        if c.count == 10, c.prefix(9).allSatisfy({ $0.isASCII && $0.isNumber }), c[9].isNumber || c[9] == "X" {
            let sum = c.enumerated().reduce(0) { $0 + ($1.element == "X" ? 10 : Int(String($1.element))!) * (10 - $1.offset) }
            return sum % 11 == 0
        }
        return false
    }

    /// The ISBN-13 form of a valid ISBN-10 or ISBN-13.
    static func isbn13(_ d: String) -> String {
        guard d.count == 10 else { return d }
        let body = "978" + d.prefix(9)
        let sum = body.enumerated().reduce(0) { $0 + Int(String($1.element))! * ($1.offset.isMultiple(of: 2) ? 1 : 3) }
        return body + String((10 - sum % 10) % 10)
    }
}

public enum ReferenceError: LocalizedError, Equatable {
    case notFound, offline, unreadable(String), invalidKey(String), keyInUse(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "No reference was found for this DOI, arXiv ID or ISBN.", bundle: .module)
        case .offline: String(localized: "The lookup service could not be reached. Check your internet connection.", bundle: .module)
        case .unreadable(let why): String(localized: "The answer could not be read as a bibliography entry. \(why)", bundle: .module)
        case .invalidKey(let k): String(localized: "“\(k)” is not a valid key: use letters, digits, and _ - : . starting with a letter.", bundle: .module)
        case .keyInUse(let k): String(localized: "The key “\(k)” is already used in this project.", bundle: .module)
        }
    }
}

/// Performs a request and returns the body with the HTTP status. Tests inject stubs; the app uses `urlSession`.
public typealias ReferenceFetch = @Sendable (URLRequest) async throws -> (Data, Int)

/// One BibTeX entry ready to be added: validated, with a project-unique key.
public struct ReferenceDraft: Sendable, Equatable {
    public let bibtex: String
    public let entry: BibEntry
    public var key: String { entry.key }

    /// Validates `bibtex` (exactly one entry for the project's parser). Keeps its key if valid and not in `usedKeys`,
    /// else generates `<lastname><year>` with a, b, c… until unique.
    public static func make(bibtex: String, usedKeys: Set<String>, keepKey: Bool = true) throws -> ReferenceDraft {
        let parsed = try parse(bibtex)
        let key: String
        if keepKey, ReferenceLookup.isValidKey(parsed.key), !usedKeys.contains(parsed.key) {
            key = parsed.key
        } else {
            let base = ReferenceLookup.baseKey(bibtex: bibtex, year: parsed.year)
            key = ([base] + "abcdefghijklmnopqrstuvwxyz".map { base + String($0) }).first { !usedKeys.contains($0) } ?? base + UUID().uuidString.prefix(4).lowercased()
        }
        return try parse(ReferenceLookup.rewriteKey(bibtex, to: key)).draft
    }

    /// The same entry under a key the user chose.
    public func rekeyed(_ key: String, usedKeys: Set<String>) throws -> ReferenceDraft {
        guard ReferenceLookup.isValidKey(key) else { throw ReferenceError.invalidKey(key) }
        guard !usedKeys.contains(key) else { throw ReferenceError.keyInUse(key) }
        return try Self.parse(ReferenceLookup.rewriteKey(bibtex, to: key)).draft
    }

    private static func parse(_ bibtex: String) throws -> (key: String, year: Int?, draft: ReferenceDraft) {
        let r = Bridge.bibliography(bibtex, yaml: false)
        guard r.error == nil, r.entries.count == 1, let e = r.entries.first else {
            throw ReferenceError.unreadable(r.error ?? String(localized: "It holds \(r.entries.count) entries instead of one.", bundle: .module))
        }
        return (e.key, e.year, ReferenceDraft(bibtex: bibtex, entry: e))
    }
}

public enum ReferenceLookup {
    static let userAgent = "Typo/0.1", timeout: TimeInterval = 20

    /// Looks the reference up and returns a draft keyed uniquely against `usedKeys`.
    public static func fetch(_ id: ReferenceID, usedKeys: Set<String>, via fetch: ReferenceFetch = urlSession) async throws -> ReferenceDraft {
        switch id {
        case .doi(let doi):
            return try .make(bibtex: try await bibtex(doi: doi, fetch), usedKeys: usedKeys)
        case .arxiv(let id):
            // arXiv registers every paper as a DataCite DOI, which doi.org serves as BibTeX. Its key is a URL, so it is
            // replaced before the entry is parsed.
            let text = try await bibtex(doi: "10.48550/arXiv." + id, fetch)
            return try .make(bibtex: rewriteKey(text, to: "arxiv"), usedKeys: usedKeys, keepKey: false)
        case .isbn(let isbn):
            let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data")!
            let (data, _) = try await get(url, accept: "application/json", fetch)
            return try .make(bibtex: bibtex(openLibraryJSON: data, isbn: isbn), usedKeys: usedKeys, keepKey: false)
        }
    }

    @Sendable public static func urlSession(_ req: URLRequest) async throws -> (Data, Int) {
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// The BibTeX doi.org's content negotiation answers for `doi`.
    private static func bibtex(doi: String, _ fetch: ReferenceFetch) async throws -> String {
        let url = URL(string: "https://doi.org/" + (doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? doi))!
        let (data, _) = try await get(url, accept: "application/x-bibtex; charset=utf-8", fetch)
        guard let text = String(data: data, encoding: .utf8), text.contains("@") else { throw ReferenceError.unreadable("") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func get(_ url: URL, accept: String, _ fetch: ReferenceFetch) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        do {
            let (data, status) = try await fetch(req)
            if status == 404 { throw ReferenceError.notFound }
            guard (200..<300).contains(status) else { throw ReferenceError.unreadable(String(localized: "The service answered with status \(status).", bundle: .module)) }
            return (data, status)
        } catch let e as ReferenceError {
            throw e
        } catch {
            throw ReferenceError.offline
        }
    }

    /// A `@book` from Open Library's `jscmd=data` answer (`{"ISBN:…": {title, authors, publishers, publish_date}}`).
    static func bibtex(openLibraryJSON data: Data, isbn: String) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ReferenceError.unreadable("") }
        guard let book = root.values.first as? [String: Any], let title = book["title"] as? String else { throw ReferenceError.notFound }
        func clean(_ s: String) -> String { s.filter { $0 != "{" && $0 != "}" } }
        func names(_ key: String) -> [String] { (book[key] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? [] }
        let fullTitle = [title, book["subtitle"] as? String].compactMap { $0 }.joined(separator: ": ")
        let authors = names("authors").map { n -> String in
            guard let sp = n.lastIndex(of: " ") else { return n }
            return "\(n[n.index(after: sp)...]), \(n[..<sp])"
        }
        let year = (book["publish_date"] as? String)?.firstMatch(of: /\b(1[5-9]|20)\d\d\b/).map { String($0.output.0) }
        var fields = [("title", fullTitle)]
        if !authors.isEmpty { fields.append(("author", authors.joined(separator: " and "))) }
        if let p = names("publishers").first { fields.append(("publisher", p)) }
        if let year { fields.append(("year", year)) }
        fields.append(("isbn", ReferenceID.isbn13(isbn)))
        return "@book{book,\n" + fields.map { "  \($0.0) = {\(clean($0.1))}" }.joined(separator: ",\n") + "\n}\n"
    }

    static func isValidKey(_ k: String) -> Bool { k.wholeMatch(of: /[A-Za-z_][A-Za-z0-9_:.\-]*[A-Za-z0-9_\-]|[A-Za-z_]/) != nil }

    /// Replaces the key of the first entry.
    static func rewriteKey(_ bibtex: String, to key: String) -> String {
        guard let m = bibtex.firstMatch(of: /^(\s*@[A-Za-z]+\s*[{(]\s*)([^,\s]*)/) else { return bibtex }
        return bibtex.replacingCharacters(in: m.output.2.startIndex..<m.output.2.endIndex, with: key)
    }

    /// `<firstauthorlastname><year>`, ASCII-folded and lowercase.
    static func baseKey(bibtex: String, year: Int?) -> String {
        var name = ""
        if let m = bibtex.firstMatch(of: /(?i:\bauthor\s*=\s*[{"])\s*([^}"]*)/) {
            let first = m.output.1.split(separator: " and ").first.map(String.init) ?? ""
            name = first.contains(",") ? String(first.split(separator: ",")[0]) : String(first.split(separator: " ").last ?? "")
        }
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return (folded.isEmpty ? "ref" : folded) + (year.map(String.init) ?? "")
    }
}

extension Project {
    /// The `.bib` files a BibTeX entry can go into, and the one to preselect: the only one, else the first named
    /// by a `bibliography("…")` string in a Typst file. Nil `preferred` with several candidates means: ask.
    public func referenceTargets() -> (candidates: [RelPath], preferred: RelPath?) {
        let bibs = allFiles.filter { $0.raw.lowercased().hasSuffix(".bib") }
        if bibs.count <= 1 { return (bibs, bibs.first) }
        for f in allFiles where FileKind.isTypst(f.raw) {
            guard let text = currentText(of: f) else { continue }
            let ns = text as NSString
            for t in TypstSyntax.tokens(in: text) where t.tag == .string && t.range.length >= 2 {
                guard ns.substring(to: t.range.location).hasSuffix("bibliography(") else { continue }
                let name = ns.substring(with: NSRange(location: t.range.location + 1, length: t.range.length - 2))
                let path = name.hasPrefix("/") ? RelPath(String(name.dropFirst())) : RelPath.make(name, in: f.parent)
                if let path, bibs.contains(path) { return (bibs, path) }
            }
        }
        return (bibs, nil)
    }

    /// Keys of every bibliography of the project (unsaved text wins).
    public func usedReferenceKeys() async -> Set<String> {
        Set(await references().flatMap { $0.entries.map(\.key) })
    }

    /// Appends the entry to `target` (one undo step in that file). Without a target, creates `refs.bib` at the root and,
    /// with `appendBibliography`, appends `#bibliography("refs.bib")` to the main file (a second undo step there).
    /// Returns the file written.
    @discardableResult public func addReference(_ draft: ReferenceDraft, to target: RelPath?, appendBibliography: Bool = false) async throws(ProjectError) -> RelPath {
        let path: RelPath
        if let target {
            path = target
        } else {
            path = RelPath("refs.bib")!
            guard !exists(path) else { throw .nameExists(path.raw) }
            do { try Data().write(to: url(for: path), options: .withoutOverwriting) } catch { throw .operationFailed(error.localizedDescription) }
            rescan()
        }
        let buffer = try await open(path)
        let text = buffer.storage.string
        let lead = text.isEmpty ? "" : text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n"
        try await edit(path, [Replacement(range: NSRange(location: (text as NSString).length, length: 0), text: lead + draft.bibtex)], actionName: String(localized: "Add Reference", bundle: .module))
        if target == nil, appendBibliography {
            let main = try await open(self.main).storage.string
            let line = (main.isEmpty || main.hasSuffix("\n") ? "" : "\n") + "\n#bibliography(\"refs.bib\")\n"
            try await edit(self.main, [Replacement(range: NSRange(location: (main as NSString).length, length: 0), text: line)], actionName: String(localized: "Add Reference", bundle: .module))
        }
        return path
    }

    func currentText(of f: RelPath) -> String? {
        buffers[f]?.storage.string ?? (try? String(contentsOf: url(for: f), encoding: .utf8))
    }
}

extension Project {
    /// The entry of the project's `.bib` files that is the same work as `draft` (same DOI, arXiv ID, ISBN, or title
    /// and year), with its file; unsaved text wins.
    public func existingReference(for draft: ReferenceDraft) -> (key: String, file: RelPath)? {
        guard let ids = BibTeX.entries(in: draft.bibtex).first?.identities, !ids.isEmpty else { return nil }
        for f in allFiles where BibTeX.isFormEditable(f.raw) {
            guard let text = currentText(of: f) else { continue }
            if let e = BibTeX.entries(in: text).first(where: { !$0.identities.isDisjoint(with: ids) }) { return (e.key, f) }
        }
        return nil
    }
}
