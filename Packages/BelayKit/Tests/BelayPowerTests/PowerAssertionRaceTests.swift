import Foundation
import Testing

@testable import BelayPower

/// `hold` and `release` reach the controller from different tasks — the sleep
/// observer, the SIGTERM handler, `shutdown()` and the decision pump all call it
/// — so the two can meet inside a single reconcile. These tests arrange that
/// meeting deliberately instead of hoping the scheduler produces it.
@Suite("PowerAssertionController under interleaving")
struct PowerAssertionRaceTests {
    /// Long enough that the refresh loop never ticks during these tests.
    private let inert: TimeInterval = 3_600

    /// The orphan: `release` runs while `hold` is parked inside IOKit's create,
    /// sees nothing recorded, no-ops and stops refreshing; the resumed `hold`
    /// then records a live assertion nobody owns. It expires silently two
    /// minutes later while the panel still says the Mac is awake, and nothing
    /// re-arms it. Invariants 1 and 4.
    @Test("A release landing inside create never orphans an assertion")
    func releaseInsideCreateNeverOrphans() async {
        let backend = GatedPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)

        let holding = Task { await controller.hold(reason: "work", timeout: inert) }
        await backend.waitForParkedCall()

        let releasing = Task { await controller.release() }
        // The release has passed its guard and dropped the intent, which is the
        // only moment that matters: from here the resumed create is unwanted.
        await settle("the release to take effect") { await controller.heldReason == nil }

        await backend.open()
        await holding.value
        await releasing.value

        #expect(await controller.isHeld == false)
        #expect(await backend.liveCount(of: .system) == 0)
        #expect(await backend.createCount == backend.releaseCount)
    }

    /// The mirror image: `reconcile` forgets the handle before calling release,
    /// so a `hold` arriving while that call is parked finds an empty table and
    /// takes a second assertion alongside the still-live first one.
    @Test("A hold landing inside release never doubles up")
    func holdInsideReleaseNeverDoublesUp() async {
        let backend = GatedPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)

        await backend.open()
        await controller.hold(reason: "first", timeout: inert)
        await backend.shut()

        let releasing = Task { await controller.release() }
        await backend.waitForParkedCall()

        let holding = Task { await controller.hold(reason: "second", timeout: inert) }
        await settle("the hold to take effect") { await controller.heldReason == "second" }

        await backend.open()
        await releasing.value
        await holding.value

        #expect(await backend.peakCount(of: .system) == 1)
        #expect(await backend.liveCount(of: .system) == 1)
        #expect(await controller.isHeld)

        await controller.release()
        #expect(await backend.live.isEmpty)
        #expect(await backend.createCount == backend.releaseCount)
    }
}

/// Spins the cooperative pool until `condition` holds, so the interleaving under
/// test is guaranteed rather than hoped for.
private func settle(_ what: String, until condition: () async -> Bool) async {
    for _ in 0..<20_000 {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("timed out waiting for \(what)")
}
