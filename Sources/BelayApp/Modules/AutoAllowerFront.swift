import AppKit
import Foundation

extension AutoAllower {
    /// A visit can pull the agent's app to the front and the person to its
    /// desktop. Whatever was in front before comes back, if nobody has
    /// touched the Mac in the meantime.
    func putBack(_ front: NSRunningApplication?) {
        guard let front, !front.isTerminated,
            front.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return }
        let now = NSWorkspace.shared.frontmostApplication
        guard now?.processIdentifier != front.processIdentifier else {
            Diagnostics.note("autoallow front=kept")
            return
        }
        guard !desks.contains(where: { $0.screen.isInUse }) else {
            Diagnostics.note("autoallow front=left")
            return
        }
        let done = front.activate(options: [.activateIgnoringOtherApps])
        Diagnostics.note("autoallow front=\(done ? "restored" : "refused")")
    }
}
