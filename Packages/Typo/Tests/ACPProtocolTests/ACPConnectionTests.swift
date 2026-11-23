import Foundation
import Synchronization
import Testing
@testable import ACPProtocol
@testable import JSONRPC

private final class Collected<T: Sendable>: Sendable {
    let items = Mutex<[T]>([])
    func add(_ x: T) { items.withLock { $0.append(x) } }
    var all: [T] { items.withLock { $0 } }
}

/// Waits until `condition` holds, for up to five seconds.
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

/// Two connections on the ends of two pipes: `client` and an in-process fake agent `peer`.
private final class Pair: @unchecked Sendable {
    let toAgent = Pipe(), toClient = Pipe()
    let peer: ACPConnection, client: ACPConnection
    let peerOutput: ACPPipeWriter

    /// The peer answers requests like an agent: `echo/…` returns its `n`, anything else is unknown, and `slow` never answers in time.
    init() {
        peerOutput = ACPPipeWriter(toClient.fileHandleForWriting)
        peer = ACPConnection(input: toAgent.fileHandleForReading, output: peerOutput)
        client = ACPConnection(input: toClient.fileHandleForReading, output: ACPPipeWriter(toAgent.fileHandleForWriting))
        peer.start(handler: { method, params in
            switch method {
            case let m where m.hasPrefix("echo/"): return .success(["n": params["n"] ?? nil])
            case "slow":
                try? await Task.sleep(for: .seconds(30))
                return .success(.null)
            default: return .failure(ACPError(ACPError.methodNotFound, method))
            }
        }, onNotification: { _, _ in })
    }

    func hangUp() { peerOutput.close() }
}

@Suite(.timeLimit(.minutes(1))) struct ACPConnectionTests {
    @Test func linesSplitAcrossReadsAndJoinedInOneRead() async throws {
        let toClient = Pipe(), sink = Pipe()
        let seen = Collected<String>()
        let c = ACPConnection(input: toClient.fileHandleForReading, output: ACPPipeWriter(sink.fileHandleForWriting))
        c.start(handler: { _, _ in .success(.null) }, onNotification: { m, p in seen.add("\(m):\(p["t"]?.string ?? "")") })
        let w = toClient.fileHandleForWriting
        try w.write(contentsOf: Data(#"{"jsonrpc":"2.0","method":"a","params":{"t":"x "#.utf8))
        try await Task.sleep(for: .milliseconds(20))
        try w.write(contentsOf: Data("y\"}}\n{\"jsonrpc\":\"2.0\",\"method\":\"b\",\"params\":{\"t\":\"z\"}}\n".utf8))
        #expect(await eventually { seen.all.count == 2 })
        #expect(seen.all == ["a:x\u{2028}y", "b:z"])
    }

    @Test func concurrentRequestsBothWays() async throws {
        let pair = Pair()
        let fromAgent = Collected<Int>()
        pair.client.start(handler: { method, params in
            fromAgent.add(params["n"]?.int ?? -1)
            return .success(["echo": .string(method)])
        }, onNotification: { _, _ in })
        let client = pair.client, peer = pair.peer
        try await withThrowingTaskGroup(of: Void.self) { g in
            for n in 0..<10 {
                g.addTask {
                    let r = try await client.request("echo/\(n)", ["n": .int(n)])
                    #expect(r["n"]?.int == n)
                }
                g.addTask {
                    let r = try await peer.request("ask/\(n)", ["n": .int(n)])
                    #expect(r["echo"]?.string == "ask/\(n)")
                }
            }
            try await g.waitForAll()
        }
        #expect(Set(fromAgent.all) == Set(0..<10))
    }

    @Test func endOfOutputFailsPendingRequests() async throws {
        let pair = Pair()
        let client = pair.client
        client.start(handler: { _, _ in .success(.null) }, onNotification: { _, _ in })
        let pending = Task { try await client.request("slow", [:]) }
        try await Task.sleep(for: .milliseconds(50))
        pair.hangUp()
        await #expect(throws: ACPError(ACPError.closed, "The agent stopped.")) { try await pending.value }
        #expect(client.isClosed)
        await #expect(throws: ACPError.self) { try await client.request("later", [:]) }
    }

    @Test func closedReasonComesFromTheCallback() async throws {
        let toClient = Pipe(), sink = Pipe()
        let c = ACPConnection(input: toClient.fileHandleForReading, output: ACPPipeWriter(sink.fileHandleForWriting)) { "boom" }
        c.start(handler: { _, _ in .success(.null) }, onNotification: { _, _ in })
        let pending = Task { try await c.request("x", [:]) }
        try await Task.sleep(for: .milliseconds(50))
        try toClient.fileHandleForWriting.close()
        await #expect(throws: ACPError(ACPError.closed, "boom")) { try await pending.value }
    }

    @Test func unknownMethodIsMethodNotFound() async throws {
        let pair = Pair()
        pair.client.start(handler: { _, _ in .failure(ACPError(ACPError.methodNotFound, "no")) }, onNotification: { _, _ in })
        let e = await #expect(throws: ACPError.self) { try await pair.peer.request("terminal/create", [:]) }
        #expect(e?.code == ACPError.methodNotFound)
    }

    @Test func notificationsReachTheHandlerInOrder() async throws {
        let pair = Pair()
        let seen = Collected<String>()
        pair.client.start(handler: { _, _ in .success(.null) }, onNotification: { m, _ in seen.add(m) })
        for m in ["a", "b", "c"] { pair.peer.notify(m, [:]) }
        #expect(await eventually { seen.all.count == 3 })
        #expect(seen.all == ["a", "b", "c"])
    }
}

@Suite struct ACPToolCallTests {
    @Test func updatesReplaceOnlyTheFieldsTheyCarry() {
        var c = ACPToolCall(id: "a")
        c.merge(["title": "Edit a", "kind": "edit", "status": "pending", "locations": [["path": "/p/a.typ"]], "rawInput": ["x": 1]])
        #expect(c.changesFiles && c.locations == ["/p/a.typ"])
        c.merge(["status": "completed", "content": [["type": "diff"]], "rawInput": nil])
        #expect(c.title == "Edit a" && c.kind == "edit" && c.status == "completed" && c.content.count == 1 && c.rawInput == ["x": 1])
        #expect(!ACPToolCall(id: "r").changesFiles)
    }
}
