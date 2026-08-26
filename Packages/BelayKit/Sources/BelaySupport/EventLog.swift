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
    /// The handler boxed in a class on purpose, and the box is the fix for a
    /// field crash. A bare closure stored in the lock's generic `State` gets
    /// reabstracted on every `withLock` read, and inout copy-out writes the
    /// wrapped copy back — so each `note` left the stored closure one thunk
    /// deeper, ~13 000 frames after a night of hooks, and the next write blew
    /// the cooperative pool's stack guard (SIGBUS, reported 2026-08-26). A
    /// class reference passes through unwrapped; the closure inside never
    /// crosses the generic boundary.
    private final class Sink: Sendable {
        let handler: @Sendable (String) -> Void
        init(_ handler: @escaping @Sendable (String) -> Void) { self.handler = handler }
    }

    private static let sink = OSAllocatedUnfairLock<Sink?>(initialState: nil)

    /// The app installs its writer here when collection turns on, and clears
    /// it when collection turns off. Kit code never checks a setting.
    public static func install(_ handler: (@Sendable (String) -> Void)?) {
        let boxed = handler.map(Sink.init)
        sink.withLock { $0 = boxed }
    }

    public static func note(_ line: @autoclosure () -> String) {
        guard let box = sink.withLock({ $0 }) else { return }
        box.handler(line())
    }
}
