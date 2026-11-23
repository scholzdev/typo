import Foundation
import Testing
import TypoTestSupport
@testable import TypoKit
@testable import TypstEngine

struct GitExtrasParseTests {
    @Test func blameParsesGroupsAndRepeats() {
        let a = String(repeating: "a", count: 40), z = String(repeating: "0", count: 40)
        let raw = [
            "\(a) 1 1 2", "author Ann", "author-time 100", "summary First", "filename main.typ", "\tone",
            "\(a) 2 2", "\ttwo",
            "\(z) 3 3 1", "author Not Committed Yet", "author-time 200", "summary Version of main.typ from main.typ", "\tnew",
        ].joined(separator: "\n") + "\n"
        let b = GitBlame.parse(raw)
        #expect(b.count == 3)
        #expect(b[0].author == "Ann" && b[1].author == "Ann" && b[1].summary == "First" && b[0].isCommitted)
        #expect(!b[2].isCommitted)
    }

    @Test func stashListParses() {
        let s = GitStash.parse("stash@{0}\u{1f}100\u{1f}On main: wip\nstash@{1}\u{1f}50\u{1f}WIP on main: abc x\n")
        #expect(s.map(\.ref) == ["stash@{0}", "stash@{1}"] && s[0].message == "On main: wip")
    }

    @Test func patchSplitsHunks() {
        let p = GitPatch("diff --git a/x b/x\nindex 1..2 100644\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+A\n@@ -9 +9 @@\n-b\n+B\n")
        #expect(p.header.count == 4 && p.hunks.count == 2)
        #expect(p.patch(forHunk: 1) == "diff --git a/x b/x\nindex 1..2 100644\n--- a/x\n+++ b/x\n@@ -9 +9 @@\n-b\n+B\n")
        #expect(p.patch(forHunk: 2) == nil)
    }

    @Test func conflictRegionsParseAndResolve() {
        let text = "top\n<<<<<<< HEAD\nmine\n||||||| base\nold\n=======\ntheirs\n>>>>>>> feature\nend\n"
        let r = ConflictRegion.parse(text)
        #expect(r.count == 1)
        #expect(r[0].startLine == 2 && r[0].endLine == 8 && r[0].mine == ["mine"] && r[0].theirs == ["theirs"])
        #expect(r[0].mineLabel == "HEAD" && r[0].theirsLabel == "feature")
        func apply(_ e: Replacement) -> String { (text as NSString).replacingCharacters(in: e.range, with: e.text) }
        #expect(apply(r[0].resolution(.theirs, in: text)) == "top\ntheirs\nend\n")
        #expect(apply(r[0].resolution(.both, in: text)) == "top\nmine\ntheirs\nend\n")
    }

    private static let two = "a\n<<<<<<< HEAD\nm1\n=======\nt1\n>>>>>>> x\nb\n<<<<<<< HEAD\nm2\n=======\nt2a\nt2b\n>>>>>>> x\nc\n"

    @Test func resolveMixedChoices() {
        let t = Self.two
        #expect(ConflictRegion.resolve(t, choices: [.theirs, .both]) == "a\nt1\nb\nm2\nt2a\nt2b\nc\n")
        #expect(ConflictRegion.resolve(t, choices: [nil, .mine]) == "a\n<<<<<<< HEAD\nm1\n=======\nt1\n>>>>>>> x\nb\nm2\nc\n")
        #expect(ConflictRegion.resolve(t, choices: [.mine]) == ConflictRegion.resolve(t, choices: [.mine, nil]))
        #expect(ConflictRegion.resolve(t, choices: []) == t)
    }

    @Test func resolveAllMineMatchesRepeatedResolution() {
        var text = Self.two
        while let r = ConflictRegion.parse(text).first {
            let e = r.resolution(.mine, in: text)
            text = (text as NSString).replacingCharacters(in: e.range, with: e.text)
        }
        #expect(ConflictRegion.resolve(Self.two, choices: [.mine, .mine]) == text)
    }

    @Test func resolveEdgeCases() {
        #expect(ConflictRegion.resolve("a\n<<<<<<< H\nm\n=======\nt\n>>>>>>> x", choices: [.theirs]) == "a\nt")   // no final newline
        #expect(ConflictRegion.resolve("<<<<<<< H\n=======\nt\n>>>>>>> x\nz\n", choices: [.mine]) == "z\n")           // empty side
        #expect(ConflictRegion.resolve("<<<<<<< H\nm\n=======\n>>>>>>> x\nz\n", choices: [.theirs]) == "z\n")
    }

