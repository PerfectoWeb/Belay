import BelayChannel
import SwiftUI

/// One version's worth of news, in the shape a person reads rather than the
/// shape a changelog is written in.
///
/// `CHANGELOG.md` is the record: every fix, in English, at whatever length the
/// fix deserved. This is the announcement: one headline, a paragraph or two,
/// and a picture — the card a product shows once after an update. They are
/// deliberately not generated from each other. A changelog entry that has to
/// double as interface copy ends up serving neither.
struct ReleaseNote: Equatable {
    /// The marketing version these notes belong to, exactly as
    /// `CFBundleShortVersionString` spells it.
    let version: String

    /// The one thing this release is about.
    let title: LocalizedStringKey

    /// A paragraph or two under the title. Whole thoughts, centred, short:
    /// the card is read standing up.
    var paragraphs: [Paragraph]

    /// An image from the asset catalogue, drawn full width under the text and
    /// bleeding to the card's bottom edge. 400 by 220 points; supplied at 2x.
    var image: String?

    struct Paragraph: Equatable, Identifiable {
        let text: LocalizedStringKey
        /// True for anything the App Store build does not have. It updates
        /// itself through the store and has no Homebrew or lid helper, so
        /// telling somebody there about either is the same inaccuracy that
        /// took Precise Detection out of the store listing.
        var directOnly = false
        let id = UUID()

        init(_ text: LocalizedStringKey, directOnly: Bool = false) {
            self.text = text
            self.directOnly = directOnly
        }

        static func == (lhs: Paragraph, rhs: Paragraph) -> Bool {
            lhs.text == rhs.text && lhs.directOnly == rhs.directOnly
        }
    }
}

/// The announcement for the version being released, and only that one.
///
/// **Adding a release.** Replace the entry — the window shows the update that
/// just happened and nothing else, and every skipped version's story lives in
/// `CHANGELOG.md`. Retire the old entry's strings from the catalogue when it
/// goes. The title and each paragraph are keys in
/// `Resources/Localizable.xcstrings` and have to be translated into every
/// language before the gate goes green: `LocalizationTests` counts the tables
/// and fails when they differ. That cost is the feature working.
///
/// A version with no entry here shows nothing and is recorded silently, which is
/// the right behaviour for a hotfix. Omission is a decision, not an oversight.
enum ReleaseNotes {
    /// Computed rather than stored: `LocalizedStringKey` is not `Sendable`, and
    /// it should not be — SwiftUI resolves it against the environment's locale
    /// as it draws, which is what lets the language picker change a window
    /// that is already open. And the channel filter below has to run per read.
    static var all: [ReleaseNote] {
        let direct = DistributionChannel.current == .direct
        return
            written
            .map { note in
                var note = note
                note.paragraphs = note.paragraphs.filter { direct || !$0.directOnly }
                return note
            }
            .filter { !$0.paragraphs.isEmpty }
    }

    private static var written: [ReleaseNote] {
        [
            ReleaseNote(
                version: "1.3.3",
                title: "Belay stays in sync",
                paragraphs: [
                    .init(
                        """
                        Finished turns now go quiet within seconds and stay that way. No stale rows \
                        after restarts, no jumping back to Working, and the idle timer starts when the \
                        session actually goes quiet.
                        """),
                    .init(
                        """
                        If Codex quits or crashes mid-turn, Belay notices the process is gone and lets \
                        go within seconds instead of waiting through the retry grace period.
                        """)
                ]
            )
        ]
    }
}
