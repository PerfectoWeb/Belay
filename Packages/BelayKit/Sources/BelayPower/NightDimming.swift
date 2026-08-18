import Foundation

/// Decides when the screen dims at night and when it comes back, and nothing
/// else. Pure on purpose: the gamma calls, the clock and the input sampling all
/// live in the app layer, so every rule in here is testable in milliseconds.
///
/// The scenario, from docs/ROADMAP: the Mac runs overnight, its own display
/// sleep arrives, and Belay refuses it because an agent is working. From that
/// moment the screen lights an empty room until morning. Dimming is what the
/// display sleep would have done, only reversibly.
public struct NightDimming: Sendable, Equatable {
    /// A clock-time span, in minutes from midnight, that may cross it:
    /// 22:00 to 07:00 is `start 1320, end 420`. An equal start and end is an
    /// empty window, never a full day — a switch that is on around the whole
    /// clock is the `enabled` flag's job, not a degenerate window's.
    public struct Window: Sendable, Equatable {
        public var start: Int
        public var end: Int

        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }

        public func contains(minuteOfDay minute: Int) -> Bool {
            guard start != end else { return false }
            if start < end { return minute >= start && minute < end }
            return minute >= start || minute < end
        }
    }

    /// Everything the decision reads, measured by the caller each tick.
    public struct Sample: Sendable {
        public var minuteOfDay: Int
        /// Belay is holding, and the hold includes the display. When it does
        /// not, the display sleeps on its own and there is nothing to dim; when
        /// nothing is held at all, the screen being lit is not Belay's doing
        /// and therefore not Belay's to darken.
        public var holdingDisplay: Bool
        /// Seconds since any user input, from `CGEventSource`.
        public var secondsSinceInput: TimeInterval
        /// The system's own display-sleep delay: the moment that would have
        /// darkened the screen if Belay had not held it awake.
        public var displaySleepDelay: TimeInterval
        /// A key went down or a button was clicked since the last sample.
        /// Restores immediately: nobody types by accident.
        public var keyOrClick: Bool
        /// How far the pointer has moved, in points, since the screen dimmed.
        /// Zero while not dimmed. Distance, not "any event": a sleeping
        /// trackpad and a heavy lorry outside both produce single-pixel
        /// jitter, and neither means somebody is there.
        public var pointerTravel: Double

        public init(
            minuteOfDay: Int,
            holdingDisplay: Bool,
            secondsSinceInput: TimeInterval,
            displaySleepDelay: TimeInterval,
            keyOrClick: Bool,
            pointerTravel: Double
        ) {
            self.minuteOfDay = minuteOfDay
            self.holdingDisplay = holdingDisplay
            self.secondsSinceInput = secondsSinceInput
            self.displaySleepDelay = displaySleepDelay
            self.keyOrClick = keyOrClick
            self.pointerTravel = pointerTravel
        }
    }

    public enum Command: Sendable, Equatable {
        /// Ramp down over about a second — see `docs/ROADMAP`.
        case dim
        /// Instantly. A person who moved the mouse is waiting.
        case restore
    }

    /// Pointer movement below this is jitter, not presence.
    public static let pointerTravelThreshold: Double = 20

    public private(set) var isDimmed = false

    public init() {}

    /// One tick. Returns what the actuator should do, or nothing.
    ///
    /// Entering needs every gate at once; leaving needs any one reason. The
    /// input-idle gate applies only to entering, and deliberately so: the
    /// system resets its idle clock on the same jitter the travel threshold
    /// exists to ignore, so a dimmed screen re-arms on real input, not on a
    /// timer that a passing lorry can reset.
    public mutating func evaluate(
        _ sample: Sample, enabled: Bool, window: Window
    ) -> Command? {
        if isDimmed {
            let leave =
                !enabled
                || !window.contains(minuteOfDay: sample.minuteOfDay)
                || !sample.holdingDisplay
                || sample.keyOrClick
                || sample.pointerTravel > Self.pointerTravelThreshold
            guard leave else { return nil }
            isDimmed = false
            return .restore
        }

        let enter =
            enabled
            && window.contains(minuteOfDay: sample.minuteOfDay)
            && sample.holdingDisplay
            && sample.secondsSinceInput >= sample.displaySleepDelay
        guard enter else { return nil }
        isDimmed = true
        return .dim
    }
}