    @Test func segmentsSplitContextAndBlocks() {
        let s = ConflictRegion.segments(Self.two)
        #expect(s.count == 5)
        #expect(s[0] == .context(["a"]) && s[2] == .context(["b"]) && s[4] == .context(["c"]))
        guard case .conflict(1, let r) = s[3] else { Issue.record("expected the second block"); return }
        #expect(r.theirs == ["t2a", "t2b"])
        #expect(ConflictRegion.segments("x\ny\n") == [.context(["x", "y"])])
        #expect(ConflictRegion.segments("<<<<<<< H\nm\n=======\nt\n>>>>>>> x\n").count == 1)
    }

    @Test func hunksRevertToHead() {
        func roundTrip(_ base: String, _ current: String) -> String {
            var text = current
            // Reverting the last hunk first keeps the earlier hunks' line numbers valid.
            for h in GitGutterMarks.compute(base: base, current: current).hunks.reversed() {
                let e = h.revert(in: text)
                text = (text as NSString).replacingCharacters(in: e.range, with: e.text)
            }
            return text
        }
        for (base, current) in [
            ("a\nb\nc\n", "a\nB\nc\n"), ("a\nb\nc\n", "x\na\nc\nd\n"), ("a\nb", "a"), ("a", "a\nb"),
            ("a\nb\nc", "a\nB"), ("", "new\n"), ("x\ny\n", ""), ("a\nb\nc\nd\n", "a\nc\n"),
        ] {
            #expect(roundTrip(base, current) == base, "\(base.debugDescription) ← \(current.debugDescription)")
        }
        let m = GitGutterMarks.compute(base: "a\nb\nc\n", current: "a\nc\n")
        #expect(m.hunk(at: 1)?.oldLines == ["b"])
    }

    @Test func diffBetweenTexts() {
        let d = GitDiff.between("a\nb\nc\nd\ne\nf\ng\nh\ni\n", "a\nb\nc\nd\nE\nf\ng\nh\ni\n", context: 1)
        #expect(d.map(\.text) == ["@@ -4,3 +4,3 @@", "d", "e", "E", "f"])
        #expect(d.map(\.kind) == [.hunk, .context, .removed, .added, .context])
        #expect(GitDiff.between("same", "same").isEmpty)
    }
}

#if os(macOS)
@Suite(.serialized) @MainActor struct GitExtrasOperationTests {
    private let git = GitRunner(extraEnvironment: [
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
    ], timeout: 30)

    private func committed(_ text: String) async throws -> (Project, URL) {
        let (p, root) = try await TestEnv.project(files: ["main.typ": text])
        try await p.initRepository(git: git)
        try await p.commitAll("first", git: git)
        return (p, root)
    }

