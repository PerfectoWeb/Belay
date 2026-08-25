import BelaySupport
import Foundation

/// The decision layer: signals in, hold-or-release out.
///
/// Deliberately free of timers, I/O and wall-clock reads. `evaluate()` is a pure
/// function of (recorded signals, policy, power conditions, `clock.now`), which
/// is what lets the suite drive hours of behaviour in milliseconds. Something
/// has to call it as time passes — that is `CoordinatorDriver`'s only job.
public actor ActivityCoordinator {
    // `internal` where `private` reads truer: the timer half of this actor
    // lives in `ActivityCoordinatorTimer.swift` for the file-length rule, and
    // Swift's `private` stops at the file. Isolation still guards them all.
    let clock: Clock
    private var policy: AwakePolicy
    private var power: PowerConditions = .unknown
    private var ledger = SessionLedger()

    /// Last moment any session was working or awaiting. The grace period is
    /// measured from here, so it survives sessions being evicted underneath it.
    private var lastActiveAt: Date?
    private var holdingSince: Date?
    /// Set when the max-duration cap fires; cleared only once work actually
    /// stops, otherwise we would release and immediately re-hold forever.
    var capTripped = false
    /// The user's "stay on this long". Needs no tripped latch of its own: a
    /// deadline in the past stays in the past until `holdAgain` moves it.
    var timer: AlwaysOnTimer?

    /// The reason survives the grace period unchanged. Swapping it to
    /// "cooling down" the moment a turn ends would re-emit a decision on every
    /// pause between two tool calls, which is exactly the churn docs/08 forbids.
    private var lastHoldReason: HoldReason?
    private var emitted: (holding: Bool, reason: HoldReason?) = (false, nil)
    private var subscribers: [UUID: AsyncStream<AwakeDecision>.Continuation] = [:]

    public private(set) var snapshot: CoordinatorSnapshot = .idle

    public init(clock: Clock = SystemClock(), policy: AwakePolicy = .default) {
        self.clock = clock
        self.policy = policy
    }

    public func decisions() -> AsyncStream<AwakeDecision> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AwakeDecision>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        return stream
    }

    @discardableResult
    public func ingest(_ signal: ActivitySignal) -> AwakeDecision {
        let now = clock.now
        ledger.record(signal, now: now)
        return evaluate()
    }

    public func setPolicy(_ policy: AwakePolicy) {
        // The timer is a property of one stay in Always on, not of the mode
        // switch itself: leaving the mode ends it, and coming back starts
        // plain "until turned off" rather than resuming a stale countdown.
        if policy.mode != .alwaysOn { timer = nil }
        self.policy = policy
        evaluate()
    }

    public func setPowerConditions(_ conditions: PowerConditions) {
        power = conditions
        evaluate()
    }

    /// Forgets everything and re-derives from scratch. Called after a wake from
    /// sleep, where every timestamp we hold is meaningless (docs/04).
    public func resync() {
        ledger.removeAll()
        lastActiveAt = nil
        capTripped = false
        // `holdingSince` too: without this it survives the sleep, so in Always
        // on the awake-limit counts the hours the Mac spent asleep and trips the
        // moment it wakes (hold 09:00, sleep 10:00, wake 14:30, cap 4h →
        // suspended after one real hour). Clearing it lets the same evaluate()
        // re-stamp it in `commit` — the fresh cap cycle a wake is meant to give.
        holdingSince = nil
        evaluate()
    }

    /// The earliest time the decision could change with no further input, so the
    /// driver can sleep exactly that long instead of polling.
    public var nextDeadline: Date? {
        let now = clock.now
        var candidates: [Date] = []
        if let lastActiveAt {
            candidates.append(lastActiveAt + policy.effectiveGrace(lowPower: power.isLowPowerMode))
        }
        if let holdingSince, let cap = policy.maxContinuousAwake {
            candidates.append(holdingSince + cap)
        }
        if policy.mode == .alwaysOn, let timer {
            candidates.append(timer.deadline)
        }
        candidates.append(contentsOf: ledger.deadlines(policy: policy))
        return candidates.filter { $0 > now }.min()
    }

    @discardableResult
    public func evaluate() -> AwakeDecision {
        let now = clock.now
        ledger.prune(now: now, policy: policy)
        let activities = ledger.refreshDerived(now: now, policy: policy)

        let (desired, desiredState) = desiredHold(now: now, activities: activities)

        // Reset the cap on what the session state *wants*, not on what the gates
        // allow. Resetting after a gate cleared the reason would let the cap
        // re-arm on the very next tick and never actually cap anything.
        if desired == nil {
            capTripped = false
            lastHoldReason = nil
        }

        var reason = desired
        var state = desiredState
        if reason != nil, let suspension = suspension(now: now) {
            reason = nil
            state = .suspended(suspension)
        }

        return commit(reason: reason, state: state, now: now, activities: activities)
    }

    private func desiredHold(
        now: Date,
        activities: [SessionID: SessionActivity]
    ) -> (HoldReason?, BelayState) {
        switch policy.mode {
        case .off:
            return (nil, .off)
        case .alwaysOn:
            lastActiveAt = now
            lastHoldReason = .alwaysOn
            return (.alwaysOn, .alwaysOn)
        case .auto:
            break
        }

        let working = ledger.sessions.values.filter { activities[$0.id] == .working }
        if !working.isEmpty {
            lastActiveAt = now
            let workspace = working.count == 1 ? working.first?.workspace : nil
            let reason = HoldReason.working(sessions: working.count, workspace: workspace)
            lastHoldReason = reason
            return (reason, .working)
        }

        let awaiting = ledger.sessions.values.filter {
            guard activities[$0.id] == .awaitingUser, let since = $0.awaitingSince else { return false }
            return now.timeIntervalSince(since) < policy.awaitingUserBudget
        }
        if let first = awaiting.first {
            // Deliberately does not refresh `lastActiveAt`: the awaiting budget is
            // the bound here (PRD R7), and letting it also feed the grace timer
            // would make the tail depend on how often the driver happens to tick.
            let reason = HoldReason.awaitingUser(workspace: awaiting.count == 1 ? first.workspace : nil)
            lastHoldReason = reason
            return (reason, .awaitingUser)
        }

        guard let lastActiveAt else { return (nil, .armed) }
        let grace = policy.effectiveGrace(lowPower: power.isLowPowerMode)
        guard now.timeIntervalSince(lastActiveAt) < grace else { return (nil, .armed) }
        return (lastHoldReason ?? .coolingDown, .coolingDown)
    }

    /// Safety gates that override any desire to hold. All are user-visible.
    private func suspension(now: Date) -> SuspensionReason? {
        if power.trips(policy.batteryFloor) {
            return .batteryLow(charge: power.charge ?? 0)
        }
        // Before the cap: when both bounds have passed, the one the user chose
        // by hand is the honest answer to "why did Belay let go".
        if policy.mode == .alwaysOn, let timer, now >= timer.deadline {
            return .timerEnded(timer.duration)
        }
        guard let cap = policy.maxContinuousAwake else { return nil }
        // Checked before `holdingSince`, which the release this gate caused has
        // already cleared. Reading it first would let the cap fire once and then
        // immediately forget it had.
        if capTripped { return .maxDurationReached(cap) }
        if let holdingSince, now.timeIntervalSince(holdingSince) >= cap {
            capTripped = true
            return .maxDurationReached(cap)
        }
        return nil
    }

    private func commit(
        reason: HoldReason?,
        state: BelayState,
        now: Date,
        activities: [SessionID: SessionActivity]
    ) -> AwakeDecision {
        let holding = reason != nil
        if holding, holdingSince == nil { holdingSince = now }
        if !holding { holdingSince = nil }

        let decision: AwakeDecision =
            if let reason {
                .hold(reason: reason.assertionDetail, until: now + policy.assertionTimeout)
            } else {
                .release
            }

        snapshot = CoordinatorSnapshot(
            state: state,
            sessions: ledger.ordered,
            activities: activities,
            holdReason: reason,
            holdingSince: holdingSince,
            timer: policy.mode == .alwaysOn ? timer : nil
        )

        if emitted.holding != holding || emitted.reason != reason {
            emitted = (holding, reason)
            Log.core.debug("decision \(holding ? "hold" : "release", privacy: .public)")
            for continuation in subscribers.values { continuation.yield(decision) }
        }
        return decision
    }

    /// Ends every decision stream. Called on app termination, after the final
    /// synchronous release.
    public func shutdown() {
        for continuation in subscribers.values { continuation.finish() }
        subscribers.removeAll()
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    deinit {
        for continuation in subscribers.values { continuation.finish() }
    }
}
