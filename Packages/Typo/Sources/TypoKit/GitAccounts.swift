#if os(macOS)
import Foundation
import Observation
import Security

/// The hosting services an account can be added for, as in Xcode's Source Control settings.
public enum GitHost: String, Codable, CaseIterable, Identifiable, Sendable {
    case bitbucketCloud, bitbucketServer, github, githubEnterprise, gitlab, gitlabSelfHosted

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .bitbucketCloud: "Bitbucket Cloud"
        case .bitbucketServer: "Bitbucket Server"
        case .github: "GitHub"
        case .githubEnterprise: "GitHub Enterprise"
        case .gitlab: "GitLab.com"
        case .gitlabSelfHosted: "GitLab self-hosted"
        }
    }

    /// The fixed server of a cloud service; nil when the user enters it (Enterprise, self-hosted, Server).
    public var fixedServer: URL? {
        switch self {
        case .bitbucketCloud: URL(string: "https://bitbucket.org")
        case .github: URL(string: "https://github.com")
        case .gitlab: URL(string: "https://gitlab.com")
        case .bitbucketServer, .githubEnterprise, .gitlabSelfHosted: nil
        }
    }

    public var needsServer: Bool { fixedServer == nil }

    /// What the secret is called on the service.
    public var tokenLabel: String { self == .bitbucketCloud ? "App Password" : "Token" }

    /// The scopes (GitHub, GitLab) or permissions (Bitbucket) the token needs for clone, fetch and push.
    public var requiredScopes: [String] {
        switch self {
        case .github, .githubEnterprise: ["admin:public_key", "repo", "user"]
        case .gitlab, .gitlabSelfHosted: ["api", "read_user", "write_repository"]
        case .bitbucketCloud: ["Account: Read", "Repositories: Write"]
        case .bitbucketServer: ["Repository: Write"]
        }
    }

    /// Where the user makes a token with those scopes.
    public func tokenPage(server: URL) -> URL? {
        let s = server.absoluteString
        switch self {
        case .github, .githubEnterprise:
            return URL(string: s + "/settings/tokens/new?description=Typo&scopes=admin:public_key,repo,user")
        case .gitlab, .gitlabSelfHosted:
            return URL(string: s + "/-/user_settings/personal_access_tokens?name=Typo&scopes=api,read_user,write_repository")
        case .bitbucketCloud:
            return URL(string: "https://bitbucket.org/account/settings/app-passwords/new")
        case .bitbucketServer:
            return URL(string: s + "/plugins/servlet/access-tokens/manage")
        }
    }

    /// A request that only succeeds with a valid token: the signed-in user of the service's API.
    public func verificationRequest(server: URL, account: String, token: String) -> URLRequest? {
        let s = server.absoluteString
        let url: URL?
        switch self {
        case .github: url = URL(string: "https://api.github.com/user")
        case .githubEnterprise: url = URL(string: s + "/api/v3/user")
        case .gitlab, .gitlabSelfHosted: url = URL(string: s + "/api/v4/user")
        case .bitbucketCloud: url = URL(string: "https://api.bitbucket.org/2.0/user")
        case .bitbucketServer:
            let slug = account.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? account
            url = URL(string: s + "/rest/api/1.0/users/" + slug)
        }
        guard let url else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        switch self {
        case .gitlab, .gitlabSelfHosted: r.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        case .bitbucketCloud: r.setValue(GitAccount.basicAuthorization(account, token), forHTTPHeaderField: "Authorization")
        case .github, .githubEnterprise, .bitbucketServer: r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        return r
    }

    /// The user name in the verification response (GitHub `login`, GitLab and Bitbucket `username`, Bitbucket Server `slug`).
    public func login(fromVerification data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let key = switch self {
        case .github, .githubEnterprise: "login"
        case .gitlab, .gitlabSelfHosted, .bitbucketCloud: "username"
        case .bitbucketServer: "slug"
        }
        return (json[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// A signed-in hosting account. The token is in the Keychain under `id`, never in the defaults.
public struct GitAccount: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var host: GitHost
    /// Scheme and host (and a path prefix for a server under a subpath), without a trailing slash.
    public var server: URL
    public var username: String

    public init(id: UUID = UUID(), host: GitHost, server: URL, username: String) {
        self.id = id; self.host = host; self.server = server; self.username = username
    }

    /// "https://example.com/" or "example.com" as the canonical https URL; nil for anything that is not a web server.
    public static func normalizedServer(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let c = URLComponents(string: s), let scheme = c.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = c.host, !host.isEmpty, c.query == nil, c.fragment == nil, c.user == nil else { return nil }
        return URL(string: s)
    }

    static func basicAuthorization(_ user: String, _ token: String) -> String {
        "Basic " + Data("\(user):\(token)".utf8).base64EncodedString()
    }

    /// The git config entry that signs HTTPS requests to this server in: `http.<server>/.extraHeader`. Git applies
    /// it to every URL under the server, so clone, fetch, pull and push need no credential helper or prompt.
    public func gitConfig(token: String) -> (key: String, value: String) {
        ("http.\(server.absoluteString)/.extraHeader", "Authorization: " + Self.basicAuthorization(username, token))
    }

    /// GIT_CONFIG_COUNT/KEY/VALUE for git (2.31 and later) carrying the accounts' headers; the first account of a
    /// server wins. Environment variables, unlike `-c` arguments, are not visible to other users in `ps`.
    public static func gitEnvironment(_ accounts: [(GitAccount, String)]) -> [String: String] {
        var seen = Set<String>(), env: [String: String] = [:], n = 0
        for (account, token) in accounts where !token.isEmpty {
            let c = account.gitConfig(token: token)
            guard seen.insert(c.key).inserted else { continue }
            env["GIT_CONFIG_KEY_\(n)"] = c.key
            env["GIT_CONFIG_VALUE_\(n)"] = c.value
            n += 1
        }
        if n > 0 { env["GIT_CONFIG_COUNT"] = String(n) }
        return env
    }
}

/// Where tokens are kept; the Keychain in the app, a dictionary in tests.
public protocol GitTokenStoring: Sendable {
    func token(for id: UUID) -> String?
    func setToken(_ token: String, for id: UUID, label: String) throws
    func removeToken(for id: UUID)
}

/// Generic passwords in the login Keychain, one per account.
public struct KeychainTokens: GitTokenStoring {
    // persisted keychain service, kept from the app's old name so saved data survives
    static let service = "Tympan Source Control Account"
    public init() {}

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.service, kSecAttrAccount as String: id.uuidString]
    }

    public func token(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setToken(_ token: String, for id: UUID, label: String) throws {
        SecItemDelete(query(id) as CFDictionary)
        var q = query(id)
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrLabel as String] = label
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            throw GitError.failed("The token could not be saved in the Keychain: \(reason)")
        }
    }

    public func removeToken(for id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}

/// The signed-in accounts of Settings › Source Control. Their tokens go into every git run (`GitRunner.sharedEnvironment`).
@MainActor @Observable public final class GitAccountStore {
    public static let shared = GitAccountStore()
    static let key = "gitAccounts"

    public private(set) var accounts: [GitAccount] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let tokens: GitTokenStoring

    public init(defaults: UserDefaults = .standard, tokens: GitTokenStoring = KeychainTokens()) {
        self.defaults = defaults
        self.tokens = tokens
        if let data = defaults.data(forKey: Self.key), let saved = try? JSONDecoder().decode([GitAccount].self, from: data) {
            accounts = saved
        }
    }

    /// Adds the account, or replaces the one for the same server and user (a new token for it).
    public func add(_ account: GitAccount, token: String) throws {
        var a = account
        if let old = accounts.first(where: { $0.server == a.server && $0.username.lowercased() == a.username.lowercased() }) {
            a.id = old.id
        }
        try tokens.setToken(token, for: a.id, label: "\(a.host.name) (\(a.username))")
        if let i = accounts.firstIndex(where: { $0.id == a.id }) { accounts[i] = a } else { accounts.append(a) }
        save()
    }

    public func remove(_ account: GitAccount) {
        tokens.removeToken(for: account.id)
        accounts.removeAll { $0.id == account.id }
        save()
    }

    /// The git environment for the accounts that still have a token.
    public var gitEnvironment: [String: String] {
        GitAccount.gitEnvironment(accounts.compactMap { a in tokens.token(for: a.id).map { (a, $0) } })
    }

    /// Hands the accounts to every later git run; called at launch and after each change.
    public func apply() { GitRunner.sharedEnvironment = gitEnvironment }

    private func save() {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: Self.key)
        apply()
    }

    /// Checks the token against the service's API and returns the user name it belongs to.
    public nonisolated static func verify(host: GitHost, server: URL, account: String, token: String) async throws -> String {
        guard let request = host.verificationRequest(server: server, account: account, token: token) else {
            throw GitError.failed("That server address is not valid.")
        }
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw GitError.failed("Couldn’t reach \(server.host() ?? server.absoluteString): \(error.localizedDescription)") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return host.login(fromVerification: data) ?? account
        case 401, 403: throw GitError.failed("\(host.name) did not accept this \(host.tokenLabel.lowercased()). Check that it is current and has the required scopes.")
        case 404: throw GitError.failed("No \(host.name) API was found at \(server.absoluteString).")
        default: throw GitError.failed("\(host.name) answered with HTTP status \(status).")
        }
    }
}

/// Branch names git accepts (`git check-ref-format --branch`), checked as the user types.
public enum GitBranchName {
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/"), !name.hasSuffix("."),
              !name.hasSuffix(".lock"), name != "@", !name.contains(".."), !name.contains("//"), !name.contains("@{") else { return false }
        if name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || " ~^:?*[\\".unicodeScalars.contains($0) }) { return false }
        return !name.split(separator: "/").contains { $0.hasPrefix(".") || $0.hasSuffix(".lock") }
    }
}

/// Global git settings (`~/.gitconfig`) shown in Settings: the author of new commits.
public enum GitGlobalConfig {
    public static func value(_ key: String, git: GitRunner = GitRunner()) async -> String {
        let out = try? await git.run(["config", "--global", "--get", key], in: home, okStatuses: [0, 1])
        return (out ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sets the key, or removes it for an empty value.
    public static func set(_ key: String, _ value: String, git: GitRunner = GitRunner()) async throws {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty {
            _ = try await git.run(["config", "--global", "--unset-all", key], in: home, okStatuses: [0, 5])
        } else {
            _ = try await git.run(["config", "--global", "--replace-all", key, v], in: home)
        }
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
}
#endif
