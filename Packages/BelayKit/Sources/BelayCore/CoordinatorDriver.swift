import BelaySupport
import Foundation

/// The slice of `ActivityCoordinator` the driver actually uses.
///
/// It buys one thing the concrete actor cannot: a coordinator that *suspends*
/// inside `nextDeadline`. The real one never does, so the window this file
/// guards — deadline read, actor released, sleeper not yet installed — is
/// unreachable from a test that drives the real coordinator.
public protocol DrivableCoordinator: Sendable {
    var nextDeadline: Date? { get async }
    @discardableResult func evaluate() async -> AwakeDecision
}

extension ActivityCoordinator: DrivableCoordinator {}

/// Calls `ActivityCoordinator.evaluate()` as time passes, and nothing else.
///
/// The coordinator deliberately owns no timer so it stays a pure function of its
/// inputs; this is the one piece that knows about the passage of time. It sleeps
/// until the coordinator's own `nextDeadline` rather than polling, so an idle
/// Belay wakes at most once a minute.
public actor CoordinatorDriver {
    /// Longest nap when nothing is scheduled. A wakeup a minute costs nothing
    /// and bounds the damage if a deadline is ever miscomputed.
    private static let idleInterval: TimeInterval = 60

    private let coordinator: any DrivableCoordinator
    private let clock: Clock
    private var loop: Task<Void, Never>?
    private var sleeper: Task<Void, Error>?
    /// Bumped by every nudge. `waitForNextDeadline` stamps it before reading the
    /// deadline and checks it after, which is what makes a nudge that lands in
    /// that gap a wake-up rather than a lost signal.
    private var generation: UInt64 = 0

    public init(coordinator: any DrivableCoordinator, clock: Clock = SystemClock()) {
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
        generation &+= 1
        sleeper?.cancel()
    }

    public func stop() {
        sleeper?.cancel()
        sleeper = nil
        loop?.cancel()
        loop = nil
    }

    private func waitForNextDeadline() async {
        let stamp = generation
        let deadline = await coordinator.nextDeadline
        // Reading the deadline releases the actor, so a nudge can land here —
        // cancelling a sleeper that does not exist yet. Returning lets the loop
        // evaluate immediately, which is the whole point of a nudge; without it
        // the signal waits out a fresh nap of up to `idleInterval`.
        guard stamp == generation else { return }
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
