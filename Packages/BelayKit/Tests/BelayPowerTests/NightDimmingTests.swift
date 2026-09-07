import Foundation
import Testing

@testable import BelayPower

@Suite("NightDimming")
struct NightDimmingTests {
    /// 22:00 to 07:00, the default.
    private let overnight = NightDimming.Window(start: 22 * 60, end: 7 * 60)

    private func sample(
        minute: Int = 23 * 60,
        holding: Bool = true,
        idle: TimeInterval = 601,
        delay: TimeInterval = 600,
        keyOrClick: Bool = false,
        travel: Double = 0,
        heldElsewhere: Bool = false,
        sinceHeld: TimeInterval = .infinity
    ) -> NightDimming.Sample {
        NightDimming.Sample(
            minuteOfDay: minute,
            holdingDisplay: holding,
            secondsSinceInput: idle,
            displaySleepDelay: delay,
            keyOrClick: keyOrClick,
            pointerTravel: travel,
            displayHeldElsewhere: heldElsewhere,
            secondsSinceDisplayHeldElsewhere: sinceHeld)
    }

    @Test("All four gates open dims; each one alone closed does not")
    func entryNeedsEveryGate() {
        var dimming = NightDimming()
        #expect(dimming.evaluate(sample(), enabled: false, window: overnight) == nil)
        #expect(dimming.evaluate(sample(minute: 12 * 60), enabled: true, window: overnight) == nil)
        #expect(dimming.evaluate(sample(holding: false), enabled: true, window: overnight) == nil)
        #expect(dimming.evaluate(sample(idle: 60), enabled: true, window: overnight) == nil)
        #expect(dimming.evaluate(sample(), enabled: true, window: overnight) == .dim)
        #expect(dimming.isDimmed)
    }

    /// The film case: idle, holding, deep in the window — but a video player is
    /// keeping the screen up, so the screen would not have slept and Belay does
    /// not dim it. And a video starting mid-dim brings the screen back.
    /// The flicker from the field: a player that renews its assertion every
    /// fifteen seconds. Each drop is not a calm; the screen dims only once
    /// the hold has been gone for the whole settle window.
    @Test("A flickering hold elsewhere never dims until it has settled")
    func flickeringHoldDoesNotFlapTheScreen() {
        var dimming = NightDimming()
        for _ in 0..<6 {
            #expect(
                dimming.evaluate(sample(heldElsewhere: true, sinceHeld: 0), enabled: true, window: overnight)
                    == nil)
            #expect(dimming.evaluate(sample(sinceHeld: 5), enabled: true, window: overnight) == nil)
            #expect(dimming.evaluate(sample(sinceHeld: 10), enabled: true, window: overnight) == nil)
        }
        #expect(!dimming.isDimmed)
        #expect(
            dimming.evaluate(sample(sinceHeld: NightDimming.watchingSettle), enabled: true, window: overnight)
                == .dim)
    }

    @Test("Another app holding the display blocks dimming and restores it")
    func watchingBlocksDimming() {
        var dimming = NightDimming()
        #expect(dimming.evaluate(sample(heldElsewhere: true), enabled: true, window: overnight) == nil)
        #expect(!dimming.isDimmed)

        // Nothing playing now: the same idle screen dims.
        #expect(dimming.evaluate(sample(), enabled: true, window: overnight) == .dim)
        // A video starts while dimmed: restore for the watcher.
        #expect(dimming.evaluate(sample(heldElsewhere: true), enabled: true, window: overnight) == .restore)
        #expect(!dimming.isDimmed)
    }

    @Test("A window crossing midnight covers both of its evenings")
    func windowWrapsMidnight() {
        #expect(overnight.contains(minuteOfDay: 23 * 60))
        #expect(overnight.contains(minuteOfDay: 3 * 60))
        #expect(!overnight.contains(minuteOfDay: 12 * 60))
        #expect(overnight.contains(minuteOfDay: 22 * 60))
        #expect(!overnight.contains(minuteOfDay: 7 * 60))

        let daytime = NightDimming.Window(start: 9 * 60, end: 17 * 60)
        #expect(daytime.contains(minuteOfDay: 12 * 60))
        #expect(!daytime.contains(minuteOfDay: 20 * 60))

        // Equal ends are an empty window, not a full day.
        let empty = NightDimming.Window(start: 300, end: 300)
        #expect(!empty.contains(minuteOfDay: 300))
        #expect(!empty.contains(minuteOfDay: 900))
    }

    @Test("A key or a click restores instantly")
    func keyRestores() {
        var dimming = NightDimming()
        #expect(dimming.evaluate(sample(), enabled: true, window: overnight) == .dim)
        #expect(
            dimming.evaluate(sample(keyOrClick: true), enabled: true, window: overnight)
                == .restore)
        #expect(!dimming.isDimmed)
    }

    @Test("Pointer jitter stays dimmed; real travel restores")
    func travelThreshold() {
        var dimming = NightDimming()
        #expect(dimming.evaluate(sample(), enabled: true, window: overnight) == .dim)
        // Single-pixel jitter — a sleeping trackpad, a heavy lorry outside.
        #expect(dimming.evaluate(sample(travel: 3), enabled: true, window: overnight) == nil)
        #expect(dimming.evaluate(sample(travel: 19), enabled: true, window: overnight) == nil)
        #expect(dimming.evaluate(sample(travel: 21), enabled: true, window: overnight) == .restore)
    }

    @Test("Jitter that resets the idle clock does not re-arm a dimmed screen")
    func jitterDoesNotUndim() {
        var dimming = NightDimming()
        #expect(dimming.evaluate(sample(), enabled: true, window: overnight) == .dim)
        // The system reset its idle count on the jitter; the screen stays down.
        #expect(dimming.evaluate(sample(idle: 1, travel: 2), enabled: true, window: overnight) == nil)
        #expect(dimming.isDimmed)
    }

    @Test("Losing the hold, the window or the switch restores")
    func conditionsLapseRestores() {
        for lapsed in [
            sample(holding: false),
            sample(minute: 8 * 60)
        ] {
            var dimming = NightDimming()
            #expect(dimming.evaluate(sample(), enabled: true, window: overnight) == .dim)
            #expect(dimming.evaluate(lapsed, enabled: true, window: overnight) == .restore)
        }
        var dimming = NightDimming()
        #expect(dimming.evaluate(sample(), enabled: true, window: overnight) == .dim)
        #expect(dimming.evaluate(sample(), enabled: false, window: overnight) == .restore)
    }

    @Test("After a restore the idle gate has to fill again before it re-dims")
    func rearmWaitsForIdle() {
        var dimming = NightDimming()
        #expect(dimming.evaluate(sample(), enabled: true, window: overnight) == .dim)
        #expect(
            dimming.evaluate(sample(keyOrClick: true), enabled: true, window: overnight)
                == .restore)
        // The person is at the keyboard now: idle is small, no dim.
        #expect(dimming.evaluate(sample(idle: 30), enabled: true, window: overnight) == nil)
        // They left again; the full delay passes; the screen goes back down.
        #expect(dimming.evaluate(sample(idle: 700), enabled: true, window: overnight) == .dim)
    }
}
