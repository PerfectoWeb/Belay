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
        at offset: TimeInterval = 0
    ) -> LidHold.Sample {
        LidHold.Sample(
            enabled: enabled,
            holding: holding,
            lidClosed: lidClosed,
            thermalSerious: hot,
            now: start.addingTimeInterval(offset))
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
}
