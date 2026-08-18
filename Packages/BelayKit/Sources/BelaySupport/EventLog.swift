import os

/// The kit's half of the diagnostics file: modules below the app cannot see
/// `Diagnostics`, so they hand their lines to whatever sink the app installed.
/// No sink — the switch is off, or there is no app, as in tests — and a note
/// costs one lock read and builds no string.
///
/// Lines follow the same shape the app writes: `subject verb key=value …`,
/// one line, greppable. They exist so that a problem report plus this file
/// can say what happened without a debugger; see `Diagnostics`.
public enum EventLog {
    private static let sink = OSAllocatedUnfairLock<(@Sendable (String) -> Void)?>(
        initialState: nil)

    /// The app installs its writer here when collection turns on, and clears
    /// it when collection turns off. Kit code never checks a setting.
    public static func install(_ handler: (@Sendable (String) -> Void)?) {
        sink.withLock { $0 = handler }
    }

    public static func note(_ line: @autoclosure () -> String) {
        guard let handler = sink.withLock({ $0 }) else { return }
        handler(line())
    }
}
