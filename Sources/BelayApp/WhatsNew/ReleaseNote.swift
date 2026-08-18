import BelayChannel
import SwiftUI

/// One version's worth of news, in the shape a person reads rather than the
/// shape a changelog is written in.
///
/// `CHANGELOG.md` is the record: every fix, in English, at whatever length the
/// fix deserved. This is the announcement: a few lines, translated, about things
/// somebody would notice. They are deliberately not generated from each other. A
/// changelog entry that has to double as interface copy ends up serving neither,
/// and the moment they share a source the screen inherits the changelog's length
/// and its vocabulary.
struct ReleaseNote: Equatable {
    /// The marketing version these notes belong to, exactly as
    /// `CFBundleShortVersionString` spells it.
    let version: String

    /// The three to five things worth an icon and a sentence.
    var items: [Item]

    /// Everything else, one short line each, under a quiet heading. The release
    /// where four things are worth a row and six more are worth a mention is the
    /// ordinary release; without this the choice was between a wall of icons and
    /// leaving real work unannounced.
    var asides: [Aside] = []

    /// One line of news: what it is, what it means, and a symbol so the eye can
    /// find its way down the list without reading every word.
    struct Item: Equatable, Identifiable {
        /// An SF Symbol name. Checked by `ReleaseNotesTests`, because a symbol
        /// that does not exist on the running system draws nothing at all and
        /// leaves a hole where the icon should be.
        let symbol: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey

        /// True for anything the App Store build does not have. It updates
        /// itself through the store and has no Homebrew, so telling somebody
        /// there about either is the same inaccuracy that took Precise Detection
        /// out of the store listing.
        var directOnly = false

        /// Stable within a version: the symbol is what distinguishes one row
        /// from another, and no version repeats one.
        var id: String { symbol }
    }

    /// A one-line mention. No icon, because an icon is a promise that the line
    /// is worth stopping at.
    struct Aside: Equatable, Identifiable {
        let text: LocalizedStringKey
        var directOnly = false
        let id = UUID()

        static func == (lhs: Aside, rhs: Aside) -> Bool {
            lhs.text == rhs.text && lhs.directOnly == rhs.directOnly
        }
    }
}

/// Every version that has anything to announce.
///
/// **Adding a release.** Put the newest entry at the top. Three to five items,
/// each earning its icon, and everything else as an aside. Each `title`, `body`
/// and aside is a new key in `Resources/Localizable.xcstrings` and has to be
/// translated into every language before the gate goes green:
/// `LocalizationTests` counts the tables and fails when they differ. That cost is
/// the feature working. An announcement screen that shows English to a German
/// user is worse than no announcement.
///
/// A version with no entry here shows nothing and is recorded silently, which is
/// the right behaviour for a hotfix. Omission is a decision, not an oversight.
enum ReleaseNotes {
    /// Computed rather than stored, for two reasons. `LocalizedStringKey` is not
    /// `Sendable`, and it should not be: it is a key SwiftUI resolves against the
    /// environment's locale as it draws, which is what lets the language picker
    /// change a window that is already open. And the channel filter below has to
    /// run per read rather than once at first touch.
    static var all: [ReleaseNote] {
        // The channel is read from the bundle rather than from
        // `ReleaseChecker.isSupported`, which says the same thing but is bound to
        // the main actor; these notes are read from tests and from a decision
        // that is deliberately not.
        let direct = DistributionChannel.current == .direct
        return
            written
            .map { note in
                var note = note
                note.items = note.items.filter { direct || !$0.directOnly }
                note.asides = note.asides.filter { direct || !$0.directOnly }
                return note
            }
            .filter { !$0.items.isEmpty }
    }

    private static var written: [ReleaseNote] {
        [
            ReleaseNote(
                version: "1.2.0",
                items: [
                    .init(
                        symbol: "arrow.down.circle",
                        title: "One click updater",
                        body: "Update Now fetches the new version itself. No web page, no hunting.",
                        directOnly: true),
                    .init(
                        symbol: "folder",
                        title: "Watch any folder",
                        body: """
                            Point Belay at a folder your own tool writes to. It \
                            remembers the ones you pick.
                            """),
                    .init(
                        symbol: "pause",
                        title: "A mark that says paused",
                        body: "When Belay lets go on purpose, the menu bar shows it.",
                    ),
                    .init(
                        symbol: "sparkles",
                        title: "This screen",
                        body: "Every update now opens with what changed. Once, then never again."
                    )
                ],
                asides: [
                    .init(text: "Quitting Belay releases your Mac at once."),
                    .init(text: "The welcome screen opens centred on macOS 15."),
                    .init(text: "Install with Homebrew: brew install --cask belay.", directOnly: true)
                ])
        ]
    }
}
