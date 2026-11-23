import Darwin
import Foundation
import Synchronization
import ACPProtocol

/// An agent's process, spawned directly (never through a shell, whose dotfiles could print into the protocol) and
/// in its own process group, so `npx` → `node` → agent all stop together.
public final class ACPProcess: Sendable {
    public let pid: pid_t
    public let stdin: ACPPipeWriter
    public let stdout: FileHandle
    private let stderr = Mutex("")

    /// Running agents until reaped; `stopping` are being shut down on some thread.
    private struct Registry {
        var live: [pid_t: ACPProcess] = [:]
        var stopping: Set<pid_t> = []
    }
    private static let registry = Mutex(Registry())

    /// `tracked`: stopped by `shutdownAll` at quit, and the app may not be terminated suddenly meanwhile.
    public init(executable: String, arguments: [String], environment: [String: String], cwd: URL, tracked: Bool = true) throws(ACPError) {
        var fds: [[Int32]] = []
        for _ in 0..<3 {
            var p: [Int32] = [0, 0]
            guard pipe(&p) == 0 else { fds.joined().forEach { close($0) }; throw ACPError(ACPError.closed, "No pipe for the agent: \(String(cString: strerror(errno)))") }
            p.forEach { _ = fcntl($0, F_SETFD, FD_CLOEXEC) }
            fds.append(p)
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, fds[0][0], 0)
        posix_spawn_file_actions_adddup2(&actions, fds[1][1], 1)
        posix_spawn_file_actions_adddup2(&actions, fds[2][1], 2)
        posix_spawn_file_actions_addchdir(&actions, cwd.path)
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // CLOEXEC_DEFAULT: the agent of another window must not inherit this one's stdin, or closing it would not end the agent.
        // The spawning thread's blocked or ignored signals would carry over, and SIGTERM could not end the agent.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attr, 0)
        var none = sigset_t(), defaults = sigset_t()
        sigemptyset(&none)
        sigemptyset(&defaults)
        [SIGPIPE, SIGTERM, SIGINT, SIGHUP].forEach { sigaddset(&defaults, $0) }
        posix_spawnattr_setsigmask(&attr, &none)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &actions, &attr, argv, envp)
        // The child's ends: kept open here, the agent's death would never close its output.
        [fds[0][0], fds[1][1], fds[2][1]].forEach { close($0) }
        guard rc == 0 else {
            [fds[0][1], fds[1][0], fds[2][0]].forEach { close($0) }
            throw ACPError(ACPError.closed, "\((executable as NSString).lastPathComponent) could not be started: \(String(cString: strerror(rc))).")
        }
        self.pid = pid
        stdin = ACPPipeWriter(FileHandle(fileDescriptor: fds[0][1], closeOnDealloc: true))
        stdout = FileHandle(fileDescriptor: fds[1][0], closeOnDealloc: true)
        let errFD = FileHandle(fileDescriptor: fds[2][0], closeOnDealloc: true)
        // Drained all the time: a full stderr pipe would block the agent.
        Thread { [self] in
            var buf = [UInt8](repeating: 0, count: 4096)
            while case let n = read(errFD.fileDescriptor, &buf, buf.count), n != 0 {
                if n < 0 { if errno == EINTR { continue } else { break } }
                stderr.withLock { $0 = String(($0 + String(decoding: buf[0..<n], as: UTF8.self)).suffix(2000)) }
            }
        }.start()
        if tracked {
            ProcessInfo.processInfo.disableSuddenTermination()
            Self.registry.withLock { $0.live[pid] = self }
        }
    }

    /// The last lines the agent wrote to stderr, for error messages.
    public var lastError: String {
        stderr.withLock { $0 }.split(whereSeparator: \.isNewline).suffix(5).joined(separator: "\n")
    }

    /// Whether the group's leader has exited; it is not reaped, so its pid (the group id) cannot be reused meanwhile.
    var exited: Bool {
        var info = siginfo_t()
        return waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) != 0 || info.si_pid == pid
    }

    /// Closes stdin, then ends the whole group: SIGTERM, then SIGKILL. Blocks for up to two seconds.
    public func shutdown() { Self.stop([self]) }

    /// Every agent of the app, at once, including those a closed window is stopping in the background; for quitting.
    public static func shutdownAll() {
        stop(registry.withLock { Array($0.live.values) })
        let end = Date(timeIntervalSinceNow: 3)
        while Date() < end, !registry.withLock({ $0.live.isEmpty }) { usleep(20_000) }
        registry.withLock { $0.live.keys.forEach { kill(-$0, SIGKILL) } }
    }

    private static func stop(_ processes: [ACPProcess]) {
        let processes = registry.withLock { r in processes.filter { r.live[$0.pid] != nil && r.stopping.insert($0.pid).inserted } }
        guard !processes.isEmpty else { return }
        func wait(_ seconds: Double) {
            let end = Date(timeIntervalSinceNow: seconds)
            while Date() < end, !processes.allSatisfy(\.exited) { usleep(20_000) }
        }
        processes.forEach { $0.stdin.close() }
        wait(1)
        // Even when the leader left on its own, its children (node under npx) may still run.
        processes.forEach { kill(-$0.pid, SIGTERM) }
        wait(1)
        for p in processes {
            kill(-p.pid, SIGKILL)
            var status: Int32 = 0
            waitpid(p.pid, &status, 0)
            ProcessInfo.processInfo.enableSuddenTermination()
        }
        // Only now: the group id stays taken until the leader is reaped.
        registry.withLock { r in processes.forEach { r.live[$0.pid] = nil; r.stopping.remove($0.pid) } }
    }

    // MARK: Command line

    /// The words of a command line; single and double quotes group words with spaces.
    public static func words(_ line: String) -> [String] {
        var out: [String] = [], word = "", quote: Character?, inWord = false
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { word.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                inWord = true
            } else if ch.isWhitespace {
                if inWord { out.append(word); word = ""; inWord = false }
            } else {
                word.append(ch)
                inWord = true
            }
        }
        if inWord { out.append(word) }
        return out
    }

    /// The executable `name` names on `path`, or nil.
    public static func locate(_ name: String, path: String) -> String? {
        if name.contains("/") {
            let p = (name as NSString).expandingTildeInPath
            return FileManager.default.isExecutableFile(atPath: p) ? p : nil
        }
        return path.split(separator: ":").map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: PATH

    static let marker = "__TYPO_PATH__"
    private static let cachedPATH = Mutex<String?>(nil)

    /// The user's PATH, from their login shell once: an app opened from the Finder has only /usr/bin:/bin:/usr/sbin:/sbin,
    /// and npx lives wherever nvm or Homebrew put it. Slow; never call it on the main actor.
    public static func userPATH() -> String {
        if let p = cachedPATH.withLock({ $0 }) { return p }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? getpwuid(getuid()).map { String(cString: $0.pointee.pw_shell) } ?? "/bin/zsh"
        let path = loginPATH(shell: shell, arguments: ["-lic", "printf '\\n\(marker)%s\\n' \"$PATH\""])
            ?? (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin") + ":/opt/homebrew/bin:/usr/local/bin"
        cachedPATH.withLock { $0 = path }
        return path
    }

    /// The environment agents get: the app's, with the user's PATH.
    public static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = userPATH()
        return env
    }

    /// Runs `shell` and takes the PATH from the last marked line, so whatever the dotfiles print around it is ignored.
    /// Stops at the shell's exit or the timeout; a background job a dotfile left holding stdout is killed with the group.
    static func loginPATH(shell: String, arguments: [String], timeout: TimeInterval = 5) -> String? {
        guard let text = run(shell, arguments: arguments, environment: ProcessInfo.processInfo.environment, timeout: timeout)?.output else { return nil }
        let line = text.split(whereSeparator: \.isNewline).last { $0.hasPrefix(marker) }.map { String($0.dropFirst(marker.count)) }
        return line?.isEmpty == false ? line : nil
    }

    /// Runs `executable` in the home folder until it exits or the timeout passes: its exit status (nil when killed),
    /// stdout and the last lines of stderr.
    public static func run(_ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval) -> (status: Int32?, output: String, error: String)? {
        guard let p = try? ACPProcess(executable: executable, arguments: arguments, environment: environment,
                                      cwd: FileManager.default.homeDirectoryForCurrentUser, tracked: false) else { return nil }
        p.stdin.close()
        final class Collected: Sendable { let data = Mutex(Data()) }
        let out = Collected(), done = DispatchSemaphore(value: 0)
        Thread {
            var buf = [UInt8](repeating: 0, count: 4096)
            while case let n = read(p.stdout.fileDescriptor, &buf, buf.count), n != 0 {
                if n < 0 { if errno == EINTR { continue } else { break } }
                out.data.withLock { $0.append(contentsOf: buf[0..<n]) }
            }
            done.signal()
        }.start()
        let end = Date(timeIntervalSinceNow: timeout)
        while Date() < end, !p.exited { usleep(20_000) }
        kill(-p.pid, SIGKILL)
        _ = done.wait(timeout: .now() + 1)
        var status: Int32 = 0
        waitpid(p.pid, &status, 0)
        return (status & 0x7f == 0 ? (status >> 8) & 0xff : nil, String(decoding: out.data.withLock { $0 }, as: UTF8.self), p.lastError)
    }
}

extension ACPProcess {
    /// Runs the `claude` command line tool with the user's PATH: whether it succeeded, and what it printed; nil when
    /// it is not installed. Slow; never call it on the main actor.
    public static func claude(_ arguments: [String]) -> (ok: Bool, text: String)? {
        let env = environment()
        guard let exe = locate("claude", path: env["PATH"] ?? "") else { return nil }
        guard let r = run(exe, arguments: arguments, environment: env, timeout: 30) else { return (false, "claude could not be started.") }
        let text = [r.output, r.error].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
        return (r.status == 0, text)
    }
}
