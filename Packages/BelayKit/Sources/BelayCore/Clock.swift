import Foundation

/// Time, injected.
///
/// The coordinator never reads the wall clock directly, which is what lets the
/// test suite drive hours of simulated behaviour in milliseconds.
public protocol Clock: Sendable {
    var now: Date { get }
    func sleep(until deadline: Date) async throws
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(until deadline: Date) async throws {
        let interval = deadline.timeIntervalSinceNow
        guard interval > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
}
