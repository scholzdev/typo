import Foundation
import Testing
@testable import TypoAssistant

struct AgentAccessTests {
    let access = AgentAccess(commands: ["cat", "cargo check", "/bin/ls", "git status", "cd"])

    @Test func splitReadsQuotesAndSeparators() {
        #expect(AgentAccess.split("cat main.typ") == [["cat", "main.typ"]])
        #expect(AgentAccess.split("grep -rn 'a b' \"c d\" e\\ f") == [["grep", "-rn", "a b", "c d", "e f"]])
        #expect(AgentAccess.split("cd x && cat y; ls | wc -l || true & z\nw") == [["cd", "x"], ["cat", "y"], ["ls"], ["wc", "-l"], ["true"], ["z"], ["w"]])
        #expect(AgentAccess.split("grep ';' a\"|\"b") == [["grep", ";", "a|b"]])
        #expect(AgentAccess.split("echo \"a \\\"b\\\" $HOME\"") == [["echo", "a \"b\" $HOME"]])
        #expect(AgentAccess.split("cat a\r\nrm -rf b") == [["cat", "a"], ["rm", "-rf", "b"]])
    }

    @Test func splitRefusesWhatItCantVouchFor() {
        for line in ["", "   ", ";", "cat a > b", "cat < a", "cargo check 2>&1", "cat $(ls)", "grep \"$(rm -rf x)\" f", "cat `ls`",
                     "echo \"`id`\"", "(cd x; rm y)", "cat 'unclosed", "cat \"unclosed", "cat a # comment", "cat a\\"] {
            #expect(AgentAccess.split(line) == nil, "\(line)")
        }
        // Inside single quotes nothing is special.
        #expect(AgentAccess.split("grep '$(x) > `y`' f") == [["grep", "$(x) > `y`", "f"]])
    }

    @Test func entriesMatchByWordPrefix() {
        #expect(access.rules(for: "cat main.typ") == ["cat"])
        #expect(access.rules(for: "cat") == ["cat"])
        #expect(access.rules(for: "cargo check --all") == ["cargo check"])
        #expect(access.rules(for: "cargo build") == nil)
        #expect(access.rules(for: "cargo") == nil)
        #expect(access.rules(for: "catalog x") == nil)
        #expect(access.rules(for: "git status --short") == ["git status"])
        #expect(access.rules(for: "git push") == nil)
        #expect(access.rules(for: "'cat' x") == ["cat"])
        #expect(access.rules(for: "") == nil)
        #expect(access.rules(for: nil) == nil)
    }

    @Test func programsCompareAsWritten() {
        #expect(access.rules(for: "/bin/ls -la") == ["/bin/ls"])
        #expect(access.rules(for: "ls -la") == nil)
        #expect(access.rules(for: "/bin/cat x") == nil)
        #expect(access.rules(for: "/tmp/evil/cat x") == nil)
        #expect(access.rules(for: "./cat x") == nil)
    }

    @Test func compoundCommandsNeedEveryPart() {
        #expect(access.rules(for: "cd ch && cat a.typ") == ["cd", "cat"])
        #expect(access.rules(for: "cat a; cat b") == ["cat"])
        #expect(access.rules(for: "cat main.typ; rm -rf x") == nil)
        #expect(access.rules(for: "cat a | sh") == nil)
        #expect(access.rules(for: "cat a > b") == nil)
        #expect(access.rules(for: "cat $(rm -rf x)") == nil)
    }

    @Test func shellWrappersAreUnwrapped() {
        #expect(access.rules(for: "bash -lc 'cat main.typ'") == ["cat"])
        #expect(access.rules(for: "/bin/zsh -c \"cd x && cat y\"") == ["cd", "cat"])
        #expect(access.rules(for: "bash -lc 'rm -rf x'") == nil)
        #expect(access.rules(for: "bash -c 'cat a' extra") == nil)
        #expect(access.rules(for: "bash script.sh") == nil)
    }

    @Test func alwaysAllowSuggestsProgramAndSubcommand() {
        #expect(AgentAccess.suggestion(for: ["cat", "main.typ"]) == "cat")
        #expect(AgentAccess.suggestion(for: ["cargo", "check", "--all"]) == "cargo check")
        #expect(AgentAccess.suggestion(for: ["cargo", "--version"]) == "cargo")
        #expect(AgentAccess.suggestion(for: ["git", "status"]) == "git status")
        let r = AgentAccess.Request(kind: "execute", title: "", command: "cat a && cargo test -q && rm x")
        #expect(access.additions(for: r, root: "/p").commands == ["cargo test", "rm"])
        var a = access
        a.remember(r, root: "/p")
        #expect(a.rules(for: "cargo test --all") == ["cargo test"])
        #expect(a.commands == a.commands.sorted())
        // Nothing to add for a line the policy can't read.
        #expect(access.additions(for: AgentAccess.Request(kind: "execute", title: "", command: "cat > x"), root: "/p").commands == [])
    }

