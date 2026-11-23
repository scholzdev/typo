import Foundation
import Testing
@testable import ACPProtocol
@testable import TypoACP
@testable import TypoAssistant

/// A start that waits until `open` is called.
private final class Gate: Sendable {
    let s = AsyncStream<Void>.makeStream()
    func wait() async { for await _ in s.stream { return } }
    func open() { s.continuation.yield(); s.continuation.finish() }
}

@MainActor @Suite(.timeLimit(.minutes(1))) struct ACPWarmupTests {
    @Test func startsOnceAndBecomesReady() async {
        let w = ACPWarmup(), gate = Gate(), runs = Collected<Int>()
        #expect(w.state == .idle)
        #expect(w.warm("a") { runs.add(1); await gate.wait() })
        #expect(w.state == .starting)
        #expect(!w.warm("a") { runs.add(2) })    // the same target again: nothing new starts
        gate.open()
        #expect(await eventually { w.state == .ready })
        #expect(!w.warm("a") { runs.add(3) })
        #expect(runs.all == [1])
    }

    @Test func aFailedStartSaysWhy() async {
        let w = ACPWarmup()
        w.warm("a") { throw ACPError(ACPError.authRequired, "Log in first.") }
        #expect(await eventually { w.state == .failed("Log in first.") })
        // Another target, such as another agent, tries again.
        w.warm("b") {}
        #expect(await eventually { w.state == .ready })
    }

    @Test func cancelledStartEndsIdle() async {
        let w = ACPWarmup(), gate = Gate(), done = Collected<Bool>()
        w.warm("a") { await gate.wait(); done.add(true) }
        w.cancel()
        #expect(w.state == .idle)
        gate.open()
        #expect(await eventually { done.all == [true] })
        #expect(w.state == .idle)
        // After cancel the same target starts again.
        #expect(w.warm("a") {})
        #expect(await eventually { w.state == .ready })
    }

    @Test func anotherTargetReplacesAStartingOne() async {
        let w = ACPWarmup(), gate = Gate()
        w.warm("a") { await gate.wait(); throw ACPError(ACPError.internalError, "late") }
        w.warm("b") {}
        #expect(await eventually { w.state == .ready })
        gate.open()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(w.state == .ready)    // the replaced start's failure doesn't count
    }

    /// The warm session takes the mode picked before sending, and the first turn reuses it.
    @Test func firstTurnReusesTheWarmSessionInItsMode() async throws {
        let fakes = Collected<FakeAgent>()
        let sessions = ACPSessions()
        var p = AssistantProvider(preset: AssistantPreset.named("acp-claude")!)
        p.command = "npx agent"
        func client(mode: String?) -> ACPClient {
            ACPClient(provider: p, sessions: sessions, attachments: [], mode: mode) {
                let f = FakeAgent(modes: ["default", "plan", "acceptEdits"]) { _, _ in ["stopReason": "end_turn"] }
                fakes.add(f)
                return try await f.agent(host: nil)
            }
        }
        let warm = try await client(mode: "plan").warm(session: "d", model: "")
        #expect(warm.options.modes?.choices.map(\.id) == ["default", "plan", "acceptEdits"])
        #expect(await eventually { fakes.all.first?.notes.all.contains("set_mode:plan") == true })
        // The mode menu before the first message.
        await sessions.running("d")?.select(mode: "acceptEdits")
        #expect(warm.options.modes?.current == "acceptEdits")

        var r = AssistantRequest(model: "", system: "", files: nil, messages: [.init(role: .user, text: "q")])
        r.session = "d"
        for try await _ in client(mode: "acceptEdits").stream(r) {}
        #expect(fakes.all.count == 1)
        #expect(await sessions.running("d") === warm)
    }

    /// A window that shows a warm session later still gets its commands.
    @Test func theAgentKeepsItsCommands() async throws {
        let fake = FakeAgent()
        let agent = try await fake.agent(host: nil)
        fake.peer.notify("session/update", ["sessionId": "s1", "update": ["sessionUpdate": "available_commands_update",
                                                                         "availableCommands": [["name": "compact", "description": "Summarize"]]]])
        #expect(await eventually { agent.commands.map(\.name) == ["compact"] })
    }

    @Test func closingWhileStartingLeavesNoAgent() async throws {
        let sessions = ACPSessions(), gate = Gate()
        var p = AssistantProvider(preset: AssistantPreset.named("acp-claude")!)
        p.command = "npx agent"
        let client = ACPClient(provider: p, sessions: sessions, attachments: []) {
            await gate.wait()
            return try await FakeAgent().agent(host: nil)
        }
        let warming = Task { try await client.warm(session: "d", model: "") }
        try await Task.sleep(for: .milliseconds(50))
        sessions.close("d")
        gate.open()
        _ = try? await warming.value
        #expect(await sessions.running("d") == nil)
    }
}
