import Foundation
import Testing

@testable import VigilPower

@Suite("PowerAssertionController")
struct PowerAssertionControllerTests {
    /// Long enough that the refresh loop never ticks during a test that is not
    /// about the refresh loop.
    private let inert: TimeInterval = 3_600

    @Test func holdThenReleaseLeavesNothingBehind() async {
        let backend = MockPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)

        await controller.hold(reason: "Claude Code is working", timeout: inert)
        #expect(await controller.isHeld)
        #expect(await controller.isDisplayHeld == false)
        #expect(await backend.liveCount(of: .system) == 1)

        await controller.release()
        #expect(await controller.isHeld == false)
        #expect(await controller.heldReason == nil)
        #expect(await backend.liveIDs.isEmpty)
        #expect(await backend.createCount == backend.releaseCount)
    }

    @Test func holdTwiceRearmsInsteadOfCreatingASecondAssertion() async {
        let backend = MockPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)

        await controller.hold(reason: "first", timeout: inert)
        await controller.hold(reason: "second", timeout: inert)

        #expect(await backend.createCount == 1)
        #expect(await backend.rearmCount == 1)
        #expect(await backend.releaseCount == 0)
        #expect(await controller.heldReason == "second")
        let calls = await backend.calls
        #expect(calls.count == 2)
        #expect(calls.first == .create(kind: .system, reason: "first", timeout: inert))
        #expect(calls.last == .rearm(id: PowerAssertionID(rawValue: 1), reason: "second", timeout: inert))

        await controller.release()
    }

    @Test func releaseWithNothingHeldIsASilentNoOp() async {
        let backend = MockPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)

        await controller.release()
        await controller.release()

        #expect(await backend.calls.isEmpty)
        #expect(await controller.lastError == nil)
        #expect(await controller.isHeld == false)
    }

    @Test func displayAssertionCanBeAddedAndDroppedWithoutTouchingTheSystemOne() async throws {
        let backend = MockPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)

        await controller.hold(reason: "work", timeout: inert)
        let systemID = try #require(await backend.liveIDs.first { $0.value == .system }?.key)

        await controller.hold(reason: "work", includeDisplay: true, timeout: inert)
        #expect(await backend.liveCount(of: .system) == 1)
        #expect(await backend.liveCount(of: .display) == 1)
        #expect(await backend.createCount == 2)
        #expect(await backend.releaseCount == 0)

        await controller.hold(reason: "work", includeDisplay: false, timeout: inert)
        #expect(await backend.liveCount(of: .display) == 0)
        #expect(await backend.releaseCount == 1)
        #expect(await controller.isHeld)
        // Same handle throughout: the system assertion was never dropped.
        #expect(await backend.liveIDs[systemID] == .system)

        await controller.release()
        #expect(await backend.liveIDs.isEmpty)
    }

    @Test func refreshLoopRearmsBeforeTimeoutAndStopsOnRelease() async throws {
        let backend = MockPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend, refreshFraction: 0.5)

        await controller.hold(reason: "work", timeout: 0.06)
        try await Task.sleep(for: .milliseconds(160))
        #expect(await backend.rearmCount >= 2)

        await controller.release()
        let rearmsAtRelease = await backend.rearmCount
        try await Task.sleep(for: .milliseconds(160))

        #expect(await backend.rearmCount == rearmsAtRelease)
        #expect(await backend.liveIDs.isEmpty)
    }

    @Test func failedCreateIsSurfacedAndRecoversOnTheNextTick() async {
        let backend = MockPowerAssertionBackend()
        await backend.fail([.create])
        let controller = PowerAssertionController(backend: backend)

        await controller.hold(reason: "work", timeout: inert)
        #expect(await controller.isHeld == false)
        #expect(
            await controller.lastError
                == .assertionFailed(code: MockPowerAssertionBackend.defaultFailureCode)
        )

        await backend.stopFailing()
        await controller.refreshNow()
        #expect(await controller.isHeld)
        #expect(await controller.lastError == nil)

        await controller.release()
        #expect(await backend.liveIDs.isEmpty)
    }

    @Test func failedReleaseStillForgetsTheHandle() async {
        let backend = MockPowerAssertionBackend()
        let controller = PowerAssertionController(backend: backend)

        await controller.hold(reason: "work", timeout: inert)
        await backend.fail([.release])
        await controller.release()

        // The kernel-side assertion is now orphaned, but its own timeout reaps
        // it; what matters is that we never retry a stale ID.
        #expect(await controller.isHeld == false)
        #expect(await controller.lastError != nil)
        #expect(await backend.releaseCount == 1)

        await controller.release()
        #expect(await backend.releaseCount == 1)
    }
}
