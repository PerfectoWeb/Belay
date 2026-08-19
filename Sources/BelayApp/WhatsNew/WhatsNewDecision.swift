import Foundation

/// Whether to show the release notes on this launch, and which ones.
///
/// Pure, so the whole table can be tested without a window, a bundle or a
/// preferences file. Every branch below was a decision, and the wrong answer to
/// any of them shows a screen to somebody who did not earn it.
enum WhatsNewDecision {
    /// What the launch should do about the release notes.
    enum Outcome: Equatable {
        /// Show these notes, newest first, then record `record`.
        case show(notes: [ReleaseNote], record: String)
        /// Show nothing, but write `record` so the next update can be detected.
        case recordOnly(String)
        /// Show nothing and write nothing.
        case nothing
    }

    /// - Parameters:
    ///   - current: this build's marketing version.
    ///   - lastSeen: the version whose notes were last shown. `nil` on an
    ///     install that predates the key.
    ///   - onboarded: whether the welcome screen has been got through.
    ///   - catalogue: every version that has notes, in any order.
    /// - Returns: what this launch should show, and what it should write down.
    ///
    /// The rules, in the order they are asked:
    ///
    /// - **Not onboarded, anything:** nothing. The welcome screen owns a first
    ///   launch, and two windows on one launch is a queue, not an introduction.
    /// - **Onboarded, nothing seen:** record only. Somebody who has used Belay
    ///   since before this key existed is *not* new, and must not be told about
    ///   a version they may have been running for months.
    /// - **Onboarded, this version:** nothing. Already told.
    /// - **Onboarded, a newer version:** record only. A downgrade has nothing to
    ///   announce, and leaving the higher number stored would announce nothing
    ///   on the way back up either.
    /// - **Onboarded, an older version:** show the version just installed, and
    ///   record.
    ///
    /// The last row once showed everything released since the version last
    /// seen. That was reversed on purpose: this window announces the update
    /// that just happened and nothing else — the agreed rule, written into
    /// 1.2.1's own changelog — and the versions somebody skipped are exactly
    /// what `CHANGELOG.md` is for. An announcement that doubles as an archive
    /// grows past the screen and teaches people to dismiss it unread.
    static func outcome(
        current: String,
        lastSeen: String?,
        onboarded: Bool,
        catalogue: [ReleaseNote] = ReleaseNotes.all
    ) -> Outcome {
        guard onboarded else { return .nothing }
        guard let now = AppVersion(current) else { return .nothing }
        guard let seen = AppVersion(lastSeen) else { return .recordOnly(current) }
        guard seen < now else {
            // Equal, or a downgrade. Both write, so the stored version is always
            // the one that is running.
            return seen == now ? .nothing : .recordOnly(current)
        }

        // A version with no notes written for it is not an occasion. This is the
        // ordinary case for a hotfix, and showing an empty window for one would
        // teach people to dismiss the screen without reading it.
        guard let note = catalogue.first(where: { AppVersion($0.version) == now }) else {
            return .recordOnly(current)
        }
        return .show(notes: [note], record: current)
    }
}
