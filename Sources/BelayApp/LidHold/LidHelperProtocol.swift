import Foundation

/// The whole conversation between the app and its privileged helper. Compiled
/// into both — the one file they share — so the two halves cannot drift.
///
/// The shape is a heartbeat, not a switch (docs/ROADMAP): the helper keeps the
/// kernel's `SleepDisabled` flag up only until `deadline`, and clears it by
/// itself when no refresh arrives. The app asks again every few seconds while
/// the hold lasts. A dead app therefore costs at most one leash length, and
/// the helper enforces the leash: a deadline further out than its maximum is
/// shortened, never trusted.
@objc(BelayLidHelperProtocol)
public protocol LidHelperProtocol {
    /// Raise the flag, or keep it up, until `deadline` at the latest.
    /// Replies with whether the flag is actually up.
    ///
    /// Every reply here is `@Sendable` because XPC delivers it on its own
    /// queue: a reply that silently inherited the caller's main-actor
    /// isolation is a runtime trap the first time it fires off-main, which is
    /// exactly how toggling the hold off crashed 1.3.3-dev.
    func keepSleepDisabled(until deadline: Date, reply: @Sendable @escaping (Bool) -> Void)
    /// Lower the flag now. Replies once it is down.
    func standDown(reply: @Sendable @escaping (Bool) -> Void)
    /// The helper's version, for the app to notice a stale installation.
    func version(reply: @Sendable @escaping (String) -> Void)
}

/// Shared constants, beside the protocol for the same no-drift reason.
public enum LidDaemon {
    public static let machService = "com.perfectoweb.belay.lidhelper"
    public static let plistName = "com.perfectoweb.belay.lidhelper.plist"
    /// The longest leash the helper will honour. The app asks for far less;
    /// this is the ceiling that makes a runaway caller boring.
    public static let maximumLeash: TimeInterval = 120
    public static let version = "2"
}
