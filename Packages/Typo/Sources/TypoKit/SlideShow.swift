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

extension PresentationClock {
    /// `HH:MM:SS` of the time elapsed, or with `duration` of the time left; past zero it counts on with a minus.
    public func readout(at now: Date, remainingOf duration: Int? = nil) -> String {
        let e = Int(elapsed(at: now)), s = duration.map { $0 - e } ?? e, a = abs(s)
        return (s < 0 ? "-" : "") + String(format: "%02d:%02d:%02d", a / 3600, a / 60 % 60, a % 60)
    }

    /// Seconds from `m`, `m:ss` or `h:mm:ss`; nil for anything else.
    public static func seconds(from text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        let n = parts.map { $0! }
        guard n.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return n.count == 1 ? n[0] * 60 : n.reduce(0) { $0 * 60 + $1 }
    }

    /// `mm:ss`, minutes not wrapped into hours, as the duration field shows it.
    public static func minutesSeconds(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
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
