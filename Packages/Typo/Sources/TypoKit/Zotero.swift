import Foundation
import Security

/// Reading a Zotero library as BibTeX: the desktop app's local API (Zotero 7+, no account) or the web API with a key.
/// Read-only: nothing is ever sent to Zotero but GET requests.

public struct ZoteroResponse: Sendable {
    public let status: Int
    /// Lowercased names.
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }
}

/// Performs a request. Tests inject stubs; the app uses `urlSession`.
public typealias ZoteroTransport = @Sendable (URLRequest) async throws -> ZoteroResponse

public enum ZoteroHTTP {
    public static let urlSession: ZoteroTransport = { req in
        var req = req
        req.cachePolicy = .reloadIgnoringLocalCacheData      // versions decide freshness, not URLCache
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] { headers[String(describing: k).lowercased()] = String(describing: v) }
        return ZoteroResponse(status: http?.statusCode ?? 0, headers: headers, body: data)
    }
}

public enum ZoteroSource: String, Codable, Sendable { case local, web }

public struct ZoteroCollection: Identifiable, Hashable, Sendable, Codable {
    public let key: String
    /// "Parent › Child" for a subcollection.
    public let name: String
    public var id: String { key }
    public init(key: String, name: String) { self.key = key; self.name = name }
}

public enum ZoteroError: Error, Equatable, LocalizedError {
    case notRunning, localAPIDisabled, badKey, missingKey
    case rateLimited(seconds: Int)
    case http(Int)
    case network(String)
    case unsavedChanges(String)

    public var errorDescription: String? {
        switch self {
        case .unsavedChanges(let f): "\u{201C}\(f)\u{201D} has unsaved changes, so Zotero didn\u{2019}t overwrite it. Save or revert it, then sync again."
        case .notRunning: "Zotero isn\u{2019}t running."
        case .localAPIDisabled: "Turn on \u{201C}Allow other applications on this computer to communicate with Zotero\u{201D} in Zotero \u{203A} Settings \u{203A} Advanced."
        case .badKey: "Zotero refused the API key. Check the key and its library access at zotero.org/settings/keys."
        case .missingKey: "No Zotero API key is saved. Connect Zotero again."
        case .rateLimited(let s): "Zotero asked to wait \(s) seconds before the next sync."
        case .http(let s): "Zotero answered with an error (HTTP \(s))."
        case .network(let m): m
        }
    }
}

/// A library's BibTeX; `version` is the web API's library version, nil for the local API. `backoff`: seconds the
/// server asked clients to pause (the `Backoff` header), honored by the next sync.
public struct ZoteroExport: Sendable, Equatable {
    public let text: String
    public let version: Int?
    public var backoff: Int? = nil
}

public struct ZoteroClient: Sendable {
    public let source: ZoteroSource
    public let userID: String
    let key: String?
    let transport: ZoteroTransport

    public init(source: ZoteroSource, userID: String, key: String?, transport: @escaping ZoteroTransport = ZoteroHTTP.urlSession) {
        self.source = source; self.userID = userID; self.key = key; self.transport = transport
    }

    /// 127.0.0.1 rather than localhost: localhost may resolve to ::1 first, where Zotero does not listen.
    var base: String { source == .local ? "http://127.0.0.1:23119/api/users/0" : "https://api.zotero.org/users/\(userID)" }

