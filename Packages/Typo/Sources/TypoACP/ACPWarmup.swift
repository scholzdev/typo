import Foundation
import Observation
import ACPProtocol

/// Starting a new conversation's agent before its first message, so its mode and model menus and its commands show
/// at once. One target at a time: another target replaces it, and the same target runs only once.
@MainActor @Observable public final class ACPWarmup {
    public enum State: Equatable, Sendable { case idle, starting, ready, failed(String) }

    public private(set) var state = State.idle
    private var target: String?
    private var task: Task<Void, Never>?

    public init() {}

    /// Runs `start` for `target` unless it runs or ran already; returns whether it started.
    @discardableResult public func warm(_ target: String, _ start: @escaping @MainActor () async throws -> Void) -> Bool {
        guard target != self.target else { return false }
        task?.cancel()
        self.target = target
        state = .starting
        task = Task { [weak self] in
            do {
                try await start()
                if !Task.isCancelled { self?.state = .ready }
            } catch {
                if !Task.isCancelled { self?.state = .failed((error as? ACPError)?.message ?? error.localizedDescription) }
            }
        }
        return true
    }

    /// Forgets the target; a start still running ends without changing the state.
    public func cancel() {
        task?.cancel()
        task = nil
        target = nil
        state = .idle
    }
}
