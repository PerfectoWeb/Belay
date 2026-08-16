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
    /// - **Onboarded, an older version:** show everything released since, and
    ///   record.
    ///
    /// The last row is the one with a choice in it. Apple's own screens show
    /// only the version just installed; that loses whatever was in the versions
    /// somebody skipped, and skipping is normal for an app updated on the
    /// user's schedule rather than the store's. Everything newer than what they
    /// saw is what they have not seen.
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

        let fresh =
            catalogue
            .compactMap { note -> (AppVersion, ReleaseNote)? in
                AppVersion(note.version).map { ($0, note) }
            }
            // Not `> seen` alone: notes for a version this build does not have
            // yet must not leak out of a repository into a screen.
            .filter { $0.0 > seen && $0.0 <= now }
            .sorted { $0.0 > $1.0 }
            .map(\.1)

        // A version with no notes written for it is not an occasion. This is the
        // ordinary case for a hotfix, and showing an empty window for one would
        // teach people to dismiss the screen without reading it.
        guard !fresh.isEmpty else { return .recordOnly(current) }
        return .show(notes: capped(fresh), record: current)
    }

    /// The most items the window will show, across however many versions.
    ///
    /// The window has no scroll view: it grows with its content, which is the
    /// only arrangement that cannot clip a sentence in half. That makes the item
    /// count the height, so the count is bounded here rather than by hoping
    /// nobody skips four releases. Six rows of two or three lines each is about
    /// a 700-point window, which fits the shortest screen this app supports.
    static let maximumItems = 6

    /// Trims from the oldest end, because the version somebody just installed is
    /// the one they came to read about. A version is dropped whole rather than
    /// half-shown: a heading over one of its four items would misrepresent it.
    private static func capped(_ notes: [ReleaseNote]) -> [ReleaseNote] {
        var kept: [ReleaseNote] = []
        var count = 0
        for note in notes {
            // The newest version is kept whatever its length. If a release has
            // seven things to say, that is the release being unusual, not the
            // reader being shown too much.
            guard kept.isEmpty || count + note.items.count <= maximumItems else { break }
            kept.append(note)
            count += note.items.count
        }
        return kept
    }
}