    /// Every collection of the library, sorted by their "Parent › Child" names.
    public func collections() async throws(ZoteroError) -> [ZoteroCollection] {
        var raw: [(key: String, name: String, parent: String?)] = []
        for page in try await pages("/collections", since: nil) ?? [] {
            let list = (try? JSONSerialization.jsonObject(with: page.body) as? [[String: Any]]) ?? []
            for c in list {
                guard let key = c["key"] as? String, let data = c["data"] as? [String: Any] else { continue }
                raw.append((key, data["name"] as? String ?? key, data["parentCollection"] as? String))    // `false` at the top
            }
        }
        let byKey = Dictionary(raw.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        func path(_ key: String, depth: Int = 0) -> String {
            guard let c = byKey[key] else { return "" }
            guard let p = c.parent, byKey[p] != nil, depth < 32 else { return c.name }
            return path(p, depth: depth + 1) + " \u{203A} " + c.name
        }
        return raw.map { ZoteroCollection(key: $0.key, name: path($0.key)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The top-level items of the library or of `collection` as BibTeX, pages concatenated; nil when the web library
    /// is still at version `since` (304).
    public func bibtex(collection: String?, since: Int?) async throws(ZoteroError) -> ZoteroExport? {
        let path = (collection.map { "/collections/\($0)" } ?? "") + "/items/top"
        guard let pages = try await pages(path, query: [URLQueryItem(name: "format", value: "bibtex")], since: since) else { return nil }
        let text = pages.map { String(decoding: $0.body, as: UTF8.self) }.joined(separator: "\n")
        return ZoteroExport(text: text, version: source == .web ? pages.first?.headers["last-modified-version"].flatMap { Int($0) } : nil,
                            backoff: pages.compactMap { $0.headers["backoff"].flatMap { Int($0) } }.max())
    }

    /// The local API returns everything at once; the web API at most 100 per request, so this walks `Total-Results`.
    /// `If-Modified-Since-Version` goes on the first page only: a 304 there means nothing changed.
    private func pages(_ path: String, query: [URLQueryItem] = [], since: Int?) async throws(ZoteroError) -> [ZoteroResponse]? {
        guard source == .web else { return [try await get(path, query: query, since: nil)] }
        var out: [ZoteroResponse] = []
        var start = 0
        while true {
            let r = try await get(path, query: query + [URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "start", value: String(start))],
                                  since: out.isEmpty ? since : nil)
            if r.status == 304 { return nil }
            out.append(r)
            start += 100
            guard let total = r.headers["total-results"].flatMap({ Int($0) }), start < total else { return out }
        }
    }

    private func get(_ path: String, query: [URLQueryItem], since: Int?) async throws(ZoteroError) -> ZoteroResponse {
        var url = URLComponents(string: base + path)!
        if !query.isEmpty { url.queryItems = query }
        var req = URLRequest(url: url.url!, timeoutInterval: 60)
        req.setValue("3", forHTTPHeaderField: "Zotero-API-Version")
        if source == .web {
            guard let key, !key.isEmpty else { throw .missingKey }
            req.setValue(key, forHTTPHeaderField: "Zotero-API-Key")
        }
        if let since { req.setValue(String(since), forHTTPHeaderField: "If-Modified-Since-Version") }
        let r: ZoteroResponse
        do { r = try await transport(req) } catch {
            if source == .local, let u = error as? URLError, [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(u.code) { throw .notRunning }
            throw .network(error.localizedDescription)
        }
        switch r.status {
        case 200..<300, 304: return r
        case 403 where source == .local, 404 where source == .local: throw .localAPIDisabled
        case 403: throw .badKey
        case 429, 503: throw .rateLimited(seconds: r.headers["retry-after"].flatMap { Int($0) } ?? 60)
        default: throw .http(r.status)
        }
    }
}

/// The web API key, in the login Keychain only; the user ID beside it is not secret.
public enum ZoteroKeychain {
    static let service = "Typo Zotero"
    public static let userIDKey = "Typo.zotero.userID"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public static func key(for userID: String) -> String? {
        var q = query(userID)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Attributes only, so Settings can show the status without a Keychain password prompt.
    public static func hasKey(for userID: String) -> Bool {
        var q = query(userID)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
    }

    public static func setKey(_ key: String, for userID: String) -> Bool {
        SecItemDelete(query(userID) as CFDictionary)
        var q = query(userID)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrLabel as String] = "Zotero API key"
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    public static func removeKey(for userID: String) { SecItemDelete(query(userID) as CFDictionary) }
}
