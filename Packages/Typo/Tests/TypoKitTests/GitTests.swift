import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

@Suite struct GitParseTests {
    @Test func statusParsesBranchAndEntries() {
        let raw = [
            "# branch.oid abc", "# branch.head main", "# branch.upstream origin/main", "# branch.ab +2 -1",
            "1 .M N... 100644 100644 100644 a b main.typ",
            "1 A. N... 000000 100644 100644 a b new file.typ",
            "1 .D N... 100644 100644 000000 a b gone.typ",
            "2 R. N... 100644 100644 100644 a b R100 renamed.typ", "old.typ",
            "u UU N... 1 2 3 4 a b c clash.typ",
            "? notes.txt",
        ].joined(separator: "\0") + "\0"
        let s = GitStatus(porcelainV2: raw)
        #expect(s.branch == "main" && s.upstream == "origin/main" && s.ahead == 2 && s.behind == 1)
        #expect(s.changes == [
            GitChange(path: "main.typ", kind: .modified), GitChange(path: "new file.typ", kind: .added, staged: true, unstaged: false),
            GitChange(path: "gone.typ", kind: .deleted),
            GitChange(path: "renamed.typ", kind: .renamed, oldPath: "old.typ", staged: true, unstaged: false),
            GitChange(path: "clash.typ", kind: .conflicted), GitChange(path: "notes.txt", kind: .untracked),
        ])
    }

    @Test func diffParsesLines() {
        let d = GitDiff.parse("diff --git a/x b/x\nindex 1..2 100644\n--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n keep\n-old\n+new\n\\ No newline at end of file\n")
        #expect(d.map(\.kind) == [.hunk, .context, .removed, .added])
        #expect(d.map(\.text) == ["@@ -1,2 +1,2 @@", "keep", "old", "new"])
    }

    @Test func partlyStagedFile() {
        let s = GitStatus(porcelainV2: "1 MM N... 100644 100644 100644 a b main.typ\0")
        #expect(s.changes == [GitChange(path: "main.typ", kind: .modified, staged: true, unstaged: true)])
        #expect(s.changes[0].partlyStaged)
    }

    @Test func branchesParse() {
        #expect(GitBranch.parse(" \0feature/x\n*\0main\n") == [GitBranch(name: "feature/x"), GitBranch(name: "main", isCurrent: true)])
    }

    @Test func logParsesCommitsAndTheirPaths() {
        let raw = "\u{1e}aaa\u{1f}Ann\u{1f}100\u{1f}Rename it\n\nnew.typ\n\u{1e}bbb\u{1f}Bo\u{1f}50\u{1f}a: b\u{1f}c\n\nold.typ\n"
        #expect(GitCommit.parse(raw) == [
            GitCommit(hash: "aaa", author: "Ann", date: Date(timeIntervalSince1970: 100), subject: "Rename it", path: "new.typ"),
            GitCommit(hash: "bbb", author: "Bo", date: Date(timeIntervalSince1970: 50), subject: "a: b\u{1f}c", path: "old.typ"),
        ])
    }

    @Test func sideBySidePairsRunsOfChanges() {
        let d = GitDiff.parse("@@ -3,4 +3,3 @@\n keep\n-a\n-b\n+A\n tail\n-gone\n")
        let rows = GitDiff.sideBySide(d)
        #expect(rows.count == 6)
        #expect(rows[0].isHunk)
        #expect(rows[1].old?.number == 3 && rows[1].new?.number == 3)
        #expect(rows[2].old?.text == "a" && rows[2].new?.text == "A" && rows[2].new?.number == 4)
        #expect(rows[3].old?.text == "b" && rows[3].old?.number == 5 && rows[3].new == nil)
        #expect(rows[4].old?.number == 6 && rows[4].new?.number == 5)
        #expect(rows[5].old?.text == "gone" && rows[5].new == nil)
    }
}

#if os(macOS)
@Suite(.serialized) @MainActor struct GitOperationTests {
    private let git = GitRunner(extraEnvironment: [
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
    ], timeout: 30)