    @Test func blameOfTheBufferText() async throws {
        let (p, _) = try await committed("one\ntwo\n")
        let b = await p.blame(of: try #require(RelPath("main.typ")), text: "one\nnew\ntwo\n", git: git)
        #expect(b.count == 3)
        #expect(b[0].author == "Test" && b[0].summary == "first" && b[0].isCommitted)
        #expect(!b[1].isCommitted && b[2].isCommitted)
    }

    @Test func stageAndUnstageOneHunk() async throws {
        let lines = (1...20).map { "line \($0)" }
        let (p, root) = try await committed(lines.joined(separator: "\n") + "\n")
        var changed = lines
        changed[1] = "TWO"; changed[18] = "NINETEEN"
        try (changed.joined(separator: "\n") + "\n").write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        let unstaged = try await p.patch(of: "main.typ", staged: false, git: git)
        #expect(unstaged.hunks.count == 2)
        try await p.applyHunk(0, of: unstaged, unstage: false, git: git)
        let s = try await p.gitStatus(git: git)
        #expect(s.changes.first?.partlyStaged == true)
        let staged = try await p.patch(of: "main.typ", staged: true, git: git)
        #expect(staged.hunks.count == 1 && staged.hunks[0].contains("+TWO"))
        try await p.applyHunk(0, of: staged, unstage: true, git: git)
        #expect(try await p.gitStatus(git: git).changes.first?.staged == false)
    }

    @Test func stashPushListPop() async throws {
        let (p, root) = try await committed("one\n")
        try "two\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try "n\n".write(to: root.appending(path: "notes.typ"), atomically: true, encoding: .utf8)
        try await p.stash("wip", git: git)
        #expect(try await p.gitStatus(git: git).changes.isEmpty)
        let list = try await p.stashes(git: git)
        #expect(list.count == 1 && list[0].message.hasSuffix("wip"))
        try await p.applyStash(list[0], pop: true, git: git)
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "two\n")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "notes.typ").path))
        #expect(try await p.stashes(git: git).isEmpty)
    }

    @Test func stageOneHunkOfUnsavedText() async throws {
        let lines = (1...20).map { "line \($0)" }
        let (p, _) = try await committed(lines.joined(separator: "\n") + "\n")
        var changed = lines
        changed[1] = "TWO"; changed[18] = "NINETEEN"
        let text = changed.joined(separator: "\n") + "\n"          // only in the editor, never saved
        let path = try #require(RelPath("main.typ"))
        try await p.stageHunk(of: path, text: text, line: 19, git: git)
        let staged = try await p.patch(of: "main.typ", staged: true, git: git)
        #expect(staged.hunks.count == 1 && staged.hunks[0].contains("+NINETEEN") && !staged.hunks[0].contains("+TWO"))
        try await p.stageHunk(of: path, text: text, line: 2, git: git)
        let both = try await p.patch(of: "main.typ", staged: true, git: git)
        #expect(both.hunks.count == 2)
        await #expect(throws: GitError.self) { try await p.stageHunk(of: path, text: text, line: 2, git: git) }
    }

    @Test func undoAConflictingStashApply() async throws {
        let (p, root) = try await committed("base\n")
        try "stashed\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try await p.stash("wip", git: git)
        try "committed\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try await p.commitAll("other", git: git)
        let st = try #require(try await p.stashes(git: git).first)
        await #expect(throws: GitError.self) { try await p.applyStash(st, pop: true, git: git) }
        #expect(try await p.gitStatus(git: git).changes.first?.kind == .conflicted)
        #expect(!p.isMerging)
        try await p.undoStashApply(git: git)
        #expect(try await p.gitStatus(git: git).changes.isEmpty)
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "committed\n")
        #expect(try await p.stashes(git: git).count == 1)
    }

    @Test func mergeConflictKeepTheirsAndAbort() async throws {
        let (p, root) = try await committed("base\n")
        try await p.createBranch("other", git: git)
        try "theirs\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try await p.commitAll("theirs", git: git)
        try await p.switchBranch("main", git: git)
        try "mine\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try await p.commitAll("mine", git: git)
        _ = try? await git.run(["merge", "other"], in: root)
        #expect(p.isMerging)
        #expect(try await p.gitStatus(git: git).changes.first?.kind == .conflicted)
        let text = try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8)
        #expect(ConflictRegion.parse(text).first?.theirs == ["theirs"])
        try await p.resolveConflict("main.typ", keepingMine: false, git: git)
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "theirs\n")
        try await p.abortMerge(git: git)
        #expect(!p.isMerging)
        #expect(try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8) == "mine\n")
    }
    @Test func mergeEditorResolutionStagesTheFile() async throws {
        let (p, root) = try await committed("base\n")
        try await p.createBranch("other", git: git)
        try "theirs\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try await p.commitAll("theirs", git: git)
        try await p.switchBranch("main", git: git)
        try "mine\n".write(to: root.appending(path: "main.typ"), atomically: true, encoding: .utf8)
        try await p.commitAll("mine", git: git)
        _ = try? await git.run(["merge", "other"], in: root)
        let path = try #require(RelPath("main.typ"))
        await p.reloadChangedFiles()                    // the app does this on activation; the buffer still has "base"
        let text = try await p.open(path).storage.string
        #expect(ConflictRegion.parse(text).count == 1)
        let resolved = ConflictRegion.resolve(text, choices: [.both])
        try await p.edit(path, [Replacement(range: NSRange(location: 0, length: (text as NSString).length), text: resolved)], actionName: "Resolve Conflicts")
        let change = try #require(try await p.gitStatus(git: git).changes.first)
        try await p.stage([change], git: git)
        #expect(try await p.gitStatus(git: git).changes.allSatisfy { $0.kind != .conflicted })
        let disk = try String(contentsOf: root.appending(path: "main.typ"), encoding: .utf8)
        #expect(disk == "mine\ntheirs\n", "\(disk)")
    }
}
#endif
