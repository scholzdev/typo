#if os(macOS)
import Foundation

public enum GitError: Error, LocalizedError {
    case notInstalled, noRemote, timedOut(String), failed(String)
    public var errorDescription: String? {
        switch self {
        case .notInstalled: String(localized: "git was not found (looked in /opt/homebrew/bin, /usr/local/bin and /usr/bin).", bundle: .module)
        case .noRemote: String(localized: "No remote is configured. Add a remote first.", bundle: .module)
        case .timedOut(let c): String(localized: "git \(c) did not finish in time.", bundle: .module)
        case .failed(let m): m
        }
    }
}

private final class Box: @unchecked Sendable { var err = Data(); var fired = false }   // written before the group/exit that orders the read

/// What every run adds to git's environment (the accounts' credentials); behind a lock, runs start on any thread.
private final class SharedEnvironment: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String: String] = [:]
    var current: [String: String] {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}
private let shared = SharedEnvironment()

/// Runs the system git with an argument array (never a shell). `extraEnvironment` is for tests only.
public struct GitRunner: Sendable {
    public var extraEnvironment: [String: String]
    public var timeout: TimeInterval
    public init(extraEnvironment: [String: String] = [:], timeout: TimeInterval = 120) {
        self.extraEnvironment = extraEnvironment
        self.timeout = timeout
    }

    /// Set by `GitAccountStore.apply()`; under `extraEnvironment`, so tests stay isolated.
    public static var sharedEnvironment: [String: String] {
        get { shared.current }
        set { shared.current = newValue }
    }

    static var executable: URL? {
        ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"].map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" + (env["PATH"].map { ":" + $0 } ?? "")
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"   // a passphrase or host-key prompt fails with stderr instead of hanging
        env["LC_ALL"] = "C"
        return env.merging(Self.sharedEnvironment) { _, new in new }.merging(extraEnvironment) { _, new in new }
    }

    /// stdout on success; on a non-zero exit the error carries stderr (stdout when stderr is empty). `okStatuses` are also success.
    /// `input` is written to git's stdin (for `apply -` and `blame --contents -`).
    public func run(_ args: [String], in dir: URL, okStatuses: Set<Int32> = [0], input: String? = nil) async throws -> String {
        guard let exe = Self.executable else { throw GitError.notInstalled }
        let env = environment, timeout = timeout
        let (status, out, err, timedOut) = await withCheckedContinuation { (c: CheckedContinuation<(Int32, String, String, Bool), Never>) in
            DispatchQueue.global().async {
                let p = Process(), o = Pipe(), e = Pipe(), i = Pipe()
                p.executableURL = exe; p.arguments = args; p.currentDirectoryURL = dir; p.environment = env
                p.standardOutput = o; p.standardError = e; p.standardInput = input == nil ? FileHandle.nullDevice : i
                do { try p.run() } catch { c.resume(returning: (-1, "", error.localizedDescription, false)); return }
                if let input {
                    // Written on its own queue: a large input must not block while git fills stdout.
                    DispatchQueue.global().async {
                        try? i.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                        try? i.fileHandleForWriting.close()
                    }
                }
                let box = Box()
                let killer = DispatchWorkItem { box.fired = true; p.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let drained = DispatchGroup()
                drained.enter()
                DispatchQueue.global().async { box.err = e.fileHandleForReading.readDataToEndOfFile(); drained.leave() }
                let outData = o.fileHandleForReading.readDataToEndOfFile()
                drained.wait()
                p.waitUntilExit()
                killer.cancel()
                c.resume(returning: (p.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: box.err, as: UTF8.self), box.fired))
            }
        }
        if timedOut { throw GitError.timedOut(args.first ?? "") }
        guard okStatuses.contains(status) else {
            let m = (err.isEmpty ? out : err).trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.failed(m.isEmpty ? "git \(args.first ?? "") failed (exit \(status))." : m)
        }
        return out
    }
}
#endif
