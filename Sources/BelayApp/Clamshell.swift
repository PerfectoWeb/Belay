import Foundation
import IOKit

/// What the lid is doing, and whether a hold can survive it.
///
/// Belay holds an idle-sleep assertion, and that kind of assertion has no
/// bearing on the sleep a Mac performs when its lid shuts. So there is a state
/// the app could not previously describe: holding correctly, saying "an agent
/// is working", while the machine is about to suspend anyway.
///
/// Reading this costs 0.015 ms, measured, so it can be answered on the tick the
/// app already has rather than watched.
enum Clamshell {
    /// `nil` on a Mac with no lid, which is not the same as a lid that is open:
    /// a desktop can never be in the situation this type exists to describe.
    static func isClosed() -> Bool? {
        let root = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        guard
            let value = IORegistryEntryCreateCFProperty(
                root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        else { return nil }
        return value.takeRetainedValue() as? Bool
    }

    /// Whether a hold can keep this Mac awake as things stand.
    ///
    /// The exception is Apple's own: a shut lid does not sleep the machine when
    /// an external display is attached and it is on mains power. Either half
    /// missing and the lid wins, whatever anybody is asserting.
    ///
    /// Pure and injected rather than reading the world itself, because the
    /// interesting cases are the ones this Mac is not in at the moment.
    static func holdCanWork(lidClosed: Bool?, externalDisplays: Int, onAC: Bool) -> Bool {
        guard lidClosed == true else { return true }
        return externalDisplays > 0 && onAC
    }
}
