import Foundation

/// Decides when the kernel's `SleepDisabled` flag should be up, and why it
/// must come down. Pure for the same reason `NightDimming` is: the flag is
/// privileged and dangerous, so every rule about it lives where tests run.
///
/// The shape, from docs/ROADMAP: Belay's ordinary hold is an idle-sleep
/// assertion and lid close is not idle sleep. The only lever is the kernel
/// flag, which needs root and outlives the process that set it — so a
/// privileged helper holds it only while the app keeps saying "still here",
/// and this type is the app's side of that sentence: it decides what to say.
///
/// Two guards, both required, neither optional (docs/ROADMAP):
/// - A hard cap on how long the flag may stay set.
/// - A thermal release: `serious` clears the flag and lets the Mac sleep.
///   It applies **only** while the lid is closed. With the lid open,
///   `serious` happens during an ordinary compile, and releasing there
///   would kill the run Belay exists to protect.
public struct LidHold: Sendable, Equatable {
    public struct Sample: Sendable {
        /// The opt-in is on. Direct builds only; the sandboxed build never
        /// constructs any of this.
        public var enabled: Bool
        /// Belay is holding for real work. The flag rides the hold: up before
        /// the lid closes, down when the work is done.
        public var holding: Bool
        /// From `Clamshell`, which already ships in both channels.
        public var lidClosed: Bool
        /// `ProcessInfo.thermalState` at `serious` or worse.
        public var thermalSerious: Bool
        public var now: Date

        public init(
            enabled: Bool, holding: Bool, lidClosed: Bool, thermalSerious: Bool, now: Date
        ) {
            self.enabled = enabled
            self.holding = holding
            self.lidClosed = lidClosed
            self.thermalSerious = thermalSerious
            self.now = now
        }
    }

    public enum ReleaseReason: Sendable, Equatable {
        /// The hold ended or the setting was turned off: the ordinary way down.
        case done
        /// The Mac ran hot with the lid shut. Recorded in Statistics the way a
        /// battery release is (docs/ROADMAP).
        case thermal
        /// The hard cap. Past it Belay is guessing, not observing.
        case capReached
    }

    public enum Command: Sendable, Equatable {
        case engage
        case release(ReleaseReason)
    }

    /// How long the flag may stay up in one stretch, ever.
    public var cap: TimeInterval

    public private(set) var engagedSince: Date?
    /// Set when the cap or the thermal guard fired; cleared only once the hold
    /// ends. Without this the flag would go straight back up on the next tick,
    /// and the guard would have capped nothing — the same trap
    /// `ActivityCoordinator.capTripped` exists for.
    private var tripped = false

    public init(cap: TimeInterval = 4 * 60 * 60) {
        self.cap = cap
    }

    public var isEngaged: Bool { engagedSince != nil }

    public mutating func evaluate(_ sample: Sample) -> Command? {
        if let since = engagedSince {
            if !sample.enabled || !sample.holding {
                engagedSince = nil
                tripped = false
                return .release(.done)
            }
            if sample.thermalSerious && sample.lidClosed {
                engagedSince = nil
                tripped = true
                return .release(.thermal)
            }
            if sample.now.timeIntervalSince(since) >= cap {
                engagedSince = nil
                tripped = true
                return .release(.capReached)
            }
            return nil
        }

        // A guard that fired stays fired until the work itself ends; only a
        // fresh hold earns a fresh flag.
        if tripped {
            if !sample.holding || !sample.enabled { tripped = false }
            return nil
        }
        guard sample.enabled, sample.holding else { return nil }
        // Not a release rule while engaged with the lid open — see above —
        // but no reason to raise the flag on a machine already running hot
        // with the lid shut.
        guard !(sample.thermalSerious && sample.lidClosed) else { return nil }
        engagedSince = sample.now
        return .engage
    }
}
