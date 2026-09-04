import Foundation
import IOKit.pwr_mgt

/// Whether some other app is holding the display awake right now — a fullscreen
/// video, a video call, a Keynote, a screen share.
///
/// Night dimming does what the machine's own display sleep would have done, and
/// the machine would not have slept the screen while an app asserts
/// `PreventUserIdleDisplaySleep`. That assertion is the sanctioned signal for
/// "keep the screen on for the person to look at", and Belay honours it too.
///
/// Audio is deliberately **not** a signal here. A player raises a *system*-sleep
/// assertion for sound, not a display one, precisely because music is meant to
/// keep playing with the screen off — so keying off audio would refuse to dim
/// for background music, which is the opposite of what the screen wants. Only a
/// real display-sleep assertion counts.
///
/// `IOPMCopyAssertionsByProcess` is public and needs no entitlement, so this
/// reads the same in the sandboxed build. Belay's own hold raises a display
/// assertion as well, so our own process is excluded — the question is whether
/// *someone else* is keeping the screen up.
enum DisplayHeldElsewhere {
    private static let displayTypes: Set<String> = [
        kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
        kIOPMAssertionTypeNoDisplaySleep as String
    ]

    static func now(ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> Bool {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
            let assertions = byProcess?.takeRetainedValue() as? [Int: [[String: Any]]]
        else { return false }

        for (pid, held) in assertions where Int32(pid) != ownPID {
            for assertion in held {
                guard let type = assertion[kIOPMAssertionTypeKey as String] as? String,
                    displayTypes.contains(type)
                else { continue }
                // A level of 0 is a released assertion the process has not
                // torn down yet; only a live one keeps the screen up.
                let level = assertion[kIOPMAssertionLevelKey as String] as? Int ?? kIOPMAssertionLevelOn
                if level != kIOPMAssertionLevelOff { return true }
            }
        }
        return false
    }
}
