import Foundation

/// The user-facing bounds on a hold: the Always-on timer and the two ways a
/// pause is ended by a human. Beside the coordinator rather than inside it
/// only for the file-length rule.
extension ActivityCoordinator {
    /// Sets or clears the Always-on timer: nil means "until turned off".
    public func setAlwaysOnTimer(_ duration: TimeInterval?) {
        timer = duration.map { AlwaysOnTimer(duration: $0, deadline: clock.now + $0) }
        evaluate()
    }

    /// The pause's one-click exit. Re-arms whichever bound fired: a tripped
    /// cap is forgiven, and a finished timer starts a fresh round of the same
    /// length. Harmless when nothing is paused.
    public func holdAgain() {
        capTripped = false
        if let timer {
            self.timer = AlwaysOnTimer(duration: timer.duration, deadline: clock.now + timer.duration)
        }
        evaluate()
    }

    /// The cap's other exit: the user came back to the machine (screen wake,
    /// unlock). A returned human is the same sanction a wake from sleep gives
    /// via `resync`, so the cap starts a fresh cycle. Deliberately does not
    /// touch the timer — that was an explicit "this long, no longer", and
    /// walking back to the Mac is not a request for another round.
    public func renewCapOnReturn() {
        guard capTripped else { return }
        capTripped = false
        evaluate()
    }
}
