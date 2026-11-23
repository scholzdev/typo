import Foundation

/// A stopwatch for a talk. It reads no clock itself: every call gets the current time.
public struct PresentationClock: Equatable, Sendable {
    private var banked: TimeInterval = 0
    private var since: Date?

    public init() {}

    public var isRunning: Bool { since != nil }
    /// Never started since creation or the last reset.
    public var isUntouched: Bool { since == nil && banked == 0 }

    public func elapsed(at now: Date) -> TimeInterval { banked + (since.map { now.timeIntervalSince($0) } ?? 0) }
    public mutating func start(at now: Date) { if since == nil { since = now } }
    public mutating func pause(at now: Date) { banked = elapsed(at: now); since = nil }
    public mutating func toggle(at now: Date) { if isRunning { pause(at: now) } else { start(at: now) } }
    public mutating func reset() { self = PresentationClock() }
}

/// Which slide a presentation shows, and its clock. The page count is passed in because the document can change underneath.
public struct SlideShow: Equatable, Sendable {
    private var page: Int
    public var clock = PresentationClock()

    public init(page: Int = 0) { self.page = page }

    /// The current page, clamped to `0..<count` (0 when there are no pages).
    public func current(count: Int) -> Int { min(max(page, 0), max(count - 1, 0)) }

    /// Moves to `target`, clamped; the first move starts an untouched clock.
    public mutating func go(to target: Int, count: Int, at now: Date) {
        let next = min(max(target, 0), max(count - 1, 0))
        if next != current(count: count), clock.isUntouched { clock.start(at: now) }
        page = next
    }

    public mutating func move(by delta: Int, count: Int, at now: Date) { go(to: current(count: count) + delta, count: count, at: now) }
}
