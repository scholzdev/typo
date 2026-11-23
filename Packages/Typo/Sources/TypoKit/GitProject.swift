import TypstEngine
#if os(macOS)
import Foundation

/// Git on a project's folder; design/14j-git.md. `git` is injectable for tests.
extension Project {
    public var isRepository: Bool { FileManager.default.fileExists(atPath: rootURL.appending(path: ".git").path) }

    /// `git init` with the first branch named `defaultBranch` (Settings › Source Control); "main" when that is not a valid name.
    public func initRepository(defaultBranch: String = "main", git: GitRunner = GitRunner()) async throws {
        let branch = GitBranchName.isValid(defaultBranch) ? defaultBranch : "main"
        _ = try await git.run(["init", "-b", branch], in: rootURL)
    }

    public func gitStatus(git: GitRunner = GitRunner()) async throws -> GitStatus {
        GitStatus(porcelainV2: try await git.run(["status", "--porcelain=v2", "--branch", "-z"], in: rootURL))
    }

    public func hasRemote(git: GitRunner = GitRunner()) async throws -> Bool {
        !(try await git.run(["remote"], in: rootURL)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func addRemote(_ url: String, git: GitRunner = GitRunner()) async throws {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty, !u.hasPrefix("-") else { throw GitError.failed("Enter a repository URL.") }
        _ = try await git.run(["remote", "add", "origin", u], in: rootURL)
    }

    public func diff(of change: GitChange, git: GitRunner = GitRunner()) async throws -> [DiffLine] {
        if change.kind == .untracked {
            return GitDiff.parse(try await git.run(["diff", "--no-index", "--", "/dev/null", change.path], in: rootURL, okStatuses: [0, 1]))
        }
        do { return GitDiff.parse(try await git.run(["diff", "HEAD", "--", change.path], in: rootURL)) }
        catch { return GitDiff.parse(try await git.run(["diff", "--cached", "--", change.path], in: rootURL)) }   // no commit yet
    }

    public func commitAll(_ message: String, git: GitRunner = GitRunner()) async throws {
        try await saveAll()
        _ = try await git.run(["add", "-A"], in: rootURL)
        _ = try await git.run(["commit", "-m", message], in: rootURL)
    }

    /// Whether HEAD names a commit; false in a fresh repository.
    public func hasCommits(git: GitRunner = GitRunner()) async throws -> Bool {
        !(try await git.run(["rev-parse", "--verify", "-q", "HEAD"], in: rootURL, okStatuses: [0, 1])).isEmpty
    }

    /// `git add` for the given changes (also stages deletions and resolves conflicts), after saving so the open text is what gets staged.
    public func stage(_ changes: [GitChange], git: GitRunner = GitRunner()) async throws {
        guard !changes.isEmpty else { return }
        try await saveAll()
        _ = try await git.run(["add", "-A", "--"] + changes.map(\.path), in: rootURL)
    }

    /// Takes the changes out of the index again; the working tree is untouched. A staged rename also frees its origin.
    public func unstage(_ changes: [GitChange], git: GitRunner = GitRunner()) async throws {
        let paths = changes.flatMap { [$0.path] + ($0.oldPath.map { [$0] } ?? []) }
        guard !paths.isEmpty else { return }
        if try await hasCommits(git: git) {
            _ = try await git.run(["restore", "--staged", "--"] + paths, in: rootURL)
        } else {
            _ = try await git.run(["rm", "--cached", "-r", "-q", "--ignore-unmatch", "--"] + paths, in: rootURL)
        }
    }

    /// Commits only what is staged.
    public func commitStaged(_ message: String, git: GitRunner = GitRunner()) async throws {
        _ = try await git.run(["commit", "-m", message], in: rootURL)
    }

    public func branches(git: GitRunner = GitRunner()) async throws -> [GitBranch] {
        GitBranch.parse(try await git.run(["for-each-ref", "--format=%(HEAD)%00%(refname:short)", "refs/heads"], in: rootURL))
    }

    /// The short commit HEAD points at (shown when no branch is checked out); nil without commits.
    public func shortHead(git: GitRunner = GitRunner()) async -> String? {
        try? await git.run(["rev-parse", "--short", "HEAD"], in: rootURL).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checks out `name`; git refuses when uncommitted changes would be lost, and that message is the error.
    public func switchBranch(_ name: String, git: GitRunner = GitRunner()) async throws {
        try await rewritingWorkingTree { _ = try await git.run(["switch", "--", name], in: self.rootURL) }
    }

    /// Creates `name` at HEAD and switches to it; the working tree and index stay as they are.
    public func createBranch(_ name: String, git: GitRunner = GitRunner()) async throws {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !n.hasPrefix("-") else { throw GitError.failed("Enter a branch name.") }
        do { _ = try await git.run(["check-ref-format", "--branch", n], in: rootURL) }
        catch { throw GitError.failed("“\(n)” is not a valid branch name.") }
        _ = try await git.run(["switch", "-c", n], in: rootURL)
    }

    /// The commits that touched `path`, newest first, following renames.
    public func history(of path: String, limit: Int = 200, git: GitRunner = GitRunner()) async throws -> [GitCommit] {
        guard try await hasCommits(git: git) else { return [] }
        return GitCommit.parse(try await git.run(["-c", "core.quotePath=false", "log", "--follow", "-M", "--name-only", "-n", String(limit),
                                                  GitCommit.logFormat, "--", path], in: rootURL))
    }

    /// What `commit` changed in its version of the file.
    public func diff(of commit: GitCommit, git: GitRunner = GitRunner()) async throws -> [DiffLine] {
        GitDiff.parse(try await git.run(["show", "--format=", "-M", "--root", commit.hash, "--", commit.path], in: rootURL))
    }

    /// From the file as of `commit` to its text on disk now (`path` is the current name).
    public func diff(from commit: GitCommit, toWorkingCopyOf path: String, git: GitRunner = GitRunner()) async throws -> [DiffLine] {
        try await saveAll()
        return GitDiff.parse(try await git.run(["diff", "-M", commit.hash, "--", commit.path, path], in: rootURL))
    }

    /// The file's text in HEAD for the gutter marks; nil outside a repository, before the first commit and for a
    /// file HEAD does not have (untracked or new), which then shows no marks.
    public func headText(of path: RelPath, git: GitRunner = GitRunner()) async -> String? {
        guard isRepository else { return nil }
        return try? await git.run(["show", "HEAD:./" + path.raw], in: rootURL)
    }

    /// The file's text in the current branch's upstream, for gutter marks that include upstream changes; nil
    /// without an upstream or when the upstream does not have the file.
    public func upstreamText(of path: RelPath, git: GitRunner = GitRunner()) async -> String? {
        guard isRepository else { return nil }
        return try? await git.run(["show", "@{upstream}:./" + path.raw], in: rootURL)
    }

    /// Settings' "Add and remove files automatically": stages items the app created, renamed or trashed, so the
    /// index follows the file list. Each path on its own, as one that is gone and was never tracked fails.
    public func track(_ paths: [RelPath], git: GitRunner = GitRunner()) async {
        guard isRepository else { return }
        for p in Set(paths) { _ = try? await git.run(["add", "-A", "--", p.raw], in: rootURL) }
    }

    // MARK: Blame

    /// Who last changed each line of `text` (the buffer as it is now, so unsaved lines show as not committed).
    /// Empty outside a repository, before the first commit and for files HEAD does not have.
    public func blame(of path: RelPath, text: String, git: GitRunner = GitRunner()) async -> [GitBlameLine] {
        guard isRepository, let out = try? await git.run(["blame", "--porcelain", "--contents", "-", "--", path.raw], in: rootURL, input: text)
        else { return [] }
        return GitBlame.parse(out)
    }

    // MARK: Hunks

    /// The file's diff against the index (`staged` false: what could be staged) or of the index against HEAD
    /// (`staged` true: what could be unstaged), saved first so disk matches the editor.
    public func patch(of path: String, staged: Bool, git: GitRunner = GitRunner()) async throws -> GitPatch {
        try await saveAll()
        return GitPatch(try await git.run(["diff"] + (staged ? ["--cached"] : []) + ["--", path], in: rootURL))
    }

    /// Stages hunk `i` of an unstaged patch, or unstages it from a staged one.
    public func applyHunk(_ i: Int, of patch: GitPatch, unstage: Bool, git: GitRunner = GitRunner()) async throws {
        guard let text = patch.patch(forHunk: i) else { throw GitError.failed("That change is no longer there.") }
        _ = try await git.run(["apply", "--cached", "--recount"] + (unstage ? ["--reverse"] : []) + ["-"], in: rootURL, input: text)
    }

    /// Stages the change at `line` of `text` (the editor's text, saved or not) and nothing else: the index gets its
    /// current version of the file with just that hunk made, written as a blob, so the working tree is untouched.
    public func stageHunk(of path: RelPath, text: String, line: Int, git: GitRunner = GitRunner()) async throws {
        let index = (try? await git.run(["show", ":./" + path.raw], in: rootURL)) ?? ""   // not in the index yet: empty
        guard let hunk = GitGutterMarks.compute(base: index, current: text).hunk(at: line) else {
            throw GitError.failed("This change is already staged.")
        }
        let blob = try await git.run(["hash-object", "-w", "--stdin", "--path", path.raw], in: rootURL, input: hunk.apply(to: index))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = (try? await git.run(["ls-files", "-s", "--", path.raw], in: rootURL)) ?? ""
        let mode = entry.split(separator: " ").first.map(String.init) ?? "100644"
        _ = try await git.run(["update-index", "--add", "--cacheinfo", "\(mode),\(blob),\(path.raw)"], in: rootURL)
    }

    // MARK: Stash

    public func stashes(git: GitRunner = GitRunner()) async throws -> [GitStash] {
        GitStash.parse(try await git.run(["stash", "list", GitStash.listFormat], in: rootURL))
    }

    /// Puts every change (untracked files too) aside; the working tree is then clean at HEAD.
    public func stash(_ message: String, git: GitRunner = GitRunner()) async throws {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        try await rewritingWorkingTree {
            _ = try await git.run(["stash", "push", "--include-untracked"] + (m.isEmpty ? [] : ["-m", m]), in: self.rootURL)
        }
    }

    /// Brings a stash back; `pop` also drops it when it applied cleanly. A clash leaves conflicts to resolve.
    public func applyStash(_ s: GitStash, pop: Bool, git: GitRunner = GitRunner()) async throws {
        try await rewritingWorkingTree { _ = try await git.run(["stash", pop ? "pop" : "apply", s.ref], in: self.rootURL) }
    }

    public func dropStash(_ s: GitStash, git: GitRunner = GitRunner()) async throws {
        _ = try await git.run(["stash", "drop", s.ref], in: rootURL)
    }

    // MARK: Conflicts

    /// A merge in progress that Abort can undo.
    public var isMerging: Bool {
        FileManager.default.fileExists(atPath: rootURL.appending(path: ".git/MERGE_HEAD").path)
    }

    /// Takes one side of a conflicted file whole and marks it resolved. Mine is the checked-out side (HEAD); theirs
    /// is the one coming in (the merged branch, or the stash being applied).
    public func resolveConflict(_ path: String, keepingMine: Bool, git: GitRunner = GitRunner()) async throws {
        try await rewritingWorkingTree {
            _ = try await git.run(["checkout", keepingMine ? "--ours" : "--theirs", "--", path], in: self.rootURL)
            _ = try await git.run(["add", "--", path], in: self.rootURL)
        }
    }

    /// Undoes a stash apply that ran into conflicts: files go back to HEAD. The stash itself stays (a pop that
    /// conflicts does not drop it), so it can be applied again later.
    public func undoStashApply(git: GitRunner = GitRunner()) async throws {
        try await rewritingWorkingTree { _ = try await git.run(["reset", "--merge"], in: self.rootURL) }
    }

    public func abortMerge(git: GitRunner = GitRunner()) async throws {
        try await rewritingWorkingTree { _ = try await git.run(["merge", "--abort"], in: self.rootURL) }
    }

    public func push(git: GitRunner = GitRunner()) async throws {
        guard try await hasRemote(git: git) else { throw GitError.noRemote }
        let hasUpstream = try await gitStatus(git: git).upstream != nil
        _ = try await git.run(hasUpstream ? ["push"] : ["push", "-u", "origin", "HEAD"], in: rootURL)
    }

    /// Updates the remote-tracking branches (and so ahead/behind) without touching the working tree.
    public func fetch(git: GitRunner = GitRunner()) async throws {
        guard try await hasRemote(git: git) else { throw GitError.noRemote }
        _ = try await git.run(["fetch", "--quiet"], in: rootURL)
    }

    public func pull(git: GitRunner = GitRunner()) async throws {
        guard try await hasRemote(git: git) else { throw GitError.noRemote }
        try await rewritingWorkingTree { _ = try await git.run(["pull", "--ff-only"], in: self.rootURL) }
    }

    /// Save all, hold autosave off, run `body` (which may rewrite files), then reload what changed: a clean buffer
    /// takes the new text, one typed into meanwhile becomes a conflict instead of being overwritten.
    func rewritingWorkingTree(_ body: () async throws -> Void) async throws {
        autosavePauses += 1
        defer {
            autosavePauses -= 1
            if autosavePauses == 0, hasUnsavedChanges { scheduleAutosave() }
        }
        autosave?.cancel()
        autosave = nil
        await waitForSaves()
        try await saveAll()
        await waitForSaves()
        do { try await body() } catch { await refreshFiles(); engine.send(.recompile); throw error }
        await refreshFiles()
        engine.send(.recompile)
    }
}
#endif
