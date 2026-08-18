import BelayPower
import BelaySettings
import Foundation

/// Wires the pure `NightDimming` rules to the screen: samples the clock, the
/// hold and the input on a slow tick, and drives `GammaFade` with whatever the
/// rules answer. Owns no policy of its own — every "when" lives in BelayPower
/// where the tests are.
@MainActor
final class NightDimmingController {
    /// The slow cadence decides when to dim; nobody notices five seconds on
    /// the way down. The fast one runs only while the screen is dimmed, so
    /// the way back starts within a quarter of a second of a real return —
    /// the restore is the one direction where latency reads as a broken Mac.
    private static let tickInterval: TimeInterval = 5
    private static let dimmedTickInterval: TimeInterval = 0.25

    private let settings: SettingsStore
    private let state: AppState
    private let fade = GammaFade()
    private var machine = NightDimming()
    private var ticker: Timer?
    /// Where the pointer stood when the screen went down; travel is measured
    /// from here, so jitter accumulates toward the threshold instead of
    /// resetting some timer.
    private var pointerAtDim: CGPoint?
    /// Fed by the power-source stream the app already watches. AC and battery
    /// carry different display-sleep delays.
    var isOnAC = true

    init(settings: SettingsStore, state: AppState) {
        self.settings = settings
        self.state = state
    }

    func start() {
        schedule(every: Self.tickInterval)
    }

    private func schedule(every interval: TimeInterval) {
        ticker?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Restores on the way out so quitting Belay at night is never a way to
    /// keep a dim screen. Redundant with CoreGraphics' own exit restore, and
    /// deliberately so: belt here, kernel braces there.
    func stop() {
        ticker?.invalidate()
        ticker = nil
        if machine.isDimmed { fade.restore() }
    }

    private func tick() {
        // The cheap early-out for the common case: feature off, screen up.
        guard settings.nightDimming || machine.isDimmed else { return }

        let travel = pointerAtDim.map { at -> Double in
            let now = UserInputSource.pointerLocation()
            return Double(hypot(now.x - at.x, now.y - at.y))
        }
        let sample = NightDimming.Sample(
            minuteOfDay: Self.minuteOfDay(),
            holdingDisplay: state.isHolding && settings.keepDisplayAwake,
            secondsSinceInput: UserInputSource.secondsSinceAnyInput(),
            // `nil` is "the system would never sleep this display": the lit
            // screen is the user's arrangement, so the gate never opens.
            displaySleepDelay: DisplaySleepDelay.current(onAC: isOnAC) ?? .infinity,
            keyOrClick: UserInputSource.keyOrClick(
                within: machine.isDimmed ? Self.dimmedTickInterval : Self.tickInterval),
            pointerTravel: travel ?? 0)

        let window = NightDimming.Window(
            start: settings.nightDimmingStart, end: settings.nightDimmingEnd)
        switch machine.evaluate(sample, enabled: settings.nightDimming, window: window) {
        case .dim:
            pointerAtDim = UserInputSource.pointerLocation()
            Diagnostics.note(
                "dim on idle=\(Int(sample.secondsSinceInput)) "
                    + "delay=\(Int(sample.displaySleepDelay)) "
                    + "window=\(window.start)-\(window.end) level=\(settings.nightDimmingLevel)")
            fade.dim(to: settings.nightDimmingLevel)
            schedule(every: Self.dimmedTickInterval)
        case .restore:
            pointerAtDim = nil
            Diagnostics.note("dim off cause=\(Self.restoreCause(sample, window: window))")
            fade.restore()
            schedule(every: Self.tickInterval)
        case nil:
            break
        }
    }

    /// Which leave-rule fired, in `NightDimming`'s own precedence, so the log
    /// line and the decision cannot tell different stories.
    private static func restoreCause(
        _ sample: NightDimming.Sample, window: NightDimming.Window
    ) -> String {
        if !window.contains(minuteOfDay: sample.minuteOfDay) { return "window" }
        if !sample.holdingDisplay { return "hold-ended" }
        if sample.keyOrClick { return "key" }
        if sample.pointerTravel > NightDimming.pointerTravelThreshold {
            return "travel=\(Int(sample.pointerTravel))"
        }
        return "disabled"
    }

    private static func minuteOfDay(_ now: Date = Date()) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
