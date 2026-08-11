import Foundation
import Testing

@testable import VigilPower

/// SplitMix64. Small, well distributed, and above all reproducible: a seed that
/// fails in CI has to fail identically on the first local run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

@Suite("Assertion balance")
struct AssertionBalanceTests {
    private enum Step: CaseIterable {
        case hold
        case holdWithDisplay
        case release
        case refresh
    }

    /// Invariant 1 from docs/00-INVARIANTS.md, hammered: whatever order the coordinator
    /// calls us in, there is never more than one live assertion per type and
    /// never a leftover one once the sequence ends.
    @Test func randomisedSequencesNeverLeakOrDoubleUp() async {
        var generator = SeededGenerator(seed: 0xC0FF_EE00_1234_5678)
        let choices = Step.allCases

        for trial in 0..<5_000 {
            let backend = MockPowerAssertionBackend()
            let controller = PowerAssertionController(backend: backend)

            for index in 0..<16 {
                let step = choices[Int.random(in: choices.indices, using: &generator)]
                await apply(step, to: controller, reason: "trial \(trial)")

                let system = await backend.liveCount(of: .system)
                let display = await backend.liveCount(of: .display)
                #expect(system <= 1, "trial \(trial) step \(index)")
                #expect(display <= 1, "trial \(trial) step \(index)")
            }

            await controller.release()

            let live = await backend.liveIDs
            let creates = await backend.createCount
            let releases = await backend.releaseCount
            #expect(live.isEmpty, "trial \(trial)")
            #expect(creates == releases, "trial \(trial)")
            #expect(await controller.lastError == nil, "trial \(trial)")
        }
    }

    private func apply(_ step: Step, to controller: PowerAssertionController, reason: String) async {
        // A timeout far past the end of the test keeps the refresh loop asleep,
        // so this measures ordering rather than timing.
        let inert: TimeInterval = 3_600
        switch step {
        case .hold:
            await controller.hold(reason: reason, timeout: inert)
        case .holdWithDisplay:
            await controller.hold(reason: reason, includeDisplay: true, timeout: inert)
        case .release:
            await controller.release()
        case .refresh:
            await controller.refreshNow()
        }
    }
}
