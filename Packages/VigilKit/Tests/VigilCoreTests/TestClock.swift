// `@unchecked Sendable` justification: TestClock is mutated from test code and
// read from inside the coordinator actor, so it must cross isolation domains.
// All mutable state is behind `lock`; there is no other stored state. Using an
// actor is not possible because `Clock.now` is a synchronous requirement.

import Foundation

@testable import VigilCore

final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        current += interval
        lock.unlock()
    }

    /// Tests drive time explicitly; a driver sleeping on this clock would hang,
    /// which is the correct outcome for a test that forgot to advance it.
    func sleep(until deadline: Date) async throws {
        try Task.checkCancellation()
    }
}

/// Reproducible PRNG. `SystemRandomNumberGenerator` would make a failing
/// property test impossible to re-run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

extension ActivitySignal {
    static func make(
        _ activity: SessionActivity,
        session: String = "s1",
        at: Date,
        confidence: Confidence = .inferred,
        workspace: String? = "acme-api"
    ) -> ActivitySignal {
        ActivitySignal(
            provider: .claudeCode,
            session: SessionID(session),
            activity: activity,
            workspace: workspace,
            timestamp: at,
            confidence: confidence
        )
    }
}
