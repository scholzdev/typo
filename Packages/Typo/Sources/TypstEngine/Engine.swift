import Foundation
import Synchronization

public enum EngineMessage: Sendable {
    case setText(RelPath, String, Seq)    // open or resync a buffer
    case edit(Edit)
    case setMain(RelPath)
    case setProjectFonts([String])        // absolute paths of the project's font files
    /// A file or folder moved on disk: the overlays re-created under their new paths, the main re-pointed.
    case relocate(from: RelPath, to: RelPath, overlays: [RelPath], Seq)
    case drop([RelPath], Seq)                // buffers closed: their overlays go, disk is read again
    case recompile                        // the package store changed: compile again, no edit
    case complete(CompletionRequest)
    case click(ClickRequest)
    case cursor(CursorRequest)
    case hover(HoverRequest)
    case definition(DefinitionRequest)
    case signatureHelp(SignatureHelpRequest)

    /// Requests of one kind supersede each other: completion per file, click, cursor and hover globally.
    fileprivate enum RequestKey: Hashable { case complete(RelPath), completeText, click, cursor, hover, definition, signatureHelp }
    fileprivate var requestKey: RequestKey? {
        switch self {
        case .complete(let r): r.text == nil ? .complete(r.file) : .completeText
        case .click: .click
        case .cursor: .cursor
        case .hover: .hover
        case .definition: .definition
        case .signatureHelp: .signatureHelp
        default: nil
        }
    }

    /// Resumes a request with nil. Other messages are not requests.
    fileprivate func refuse() {
        switch self {
        case .complete(let r): r.reply(nil)
        case .click(let r): r.reply(nil)
        case .cursor(let r): r.reply(nil)
        case .hover(let r): r.reply(nil)
        case .definition(let r): r.reply(nil)
        case .signatureHelp(let r): r.reply(nil)
        default: break
        }
    }
}

/// `reply` is called exactly once, on any thread: with the answer, or nil when superseded, diverged,
/// without overlay, out of range, or the engine closed.
public struct CompletionRequest: Sendable {
    let file: RelPath
    let cursor: Int
    let explicit: Bool
    /// Complete this text as the content of `file` instead of the stored one (nothing is stored).
    var text: String? = nil
    let reply: @Sendable (CompletionAnswer?) -> Void
    public init(file: RelPath, cursor: Int, explicit: Bool, text: String? = nil, reply: @escaping @Sendable (CompletionAnswer?) -> Void) { self.file = file; self.cursor = cursor; self.explicit = explicit; self.text = text; self.reply = reply }
}

public struct CompletionAnswer: Sendable {
    public let from: Int
    public let seq: Seq                          // the file's text when answered includes every edit <= seq
    public let items: [CompletionItem]
}

public enum EngineEvent: Sendable {
    case status(CompileStatus)
    case compiled(CompileResult)
    case diverged(Set<RelPath>)           // tb_world_edit returned false: resend full text
}

