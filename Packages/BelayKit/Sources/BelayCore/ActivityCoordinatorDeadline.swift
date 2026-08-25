import Foundation

/// The two faces of "what does the wall clock mean right now": the deadline the
/// driver sleeps to, and the resync that runs when every held timestamp has
/// stopped meaning anything. Beside `ActivityCoordinator` for the file-length
/// rule.
extension ActivityCoordinator {
    /// Forgets everything — `holdingSince` included, or the awake-limit counts
    /// the sleep and trips on wake — and re-derives after a wake (docs/04).
    public func resync() {
        forgetTimestamps()
        evaluate()
    }

    /// The clearing half of `resync`, without the re-derive, so `evaluate` can
    /// use it on a clock step without recursing back into itself.
    func forgetTimestamps() {
        ledger.removeAll()
        lastActiveAt = nil
        capTripped = false
        holdingSince = nil
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
}
