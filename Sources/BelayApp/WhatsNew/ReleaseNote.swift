import SwiftUI

/// One version's worth of news, in the shape a person reads rather than the
/// shape a changelog is written in.
///
/// `CHANGELOG.md` is the record: every fix, in English, at whatever length the
/// fix deserved. This is the announcement: a handful of lines, translated,
/// about things somebody would notice. They are deliberately not generated from
/// each other. A changelog entry that has to double as interface copy ends up
/// serving neither, and the moment they share a source, the screen inherits the
/// changelog's length and its vocabulary.
struct ReleaseNote: Equatable {
    /// The marketing version these notes belong to, exactly as
    /// `CFBundleShortVersionString` spells it.
    let version: String
    let items: [Item]

    /// One line of news: what it is, what it means, and a symbol so the eye can
    /// find its way down the list without reading every word.
    struct Item: Equatable, Identifiable {
        /// An SF Symbol name. Checked by `ReleaseNotesTests`, because a symbol
        /// that does not exist on the running system draws nothing at all and
        /// leaves a hole where the icon should be.
        let symbol: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey

        /// Stable within a version: the symbol is what distinguishes one row
        /// from another, and no version repeats one.
        var id: String { symbol }
    }
}

/// Every version that has anything to announce.
///
/// **Adding a release.** Put the newest entry at the top, with three to five
/// items. Each `title` and `body` is a new key in `Resources/Localizable.xcstrings`
/// and has to be translated into all seven languages before the gate goes
/// green: `LocalizationTests` counts the tables and fails when they differ. That
/// cost is the feature working — an announcement screen that shows English to a
/// German user is worse than no announcement.
///
/// A version with no entry here shows nothing and is recorded silently, which
/// is the right behaviour for a hotfix. Omission is a decision, not an
/// oversight, and it does not need a placeholder.
enum ReleaseNotes {
    /// Computed rather than stored. `LocalizedStringKey` is not `Sendable`, and
    /// it should not be: it is a key SwiftUI resolves against the environment's
    /// locale as it draws, which is what lets the language picker change a
    /// window that is already open. A stored global of them would be resolved
    /// once, at first touch, in whatever language was current then.
    static var all: [ReleaseNote] {
        [
            ReleaseNote(
                version: "1.3.0",
                items: [
                    .init(
                        symbol: "arrow.down.circle",
                        title: "Updates arrive in one press",
                        body: """
                            Update Now downloads the new version itself instead of \
                            sending you to a web page to find it.
                            """),
                    .init(
                        symbol: "folder",
                        title: "Watch any folder",
                        body: """
                            Point Belay at a folder your own tool writes to, and \
                            your Mac stays awake while that folder is busy. The \
                            folders you choose are remembered.
                            """),
                    .init(
                        symbol: "pause",
                        title: "The menu bar says more",
                        body: """
                            When Belay stops on purpose, to save the battery or \
                            because it has been awake long enough, the mark shows \
                            it. A Mac that went quiet is never a mystery.
                            """),
                    .init(
                        symbol: "wrench.and.screwdriver",
                        title: "Fixes",
                        body: """
                            Quitting Belay now lets go of your Mac at once rather \
                            than a moment later, and the welcome screen opens in \
                            the middle of the screen on macOS 15.
                            """)
                ])
        ]
    }
}
