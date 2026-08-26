import Foundation
import Testing

@testable import BelaySupport

/// The sink must not gain weight from being used.
///
/// The field crash behind this: a closure stored bare in the lock's generic
/// `State` was reabstracted on every read and the wrapped copy written back
/// by inout copy-out — every `note` left the sink one thunk deeper, and a
/// night of hook traffic (~6 500 lines) blew the cooperative pool's stack
/// guard. SIGBUS, no warning, Belay simply gone by morning.
struct EventLogTests {
    @Test("Ten thousand notes leave the sink at its original depth")
    func noteDoesNotDeepenTheSink() {
        let depth = Depth()
        EventLog.install { _ in depth.record() }
        defer { EventLog.install(nil) }

        EventLog.note("first")
        let baseline = depth.last
        for _ in 0..<10_000 { EventLog.note("again") }
        EventLog.note("last")

        // Identical, not merely close: the sink is a stored reference and
        // nothing about calling it may rebuild it.
        #expect(depth.last == baseline, "the sink grew \(depth.last - baseline) frames deeper")
    }

    private final class Depth: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var last: Int { lock.withLock { value } }
        func record() {
            let frames = Thread.callStackReturnAddresses.count
            lock.withLock { value = frames }
        }
    }
}
