import Foundation
import Synchronization
import JSONRPC

public typealias ACPError = JSONRPCError

extension JSONRPCError {
    public static let authRequired = -32000, notFound = -32002
    /// The agent's process ended or its output closed.
    public static let closed = -1
}

/// The write end of a pipe, which one thread may close while another writes: the descriptor cannot be reused meanwhile.
public final class ACPPipeWriter: Sendable {
    private let fd: Mutex<Int32>

    /// Takes over `handle`'s descriptor; the handle is closed.
    public init(_ handle: FileHandle) {
        let d = dup(handle.fileDescriptor)
        try? handle.close()
        _ = fcntl(d, F_SETNOSIGPIPE, 1)    // a dead agent fails the write instead of killing the app
        _ = fcntl(d, F_SETFD, FD_CLOEXEC)
        fd = Mutex(d)
    }

    func write(_ data: Data) {
        fd.withLock { fd in
            data.withUnsafeBytes { buf in
                var at = 0
                while fd >= 0, at < buf.count {
                    let n = Darwin.write(fd, buf.baseAddress! + at, buf.count - at)
                    if n < 0 { if errno == EINTR { continue } else { return } }    // EPIPE: the reader sees the end and fails what is pending
                    at += n
                }
            }
        }
    }

    /// Ends the peer's input. Skipped while a write blocks on a full pipe (the agent is not reading); the caller kills it then.
    public func close() {
        fd.withLockIfAvailable { fd in
            if fd >= 0 { Darwin.close(fd) }
            fd = -1
        }
    }

    deinit { fd.withLock { if $0 >= 0 { Darwin.close($0) } } }
}

/// One JSON-RPC 2.0 peer over a pair of pipes, one message per line. Lines are handled in order on one reader
/// thread: notifications go to `onNotification` synchronously, so a response never overtakes the updates before it.
public final class ACPConnection: Sendable {
    public typealias Handler = @Sendable (_ method: String, _ params: JSONValue) async -> Result<JSONValue, ACPError>

    private struct State {
        var nextID = 1
        var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
        var closed: ACPError?
        var handler: Handler?
        var onNotification: (@Sendable (String, JSONValue) -> Void)?
    }

    private let input: FileHandle
    private let output: ACPPipeWriter
    private let state = Mutex(State())
    /// Why the peer went away, asked when the output closes (the agent's last stderr lines).
    private let closedReason: @Sendable () -> String

    public init(input: FileHandle, output: ACPPipeWriter, closedReason: @escaping @Sendable () -> String = { "The agent stopped." }) {
        self.input = input
        self.output = output
        self.closedReason = closedReason
    }

    public var isClosed: Bool { state.withLock { $0.closed != nil } }

    /// Starts reading; incoming requests go to `handler`, notifications to `onNotification`.
    public func start(handler: @escaping Handler, onNotification: @escaping @Sendable (String, JSONValue) -> Void) {
        state.withLock { $0.handler = handler; $0.onNotification = onNotification }
        let thread = Thread { [self] in readLoop() }
        thread.name = "ACP reader"
        thread.start()
    }

    public func request(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        try await withCheckedThrowingContinuation { k in
            let id: Int? = state.withLock { s in
                guard s.closed == nil else { return nil }
                defer { s.nextID += 1 }
                s.pending[s.nextID] = k
                return s.nextID
            }
            guard let id else { return k.resume(throwing: state.withLock { $0.closed! }) }
            send(["jsonrpc": "2.0", "id": .int(id), "method": .string(method), "params": params])
        }
    }

    public func notify(_ method: String, _ params: JSONValue) {
        send(["jsonrpc": "2.0", "method": .string(method), "params": params])
    }

    private func send(_ message: JSONValue) {
        var data = message.json
        data.append(0x0A)
        output.write(data)
    }

    private func readLoop() {
        let fd = input.fileDescriptor
        JSONRPCLines.read(fd) { line in
            if let message = try? JSONValue(json: line) { dispatch(message) }
        }
        let error = ACPError(ACPError.closed, closedReason())
        let waiting = state.withLock { s in
            s.closed = error
            defer { s.pending = [:] }
            return Array(s.pending.values)
        }
        for k in waiting { k.resume(throwing: error) }
    }

    private func dispatch(_ m: JSONValue) {
        if let method = m["method"]?.string {
            let params = m["params"] ?? .null
            guard let id = m["id"] else {
                state.withLock { $0.onNotification }?(method, params)
                return
            }
            guard let handler = state.withLock({ $0.handler }) else { return }
            Task {
                switch await handler(method, params) {
                case .success(let result): send(["jsonrpc": "2.0", "id": id, "result": result])
                case .failure(let e): send(["jsonrpc": "2.0", "id": id, "error": ["code": .int(e.code), "message": .string(e.message)]])
                }
            }
        } else if let id = m["id"]?.int, let k = state.withLock({ $0.pending.removeValue(forKey: id) }) {
            if let e = m["error"] {
                k.resume(throwing: ACPError(e["code"]?.int ?? ACPError.internalError, e["message"]?.string ?? "The agent reported an error."))
            } else {
                k.resume(returning: m["result"] ?? .null)
            }
        }
    }
}
