import Foundation
import Testing

@testable import BelayPower

@Suite("LidHold")
struct LidHoldTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func sample(
        enabled: Bool = true,
        holding: Bool = true,
        lidClosed: Bool = false,
        hot: Bool = false,
        at offset: TimeInterval = 0,
        monotonic: TimeInterval? = nil
    ) -> LidHold.Sample {
        LidHold.Sample(
            enabled: enabled,
            holding: holding,
            lidClosed: lidClosed,
            thermalSerious: hot,
            now: start.addingTimeInterval(offset),
            monotonic: monotonic ?? offset)
    }

    @Test("The flag rides the hold: up with work, down when it ends")
    func flagFollowsTheHold() {
        var lid = LidHold()
        #expect(lid.evaluate(sample(holding: false)) == nil)
        #expect(lid.evaluate(sample()) == .engage)
        #expect(lid.evaluate(sample(at: 60)) == nil)
        #expect(lid.evaluate(sample(holding: false, at: 120)) == .release(.done))
        #expect(!lid.isEngaged)
    }

    @Test("Turning the setting off releases even mid-hold")
    func disablingReleases() {
        var lid = LidHold()
        #expect(lid.evaluate(sample()) == .engage)
        #expect(lid.evaluate(sample(enabled: false, at: 30)) == .release(.done))
    }

    @Test("Serious heat with the lid shut releases; recorded as thermal")
    func thermalReleasesOnlyClosed() {
        var lid = LidHold()
        #expect(lid.evaluate(sample()) == .engage)
        // An ordinary compile runs the machine hot with the lid open. That is
        // not a reason to let the Mac sleep — it would kill the run.
        #expect(lid.evaluate(sample(hot: true, at: 60)) == nil)
        #expect(lid.evaluate(sample(lidClosed: true, hot: true, at: 120)) == .release(.thermal))
    }

    @Test("A thermal release stays released for the rest of the hold")
    func thermalDoesNotFlap() {
        var lid = LidHold()
        #expect(lid.evaluate(sample()) == .engage)
        #expect(lid.evaluate(sample(lidClosed: true, hot: true, at: 60)) == .release(.thermal))
        // Cooled off, still the same run: the flag stays down.
        #expect(lid.evaluate(sample(lidClosed: true, at: 700)) == nil)
        // The run ends, a new one starts: a fresh hold earns a fresh flag.
        #expect(lid.evaluate(sample(holding: false, at: 800)) == nil)
        #expect(lid.evaluate(sample(at: 900)) == .engage)
    }

    @Test("The hard cap comes down once and does not re-arm")
    func capReleasesOnce() {
        var lid = LidHold(cap: 3600)
        #expect(lid.evaluate(sample()) == .engage)
        #expect(lid.evaluate(sample(at: 3599)) == nil)
        #expect(lid.evaluate(sample(at: 3600)) == .release(.capReached))
        #expect(lid.evaluate(sample(at: 3700)) == nil)
        #expect(lid.evaluate(sample(holding: false, at: 3800)) == nil)
        #expect(lid.evaluate(sample(at: 3900)) == .engage)
    }

    @Test("Already hot and shut: the flag never goes up in the first place")
    func hotClosedNeverEngages() {
        var lid = LidHold()
        #expect(lid.evaluate(sample(lidClosed: true, hot: true)) == nil)
        #expect(lid.evaluate(sample(lidClosed: true, at: 60)) == .engage)
    }

    @Test("The cap counts on the monotonic clock, not the calendar")
    func capSurvivesAClockStep() {
        var lid = LidHold(cap: 3_600)
        #expect(lid.evaluate(sample()) == .engage)
        // Somebody drags the date a day backwards mid-hold. The wall clock now
        // reads before the engage; the machine has still been holding for over
        // an hour, and the flag must come down regardless.
        let stepped = sample(at: -86_400, monotonic: 3_601)
        #expect(lid.evaluate(stepped) == .release(.capReached))
    }
}
