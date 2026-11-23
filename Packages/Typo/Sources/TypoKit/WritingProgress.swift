import Foundation
import TypstEngine

/// The word goal of a project and the count it started the day with. Pure; `ProgressStore` persists it.
public struct WritingProgress: Codable, Equatable, Sendable {
    /// Nil: no goal.
    public var goal: Int?
    private var day: String?
    private var dayStart: Int?

    public init(goal: Int? = nil) { self.goal = goal }

    /// Remembers the first count seen on each calendar day.
    public mutating func record(total: Int, on date: Date, calendar: Calendar = .current) {
        let key = Self.key(date, calendar)
        if day != key { day = key; dayStart = total }
    }

    /// Words written since the day's first count (negative when text was deleted); 0 before any count.
    public func today(total: Int) -> Int { dayStart.map { total - $0 } ?? 0 }

    /// 0...1 toward the goal; nil without one.
    public func fraction(total: Int) -> Double? {
        guard let goal, goal > 0 else { return nil }
        return min(1, max(0, Double(total) / Double(goal)))
    }

    private static func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}

/// Stores one project's `WritingProgress` under "Tympan.progress.<project id>".
public struct ProgressStore: Sendable {
    nonisolated(unsafe) private let defaults: UserDefaults
    private let key: String

    public init(_ id: ProjectID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // persisted key, kept from the app's old name so saved data survives
        key = "Tympan.progress.\(id.raw)"
    }

    public func load() -> WritingProgress {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WritingProgress.self, from: $0) } ?? WritingProgress()
    }

    public func save(_ p: WritingProgress) {
        defaults.set(try? JSONEncoder().encode(p), forKey: key)
    }
}
