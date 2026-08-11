import Foundation
import VigilSupport

/// Calls `ActivityCoordinator.evaluate()` as time passes, and nothing else.
///
/// The coordinator deliberately owns no timer so it stays a pure function of its
/// inputs; this is the one piece that knows about the passage of time. It sleeps
/// until the coordinator's own `nextDeadline` rather than polling, so an idle
/// Vigil wakes at most once a minute.
public actor CoordinatorDriver {
    /// Longest nap when nothing is scheduled. A wakeup a minute costs nothing
    /// and bounds the damage if a deadline is ever miscomputed.
    private static let idleInterval: TimeInterval = 60

    private let coordinator: ActivityCoordinator
    private let clock: Clock
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Error>?

    public init(coordinator: ActivityCoordinator, clock: Clock = SystemClock()) {
        self.coordinator = coordinator
        self.clock = clock
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.waitForNextDeadline()
                guard !Task.isCancelled else { return }
                await self.coordinator.evaluate()
            }
        }
    }

    /// Recomputes the sleep. Call after feeding the coordinator anything, or the
    /// driver keeps napping on a deadline computed before the new signal existed
    /// — which delays a release by up to `idleInterval`. The grace period is
    /// user-visible, so it must not depend on when the last nap happened to start.
    public func nudge() {
        sleeper?.cancel()
    }

    public func stop() {
        sleeper?.cancel()
        sleeper = nil
        loop?.cancel()
        loop = nil
    }

    private func waitForNextDeadline() async {
        let deadline = await coordinator.nextDeadline
        let cap = clock.now.addingTimeInterval(Self.idleInterval)
        let wake = min(deadline ?? cap, cap)

        let sleeper = Task { [clock] in try await clock.sleep(until: wake) }
        self.sleeper = sleeper
        // A nudge cancels the sleep; that is a wake-up, not a failure, so the
        // result is deliberately discarded and the loop simply recomputes.
        _ = await sleeper.result
        self.sleeper = nil
    }

    deinit {
        sleeper?.cancel()
        loop?.cancel()
    }
}