    @Test func quoteRoundTrips() {
        for words in [["a"], ["a b", "it's", ""], ["$(x)", "`y`", "a;b"]] {
            #expect(AgentAccess.split(AgentAccess.quote(words)) == [words])
        }
    }

    @Test func containmentResolvesDotsAndSymlinks() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agent-access-\(UUID().uuidString)")
        let proj = tmp.appendingPathComponent("proj"), other = tmp.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("proj2"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createSymbolicLink(at: proj.appendingPathComponent("out"), withDestinationURL: other)
        let p = proj.path
        #expect(AgentAccess.contains(p + "/main.typ", in: p))
        #expect(AgentAccess.contains(p + "/new/dir/file.typ", in: p))
        #expect(AgentAccess.contains(p, in: p))
        #expect(!AgentAccess.contains(p + "/../other/x", in: p))
        #expect(!AgentAccess.contains(p + "2/x", in: p))
        #expect(!AgentAccess.contains(p + "/out/secret", in: p))
        #expect(AgentAccess.contains(p + "/out/secret", in: other.path))
        #expect(!AgentAccess.contains("main.typ", in: p))
        // /var is /private/var: either spelling is inside.
        #expect(AgentAccess.contains("/private" + p + "/a", in: p) || !p.hasPrefix("/var"))
    }

    @Test func fileAccessFollowsTheToggleAndFolders() {
        let root = "/nonexistent-proj"
        var a = AgentAccess(folders: ["/nonexistent-shared"])
        #expect(a.fileAccess(root + "/a.typ", root: root) == .allow("the project"))
        #expect(a.fileAccess("/nonexistent-shared/x/y.bib", root: root) == .allow("/nonexistent-shared"))
        #expect(a.fileAccess("/etc/hosts", root: root) == .ask)
        #expect(a.fileAccess("/nonexistent-proj2/a", root: root) == .ask)
        a.controlsFiles = false
        #expect(a.fileAccess("/etc/hosts", root: root) == .reject("outside the project"))
        #expect(a.fileAccess(root + "/a.typ", root: root) == .allow("the project"))
        // Always Allow adds the file's folder.
        let r = AgentAccess.Request(kind: "read", title: "", paths: ["/nonexistent-elsewhere/refs.bib"])
        #expect(AgentAccess().additions(for: r, root: root).folders == ["/nonexistent-elsewhere"])
    }

    @Test func decisions() {
        let root = "/nonexistent-proj"
        func decide(_ kind: String?, _ title: String = "", command: String? = nil, paths: [String] = [], changeFiles: PermissionPolicy = .ask, _ a: AgentAccess? = nil) -> AgentAccess.Decision {
            (a ?? access).decide(.init(kind: kind, title: title, command: command, paths: paths), root: root, changeFiles: changeFiles)
        }
        #expect(decide("execute", command: "cat main.typ") == .allow("cat"))
        #expect(decide("execute", command: "rm -rf x") == .ask)
        #expect(decide("execute", command: nil) == .ask)
        #expect(decide("other", "typo: read_file") == .allow("Typo's own tools"))
        #expect(decide("other", "typo: view_preview") == .ask)
        #expect(decide("edit", paths: [root + "/a.typ"], changeFiles: .allow) == .allow("Change files: Allow"))
        #expect(decide("edit", paths: [root + "/a.typ"]) == .ask)
        #expect(decide("delete", paths: [root + "/a.typ"], changeFiles: .never) == .reject("Change files: Never"))
        // Outside the project an edit asks even when changes are allowed, unless the folder is allowed or control is off.
        #expect(decide("edit", paths: ["/etc/hosts"], changeFiles: .allow) == .ask)
        #expect(decide("move", paths: [root + "/a", "/etc/b"], changeFiles: .allow) == .ask)
        #expect(decide("edit", paths: ["/etc/hosts"], changeFiles: .allow, AgentAccess(folders: ["/etc"])) == .allow("Change files: Allow"))
        #expect(decide("edit", paths: ["/etc/hosts"], changeFiles: .allow, AgentAccess(controlsFiles: false)) == .allow("Change files: Allow"))
        #expect(decide("fetch", "Fetch https://typst.app") == .ask)
        #expect(decide("fetch", "Fetch", AgentAccess(web: .allow)) == .allow("Web Access: Allow"))
        #expect(decide("other", "WebSearch: typst tables", AgentAccess(web: .never)) == .reject("Web Access: Never"))
        #expect(decide("read", paths: [root + "/a"]) == .ask)
        #expect(decide(nil) == .ask)
    }
}
