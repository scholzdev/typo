# 14j Git integration

## Sandbox removal

Why: git must push with the user's own setup (system git, keys in `~/.ssh`, the SSH agent socket, `~/.gitconfig`). The App Sandbox blocks all of these, so the Mac build drops it. The package still builds for iOS, which stays sandboxed; core changes stay valid there.

What changed:
- `Typo.entitlements` and `project.yml` keep only `com.apple.security.network.client` (irrelevant unsandboxed). `ENABLE_APP_SANDBOX: NO`, `ENABLE_USER_SELECTED_FILES` removed. `codesign -d --entitlements -` on the build shows no `app-sandbox`.
- Container paths become real ones: `UserDefaults` moves from `~/Library/Containers/<bundle id>/Data/Library/Preferences/<bundle id>.plist` to `~/Library/Preferences/<bundle id>.plist`; Application Support and Caches move from `.../Data/Library/...` to `~/Library/...`.

Migration (`SandboxMigration.run`, `App.init`, before `RecentProjects()` exists): copies, never moves or deletes, so a sandboxed build keeps working.
- Source `~/Library/Containers/<bundle id>/Data` (bundle id from `Bundle.main`, so the debug variant uses its own container); target the real home from `getpwuid`.
- Every key of the container prefs plist missing in the standard defaults is set; existing keys win.
- `Library/Application Support/Typo` (snapshots) and `Library/Application Support/typst/packages` are merged into the home's `Library/Application Support`, skipping items that already exist.
- The key `TypstCore.sandboxMigrated` marks it done; later runs do nothing (also when there was nothing to copy).

Reopen fallback: bookmarks the sandboxed app stored do not resolve unsandboxed. `ScopedAccess(resolving:fallbackPath:)` then opens `rootPath` when it is an existing readable directory (no security scope) and reports it stale, so `Project.open` stores a fresh bookmark. A missing `rootPath` still throws `.accessDenied`. `RecentProjects.register` no longer fails when bookmark creation fails; it stores an empty bookmark, and `rootPath` reopens it.

Limits:
- The local packages folder keeps only a bookmark, no path. After the switch it does not resolve and is dropped; the user picks that folder once again.
- macOS TCC: an unsandboxed, ad-hoc-signed app reading `~/Documents`, `~/Desktop` or iCloud Drive gets a privacy prompt, possibly again after rebuilds change the signature.
- The old container is left in place; remove it by hand if wanted.

Tests: `SandboxMigrationTests` (keys and folders copied without overwriting, container unchanged, second run a no-op; garbage bookmark reopens by path and gets a fresh one; vanished root still `.accessDenied`).

## Changes tab

Sidebar tab "Changes" (`App/GitTab.swift`, core in `GitRunner.swift`, `GitProject.swift`, `GitParse.swift`; macOS only, parsers are iOS-safe).
- Not a repository (no `.git` in the project root): "Create Repository" runs `git init -b main`.
- Repository: branch, ↑ahead ↓behind, the changed files (letter M/A/D/R/?/! + path; click opens a resizable sheet (820×560) with a header (path, change kind) and the diff: monospaced 12 pt, no wrapping, horizontal scroll, old/new line numbers from the hunk headers, added lines green with +, removed red with −, hunk rows muted; binary files show "Binary file changed" (a NUL byte in the file's first 8000 bytes, as git decides), an empty diff "No textual changes"), a multi-line commit message, Commit, Commit & Push, Pull, Push. Without a remote, Push, Pull and Commit & Push are disabled, "No remote" shows with "Add Remote…" (a URL sheet; runs `git remote add origin <url>`).
- A spinner shows while a command runs; failures open an alert with git's stderr (stdout when stderr is empty, e.g. "nothing to commit"). The toolbar shows ↑n / ↓n next to the compile badge when non-zero.
- Refresh: on appear, on app activation, when `project.dirtyRevision` changes (saves), and after each operation. The refresh runs from the toolbar label, so the counts are current while the tab is hidden.
- Commit: `saveAll()`, `git add -A`, `git commit -m`. Push: `git push`, or `git push -u origin HEAD` when the branch has no upstream. Diff: `git diff HEAD -- path` (fallback `--cached` before the first commit); untracked files `git diff --no-index -- /dev/null path` (exit 1 is normal).

## Runner environment

The system git (first executable of `/opt/homebrew/bin/git`, `/usr/local/bin/git`, `/usr/bin/git`), run with an argument array (never a shell), cwd = project root, off the main thread, 120 s timeout. Environment: the process environment, `PATH` prefixed with `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin`, `GIT_TERMINAL_PROMPT=0`, `GIT_SSH_COMMAND="ssh -o BatchMode=yes"` (a passphrase or host-key prompt fails fast with stderr instead of hanging), `LC_ALL=C`. The user's own git config and `~/.ssh` apply. Tests inject a `GitRunner` with `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` and a test identity.

## Pull protocol

`Project.rewritingWorkingTree` (used by pull): pause autosave and drain writers, `saveAll()`, run git, `refreshFiles()` (clean open buffers take the new text; a buffer typed into since the save becomes a conflict with the usual banner; saves skip conflicted files, so the pulled text stays on disk), resume autosave, recompile. The same wrapper is the place for any future command that rewrites the tree (checkout, merge).

## Limits

- No branch or merge UI; pull is `--ff-only`, so diverged histories fail with git's message and must be resolved in a terminal.
- SSH keys with a passphrase work only when an agent holds them (`BatchMode`); an app started from Finder may lack `SSH_AUTH_SOCK`, then use a key without passphrase or start the app from a shell.
- A project nested inside another repository counts as "not a repository" (only a `.git` in the root counts).
- Unsandboxed access to `~/Documents`, `~/Desktop` or iCloud Drive triggers the macOS privacy prompt (see Sandbox removal).
- No `.gitignore` is created.

Tests: `GitTests.swift` (status and diff parsing from fixtures; init + commitAll + diff; commit saves open buffers; no remote errors; push to a local bare remote sets the upstream; pull into a clean open buffer updates it and a later saveAll keeps the disk text; a buffer edited during the pull becomes a conflict and the disk keeps the pulled text).
