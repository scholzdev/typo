#if os(macOS)
import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

private final class MemoryTokens: GitTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [UUID: String] = [:]
    func token(for id: UUID) -> String? { lock.withLock { tokens[id] } }
    func setToken(_ token: String, for id: UUID, label: String) throws { lock.withLock { tokens[id] = token } }
    func removeToken(for id: UUID) { lock.withLock { tokens[id] = nil } }
}

@Suite struct GitAccountTests {
    @Test func normalizesServers() {
        #expect(GitAccount.normalizedServer("git.example.com/")?.absoluteString == "https://git.example.com")
        #expect(GitAccount.normalizedServer(" https://example.com/gitlab// ")?.absoluteString == "https://example.com/gitlab")
        #expect(GitAccount.normalizedServer("http://intranet")?.absoluteString == "http://intranet")
        #expect(GitAccount.normalizedServer("") == nil)
        #expect(GitAccount.normalizedServer("ssh://git@example.com") == nil)
        #expect(GitAccount.normalizedServer("https://example.com/?a=1") == nil)
    }

    @Test func gitEnvironmentCarriesOneHeaderPerServer() throws {
        let gh = try #require(GitHost.github.fixedServer)
        let a = GitAccount(host: .github, server: gh, username: "octo")
        let b = GitAccount(host: .github, server: gh, username: "other")
        let own = try #require(URL(string: "https://git.example.com"))
        let c = GitAccount(host: .gitlabSelfHosted, server: own, username: "me")
        let env = GitAccount.gitEnvironment([(a, "t1"), (b, "t2"), (c, "t3"), (c, "")])
        #expect(env["GIT_CONFIG_COUNT"] == "2")
        #expect(env["GIT_CONFIG_KEY_0"] == "http.https://github.com/.extraHeader")
        #expect(env["GIT_CONFIG_VALUE_0"] == "Authorization: Basic " + Data("octo:t1".utf8).base64EncodedString())
        #expect(env["GIT_CONFIG_KEY_1"] == "http.https://git.example.com/.extraHeader")
        #expect(GitAccount.gitEnvironment([]).isEmpty)
    }

    @Test func verificationRequests() throws {
        let server = try #require(URL(string: "https://ghe.example.com"))
        let ghe = try #require(GitHost.githubEnterprise.verificationRequest(server: server, account: "me", token: "tok"))
        #expect(ghe.url?.absoluteString == "https://ghe.example.com/api/v3/user")
        #expect(ghe.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        let gitlab = try #require(GitHost.gitlab.fixedServer), bitbucket = try #require(GitHost.bitbucketCloud.fixedServer)
        let gl = try #require(GitHost.gitlab.verificationRequest(server: gitlab, account: "me", token: "tok"))
        #expect(gl.url?.absoluteString == "https://gitlab.com/api/v4/user")
        #expect(gl.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "tok")
        let bb = try #require(GitHost.bitbucketCloud.verificationRequest(server: bitbucket, account: "me", token: "pw"))
        #expect(bb.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("me:pw".utf8).base64EncodedString())
        #expect(GitHost.github.login(fromVerification: Data(#"{"login":"octo"}"#.utf8)) == "octo")
        #expect(GitHost.gitlab.login(fromVerification: Data(#"{"username":"me"}"#.utf8)) == "me")
        #expect(GitHost.github.login(fromVerification: Data("nope".utf8)) == nil)
    }