    private func tempDir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appending(path: "typstcore-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// A committed project pushed to a fresh local bare remote.
    private func pushedProject(_ files: [String: String] = ["main.typ": "one\n"]) async throws -> (Project, URL, URL) {
        let (p, root) = try await TestEnv.project(files: files)
        let bare = try tempDir()
        _ = try await git.run(["init", "--bare", "-b", "main"], in: bare)
        try await p.initRepository(git: git)
        try await p.commitAll("first", git: git)
        try await p.addRemote(bare.path, git: git)
        try await p.push(git: git)
        return (p, root, bare)
    }

    /// Commits `text` to main.typ in a second clone of `bare` and pushes it.
    private func pushFromSecondClone(_ bare: URL, text: String) async throws {
        let parent = try tempDir()
        _ = try await git.run(["clone", bare.path, "second"], in: parent)
        let clone = parent.appending(path: "second")
        try text.write(to: clone.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        _ = try await git.run(["commit", "-am", "second"], in: clone)
        _ = try await git.run(["push"], in: clone)
    }

    @Test func initCommitAndStatus() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "one\n"])
        #expect(!p.isRepository)
        try await p.initRepository(git: git)
        #expect(p.isRepository)
        let s0 = try await p.gitStatus(git: git)
        #expect(s0.changes == [GitChange(path: "main.typ", kind: .untracked)])
        let d = try await p.diff(of: s0.changes[0], git: git)
        #expect(d.contains { $0.kind == .added && $0.text == "one" })
        try await p.commitAll("first", git: git)
        #expect(try await p.gitStatus(git: git).changes.isEmpty)
        try "two\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        let s1 = try await p.gitStatus(git: git)
        #expect(s1.changes == [GitChange(path: "main.typ", kind: .modified)])
        let d1 = try await p.diff(of: s1.changes[0], git: git)
        #expect(d1.contains { $0.kind == .removed && $0.text == "one" } && d1.contains { $0.kind == .added && $0.text == "two" })
    }

    @Test func commitAllSavesOpenBuffers() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "one\n"])
        try await p.initRepository(git: git)
        let b = try await p.open(RelPath("main.typ")!)
        type(b, "x", at: 0)
        try await p.commitAll("save", git: git)
        #expect(try await p.gitStatus(git: git).changes.isEmpty)
        #expect(try await git.run(["show", "HEAD:main.typ"], in: p.rootURL) == "xone\n")
    }

    @Test func stageUnstageAndCommitOnlyStaged() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "one\n", "notes.typ": "n\n"])
        try await p.initRepository(git: git)
        let s0 = try await p.gitStatus(git: git)
        let main = try #require(s0.changes.first { $0.path == "main.typ" })
        try await p.unstage([main], git: git)      // nothing staged and no commit yet: a no-op, not an error
        try await p.stage([main], git: git)
        #expect(try await p.gitStatus(git: git).changes.first { $0.path == "main.typ" }?.staged == true)
        try await p.unstage([main], git: git)
        #expect(try await p.gitStatus(git: git).changes.first { $0.path == "main.typ" }?.kind == .untracked)
        try await p.stage([main], git: git)
        try await p.commitStaged("only main", git: git)
        #expect(try await p.gitStatus(git: git).changes == [GitChange(path: "notes.typ", kind: .untracked)])

        try "two\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        let m = try #require(try await p.gitStatus(git: git).changes.first)
        try await p.stage([m], git: git)
        try await p.unstage([m], git: git)        // with HEAD: restore --staged
        #expect(try await p.gitStatus(git: git).changes.first { $0.path == "main.typ" } == GitChange(path: "main.typ", kind: .modified))
    }

    @Test func createListAndSwitchBranches() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "one\n"])
        try await p.initRepository(git: git)
        try await p.commitAll("first", git: git)
        try await p.createBranch("draft", git: git)
        #expect(try await p.branches(git: git) == [GitBranch(name: "draft", isCurrent: true), GitBranch(name: "main")])
        try "two\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try await p.commitAll("second", git: git)
        try await p.switchBranch("main", git: git)
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "one\n")
        #expect(try await p.gitStatus(git: git).branch == "main")
        await #expect(throws: GitError.self) { try await p.createBranch("bad..name", git: git) }
    }

    @Test func switchRefusedByLocalChangesFailsCleanly() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "one\n"])
        try await p.initRepository(git: git)
        try await p.commitAll("first", git: git)
        #expect(try await p.shortHead(git: git)?.count ?? 0 >= 7)
        try await p.createBranch("draft", git: git)
        try "two\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try await p.commitAll("second", git: git)
        try await p.switchBranch("main", git: git)
        try "local\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        await #expect(throws: GitError.self) { try await p.switchBranch("draft", git: git) }
        #expect(try await p.gitStatus(git: git).branch == "main")
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "local\n")
    }

    @Test func historyFollowsRenames() async throws {
        let (p, root) = try await TestEnv.project(files: ["old.typ": "a\nb\nc\nd\n"])
        try await p.initRepository(git: git)
        #expect(try await p.history(of: "old.typ", git: git).isEmpty)
        try await p.commitAll("first", git: git)
        try FileManager.default.moveItem(at: root.appending(path: "old.typ"), to: root.appending(path: "new.typ"))
        try await p.commitAll("rename", git: git)
        try "a\nb\nc\nD\n".write(to: root.appending(path: "new.typ"), atomically: true, encoding: .utf8)
        try await p.commitAll("edit", git: git)
        let h = try await p.history(of: "new.typ", git: git)
        #expect(h.map(\.subject) == ["edit", "rename", "first"])
        #expect(h.map(\.path) == ["new.typ", "new.typ", "old.typ"])
        let d = try await p.diff(of: h[0], git: git)
        #expect(d.contains { $0.kind == .added && $0.text == "D" })
        let first = try await p.diff(of: h[2], git: git)
        #expect(first.filter { $0.kind == .added }.count == 4)
        try "x\n".write(to: root.appending(path: "new.typ"), atomically: true, encoding: .utf8)
        let now = try await p.diff(from: h[2], toWorkingCopyOf: "new.typ", git: git)
        #expect(now.contains { $0.kind == .added && $0.text == "x" } && now.contains { $0.kind == .removed && $0.text == "a" })
    }

    @Test func headTextIsTheCommittedVersion() async throws {
        let (p, root) = try await TestEnv.project(files: ["main.typ": "one\n", "sub/b.typ": "b\n"])
        let main = try #require(RelPath("main.typ")), b = try #require(RelPath("sub/b.typ"))
        #expect(await p.headText(of: main, git: git) == nil)
        try await p.initRepository(git: git)
        try await p.commitAll("first", git: git)
        try "two\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        #expect(await p.headText(of: main, git: git) == "one\n")
        #expect(await p.headText(of: b, git: git) == "b\n")
        try "new\n".write(to: root.appending(path: "new.typ"), atomically: true, encoding: .utf8)
        #expect(await p.headText(of: try #require(RelPath("new.typ")), git: git) == nil)
    }

    @Test func noRemoteIsAClearError() async throws {
        let (p, _) = try await TestEnv.project(files: ["main.typ": "one\n"])
        try await p.initRepository(git: git)
        try await p.commitAll("first", git: git)
        #expect(try await !p.hasRemote(git: git))
        await #expect(throws: GitError.self) { try await p.push(git: git) }
        await #expect(throws: GitError.self) { try await p.pull(git: git) }
    }

    @Test func pushToBareRemoteSetsUpstream() async throws {
        let (p, _, bare) = try await pushedProject()
        let s = try await p.gitStatus(git: git)
        #expect(s.upstream == "origin/main" && s.ahead == 0 && s.behind == 0)
        #expect(try await git.run(["log", "--format=%s", "main"], in: bare) == "first\n")
    }

    @Test func pullTakesTheRemoteTextIntoACleanBuffer() async throws {
        let (p, root, bare) = try await pushedProject()
        let b = try await p.open(RelPath("main.typ")!)
        try await pushFromSecondClone(bare, text: "remote\n")
        try await p.pull(git: git)
        #expect(b.storage.string == "remote\n" && !b.isDirty)
        try await p.saveAll()
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "remote\n")
    }

    @Test func bufferEditedDuringThePullBecomesAConflict() async throws {
        let (p, root, bare) = try await pushedProject()
        let b = try await p.open(RelPath("main.typ")!)
        try await pushFromSecondClone(bare, text: "remote\n")
        try await p.rewritingWorkingTree {
            _ = try await git.run(["pull", "--ff-only"], in: root)
            type(b, "mine ", at: 0)                      // typed after the pull started
        }
        #expect(b.isChangedOnDisk && b.storage.string == "mine one\n")
        try await p.saveAll()
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "remote\n")
    }
}
#endif