/// Owns the TbWorld. Runs on its own serial queue, so a 2 s package download blocks that queue
/// and never a cooperative-pool thread. One Engine per project.
public actor Engine {
    private let queue = DispatchSerialQueue(label: "typstcore.engine", qos: .userInitiated)
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let world: WorldHandle                           // touched only on `queue`
    private let inbox = Mutex(Inbox())                       // FIFO, the only cross-thread state
    private struct Inbox { var messages: [EngineMessage] = []; var drainScheduled = false; var closed = false }
    private var appliedSeq = Seq(raw: 0)
    private var main: RelPath
    private var diverged: Set<RelPath> = []
    private var latest: CompileResult?
    private(set) var compileCount = 0
    /// On Save mode: edits reach the world but compile only on `.recompile` (a save), `flush()`, or the first compile.
    private let deferEdits = Mutex(false)
    private var stale = false                                // edits applied since the last compile
    public nonisolated let events: AsyncStream<EngineEvent>
    private nonisolated let sink: AsyncStream<EngineEvent>.Continuation

    public init(runtime: TypstRuntime, root: URL, main: RelPath) throws(ProjectError) {
        let (events, sink) = AsyncStream.makeStream(of: EngineEvent.self)
        guard let world = WorldHandle(runtime: runtime, root: root, main: main, onDownload: {
            sink.yield(.status(.downloading(package: $0)))
        }) else { throw .mainFileMissing(main) }
        self.world = world
        self.main = main
        self.events = events
        self.sink = sink
    }

    deinit { sink.finish() }

    /// Synchronous and non-blocking from the main actor: lock, append, maybe schedule one drain.
    /// FIFO order is the lock order, which is the order of the caller's calls.
    public nonisolated func send(_ m: EngineMessage) { send([m]) }

    /// One lock: the messages are guaranteed to land in the same drain batch.
    public nonisolated func send(_ ms: [EngineMessage]) {
        let schedule = inbox.withLock { s in
            if s.closed { return nil as Bool? }
            s.messages += ms
            defer { s.drainScheduled = true }
            return !s.drainScheduled
        }
        guard let schedule else { Self.refuse(ms); return }
        if schedule { Task { await self.drain() } }
    }

    public nonisolated func setDefersEdits(_ on: Bool) {
        deferEdits.withLock { $0 = on }
        if !on { send(.recompile) }
    }

    /// Stops accepting messages and answers queued requests with nil.
    public nonisolated func close() {
        let left = inbox.withLock { s in
            s.closed = true
            defer { s.messages = [] }
            return s.messages
        }
        Self.refuse(left)
    }

    private nonisolated static func refuse(_ ms: [EngineMessage]) {
        for m in ms { m.refuse() }
    }

    private func takeBatch() -> [EngineMessage]? {
        inbox.withLock { s in
            if s.messages.isEmpty { s.drainScheduled = false; return nil }
            defer { s.messages = [] }
            return s.messages
        }
    }

    /// Coalescing loop. Takes everything queued, applies it in order, compiles once, and repeats until
    /// the inbox is empty. Ten keystrokes during one compile become one compile, and none is dropped.
    private func drain() {
        while let batch = takeBatch() {
            // Only the newest request per kind (per file for completion) is answered; each is answered at its
            // own position, so it sees exactly the text its cursor was computed against, still ahead of
            // this batch's compile.
            var newest: [EngineMessage.RequestKey: Int] = [:]
            for (i, m) in batch.enumerated() { if let k = m.requestKey { newest[k] = i } }
            var dirty = false
            let deferring = deferEdits.withLock { $0 }
            for (i, m) in batch.enumerated() {
                guard let key = m.requestKey else {
                    apply(m)
                    if case .edit = m, deferring { stale = true } else { dirty = true }
                    continue
                }
                guard newest[key] == i else { m.refuse(); continue }
                switch m {
                case .complete(let r): r.reply(answer(r))
                case .click(let r): r.reply(answer(r))
                case .cursor(let r): r.reply(answer(r))
                case .hover(let r): r.reply(answer(r))
                case .definition(let r): r.reply(answer(r))
                case .signatureHelp(let r): r.reply(answer(r))
                default: break
                }
            }
            if !diverged.isEmpty { sink.yield(.diverged(diverged)); continue }   // never compile a wrong mirror
            if dirty || (stale && latest == nil) { compile() }
        }
    }

    private func compile() {
        sink.yield(.status(.compiling))
        let r = CompileResult(seq: appliedSeq, snapshot: world.compile(), main: main, serial: compileCount + 1)
        compileCount += 1
        stale = false
        latest = r
        sink.yield(.compiled(r))
        sink.yield(.status(.idle))
    }

    private func apply(_ m: EngineMessage) {
        switch m {
        case .setText(let path, let text, let seq):
            world.setText(path, text)
            diverged.remove(path)
            appliedSeq = max(appliedSeq, seq)
        case .edit(let e):
            appliedSeq = max(appliedSeq, e.seq)
            guard !diverged.contains(e.file) else { return }
            if !world.edit(e.file, e.range, e.replacement, expectedLength: e.newLength) { diverged.insert(e.file) }
        case .setMain(let path):
            main = path
            world.setMain(path)
        case .setProjectFonts(let paths):
            world.setProjectFonts(paths)
        case .relocate(let old, let new, let overlays, let seq):
            appliedSeq = max(appliedSeq, seq)
            for p in overlays {
                guard let moved = p.replacing(old, with: new) else { continue }
                world.relocateOverlay(p, moved)
                if diverged.remove(p) != nil { diverged.insert(moved) }
            }
            if let moved = main.replacing(old, with: new) {
                main = moved
                world.setMain(moved)
            }
        case .drop(let paths, let seq):
            appliedSeq = max(appliedSeq, seq)
            for p in paths {
                world.removeOverlay(p)
                diverged.remove(p)
            }
        case .recompile, .complete, .click, .cursor, .hover, .definition, .signatureHelp:
            break
        }
    }

    private func answer(_ r: CompletionRequest) -> CompletionAnswer? {
        guard r.text != nil || !diverged.contains(r.file),
              let c = world.complete(r.file, text: r.text, cursor: r.cursor, explicit: r.explicit) else { return nil }
        return CompletionAnswer(from: c.from, seq: appliedSeq, items: c.items)
    }

    private func answer(_ r: ClickRequest) -> ClickAnswer? {
        let target = world.jumpFromClick(shown: r.shown, page: r.page, point: r.point)
        if case .file(let f, _) = target, diverged.contains(f) { return nil }   // its offset is in a stale mirror
        return ClickAnswer(seq: appliedSeq, target: target)
    }

    private func answer(_ r: CursorRequest) -> CursorAnswer? {
        guard !diverged.contains(r.file) else { return nil }
        return CursorAnswer(seq: appliedSeq, positions: world.jumpFromCursor(r.file, cursor: r.cursor))
    }

    private func answer(_ r: HoverRequest) -> HoverAnswer? {
        guard !diverged.contains(r.file) else { return nil }
        return HoverAnswer(seq: appliedSeq, tip: world.hover(r.file, cursor: r.cursor),
                           equation: world.equationImage(r.file, cursor: r.cursor, pixelsPerPoint: r.pixelsPerPoint))
    }

    private func answer(_ r: DefinitionRequest) -> DefinitionAnswer? {
        guard !diverged.contains(r.file) else { return nil }
        return DefinitionAnswer(seq: appliedSeq, definition: world.definition(r.file, cursor: r.cursor))
    }

    private func answer(_ r: SignatureHelpRequest) -> SignatureHelpAnswer? {
        guard !diverged.contains(r.file) else { return nil }
        return SignatureHelpAnswer(help: world.signatureHelp(r.file, cursor: r.cursor))
    }

    /// Drains now and returns the result that covers every message sent before this call.
    public func flush() -> CompileResult? {
        drain()
        if latest == nil || stale { compile() }
        return latest
    }

    /// Test support: holds the engine queue until `gate` is signaled.
    func stall(_ gate: DispatchSemaphore) { gate.wait() }

    /// Test support: the Rust overlay text of `path`.
    func overlayText(_ path: RelPath) -> String? { world.text(of: path) }
}
