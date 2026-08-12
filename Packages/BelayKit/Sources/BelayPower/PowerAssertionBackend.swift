import Foundation

/// The assertion types Belay is allowed to take.
///
/// docs/04 rules out `PreventSystemSleep` (kernel/driver territory) and the
/// legacy `NoIdleSleep` aliases, so these two are the whole vocabulary.
public enum PowerAssertionKind: String, Sendable, CaseIterable {
    /// Keeps the machine running. The display may still sleep, which is the point.
    case system
    /// Opt-in second assertion behind "Also keep the display awake".
    case display
}

/// An opaque handle to one live assertion.
public struct PowerAssertionID: Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// The IOKit surface `PowerAssertionController` needs, narrowed to three calls.
///
/// The narrowing exists so the controller can be driven by
/// `MockPowerAssertionBackend` in tests; nothing else in Belay talks to IOKit.
public protocol PowerAssertionBackend: Sendable {
    /// Creates an assertion that self-releases after `timeout` seconds.
    func create(
        kind: PowerAssertionKind,
        reason: String,
        timeout: TimeInterval
    ) async throws(PowerError) -> PowerAssertionID

    /// Restarts the timeout countdown and refreshes the user-visible reason.
    func rearm(_ id: PowerAssertionID, reason: String, timeout: TimeInterval) async throws(PowerError)

    func release(_ id: PowerAssertionID) async throws(PowerError)
}