    @Test func branchNames() {
        for ok in ["main", "trunk", "feature/x", "v1.2", "a-b_c"] { #expect(GitBranchName.isValid(ok), "\(ok)") }
        for bad in ["", "my branch", "a\\b", "-x", "a..b", "a.lock", "x/", "/x", "a~b", "a^b", "a:b", "a?b", "a*b", "a[b", "@", "a@{b", ".hidden", "x/.y"] {
            #expect(!GitBranchName.isValid(bad), "\(bad)")
        }
    }

    @Test func changeOrder() {
        let cs = [GitChange(path: "b.typ", kind: .untracked), GitChange(path: "a10.typ", kind: .modified),
                  GitChange(path: "a2.typ", kind: .added), GitChange(path: "c.typ", kind: .conflicted)]
        #expect(GitChangeOrder.name.sorted(cs).map(\.path) == ["a2.typ", "a10.typ", "b.typ", "c.typ"])
        #expect(GitChangeOrder.status.sorted(cs).map(\.path) == ["c.typ", "a10.typ", "a2.typ", "b.typ"])
    }

    @MainActor @Test func storeKeepsTokensOutOfDefaultsAndReplacesSameUser() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let tokens = MemoryTokens()
        let store = GitAccountStore(defaults: defaults, tokens: tokens)
        let gh = try #require(GitHost.github.fixedServer)
        try store.add(GitAccount(host: .github, server: gh, username: "Octo"), token: "old")
        try store.add(GitAccount(host: .github, server: gh, username: "octo"), token: "new")
        #expect(store.accounts.count == 1)
        #expect(tokens.token(for: store.accounts[0].id) == "new")
        let data = try #require(defaults.data(forKey: GitAccountStore.key))
        let saved = String(decoding: data, as: UTF8.self)
        #expect(!saved.contains("new") && !saved.contains("old"))
        #expect(GitAccountStore(defaults: defaults, tokens: tokens).accounts == store.accounts)
        #expect(store.gitEnvironment["GIT_CONFIG_COUNT"] == "1")
        store.remove(store.accounts[0])
        #expect(store.accounts.isEmpty && store.gitEnvironment.isEmpty)
    }
}

@Suite(.serialized) @MainActor struct GitSettingsOperationTests {
    private let git = GitRunner(extraEnvironment: [
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
    ], timeout: 30)

    @Test func gitReadsTheAccountHeaderFromTheEnvironment() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "x\n"])
        try await p.initRepository(git: git)
        let gh = try #require(GitHost.github.fixedServer)
        let account = GitAccount(host: .github, server: gh, username: "octo")
        var runner = git
        runner.extraEnvironment.merge(GitAccount.gitEnvironment([(account, "tok")])) { _, new in new }
        let out = try await runner.run(["config", "--get", "http.https://github.com/.extraheader"], in: p.rootURL)
        #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == account.gitConfig(token: "tok").value)
    }

    @Test func initUsesTheDefaultBranchName() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "x\n"])
        try await p.initRepository(defaultBranch: "trunk", git: git)
        #expect(try await p.gitStatus(git: git).branch == "trunk")
        let (q, _) = try await TestEnv.project(files: ["main.typ": "x\n"])
        try await q.initRepository(defaultBranch: "not valid", git: git)
        #expect(try await q.gitStatus(git: git).branch == "main")
    }

    @Test func fetchUpdatesBehindAndUpstreamText() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "one\n"])
        let bare = FileManager.default.temporaryDirectory.appending(path: "typstcore-bare-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        _ = try await git.run(["init", "--bare", "-b", "main"], in: bare)
        try await p.initRepository(git: git)
        try await p.commitAll("first", git: git)
        try await p.addRemote(bare.path, git: git)
        try await p.push(git: git)
        #expect(await p.upstreamText(of: RelPath("main.typ")!, git: git) == "one\n")

        let parent = FileManager.default.temporaryDirectory.appending(path: "typstcore-clone-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        _ = try await git.run(["clone", bare.path, "second"], in: parent)
        let clone = parent.appending(path: "second")
        try "two\n".write(to: clone.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        _ = try await git.run(["commit", "-am", "second"], in: clone)
        _ = try await git.run(["push"], in: clone)

        #expect(try await p.gitStatus(git: git).behind == 0)
        try await p.fetch(git: git)
        #expect(try await p.gitStatus(git: git).behind == 1)
        #expect(await p.upstreamText(of: RelPath("main.typ")!, git: git) == "two\n")
        #expect(await p.headText(of: RelPath("main.typ")!, git: git) == "one\n")
    }

    @Test func trackStagesNewRenamedAndRemovedFiles() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "one\n", "old.typ": "o\n"])
        try await p.initRepository(git: git)
        try await p.commitAll("first", git: git)
        try "n\n".write(to: root.appending(path: "new.typ"), atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(at: root.appending(path: "old.typ"), to: root.appending(path: "moved.typ"))
        await p.track([RelPath("new.typ")!, RelPath("old.typ")!, RelPath("moved.typ")!, RelPath("never-existed.typ")!], git: git)
        let changes = try await p.gitStatus(git: git).changes
        #expect(changes.allSatisfy { $0.staged && !$0.unstaged })
        #expect(Set(changes.map(\.path)) == ["new.typ", "moved.typ"])
    }
}
#endif
