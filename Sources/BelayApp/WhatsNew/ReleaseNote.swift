import BelayChannel
import SwiftUI

/// One version's worth of news, in the shape a person reads rather than the
/// shape a changelog is written in.
///
/// `CHANGELOG.md` is the record: every fix, in English, at whatever length the
/// fix deserved. This is the announcement: a few lines, translated, about things
/// somebody would notice. They are deliberately not generated from each other. A
/// changelog entry that has to double as interface copy ends up serving neither.
struct ReleaseNote: Equatable {
    /// The marketing version these notes belong to, exactly as
    /// `CFBundleShortVersionString` spells it.
    let version: String

    /// The three to five things worth an icon and a sentence.
    var items: [Item]

    /// One line of news: what it is, what it means, and a symbol so the eye can
    /// find its way down the list without reading every word.
    struct Item: Equatable, Identifiable {
        /// An SF Symbol name, drawn as a light blue outline. Checked by
        /// `ReleaseNotesTests`, because a symbol that does not exist on the
        /// running system draws nothing at all and leaves a hole.
        let symbol: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey

        /// True for anything the App Store build does not have. It updates
        /// itself through the store and has no Homebrew or lid helper, so
        /// telling somebody there about either is the same inaccuracy that
        /// took Precise Detection out of the store listing.
        var directOnly = false

        /// Stable within a version: the symbol is what distinguishes one row
        /// from another, and no version repeats one.
        var id: String { symbol }
    }
}

/// The announcement for the version being released, and only that one.
///
/// **Adding a release.** Replace the entry — the window shows the update that
/// just happened and nothing else, and every skipped version's story lives in
/// `CHANGELOG.md`. Retire the old entry's strings from the catalogue when it
/// goes. Three to five items, each earning its icon. Each `title` and `body`
/// is a key in `Resources/Localizable.xcstrings` and has to be translated into
/// every language before the gate goes green: `LocalizationTests` counts the
/// tables and fails when they differ. That cost is the feature working.
///
/// A version with no entry here shows nothing and is recorded silently, which is
/// the right behaviour for a hotfix. Omission is a decision, not an oversight.
enum ReleaseNotes {
    /// The outlines these notes draw from, kept as a set so a release can be
    /// written by picking one rather than by inventing one.
    enum Mark {
        static let toggle = "capsule.lefthalf.filled"
        static let code = "chevron.left.forwardslash.chevron.right"
        static let laptop = "laptopcomputer"
        static let trace = "waveform.path.ecg.rectangle"
        static let update = "arrow.triangle.2.circlepath"
        static let told = "bell.badge"
        static let quiet = "speaker.slash"
        static let safety = "shield"
        static let speed = "bolt"
        static let language = "globe"
        static let night = "moon.stars"
        static let chart = "chart.bar"
        static let timer = "timer"
        static let team = "person.2"
        static let folder = "folder"
    }

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
                note.items = note.items.filter { direct || !$0.directOnly }
                return note
            }
            .filter { !$0.items.isEmpty }
    }

    private static var written: [ReleaseNote] {
        [
            ReleaseNote(
                version: "1.6.0",
                items: [
                    .init(
                        symbol: Mark.code,
                        title: "Copilot CLI is now built in",
                        body: """
                            Turn it on in Settings and Belay follows Copilot sessions on \
                            its own. Four agents, zero setup.
                            """),
                    .init(
                        symbol: Mark.folder,
                        title: "Watch an agent in any folder",
                        body: """
                            Custom config dirs and multi-profile setups: add every folder \
                            your agent works in, right from its tile.
                            """),
                    .init(
                        symbol: Mark.timer,
                        title: "The timer survives a relaunch",
                        body: """
                            An Always On timer picks up exactly where it was when Belay \
                            restarts.
                            """),
                    .init(
                        symbol: Mark.safety,
                        title: "Steadier everywhere",
                        body: """
                            A full audit fixed dozens of small faults, from launch stalls \
                            to sessions that overstayed their welcome.
                            """)
                ]
            ),
            ReleaseNote(
                version: "1.5.0",
                items: [
                    .init(
                        symbol: Mark.code,
                        title: "Cline is now built in",
                        body: """
                            Turn it on in Settings and Belay follows Cline sessions on \
                            its own. No folders to pick.
                            """),
                    .init(
                        symbol: Mark.speed,
                        title: "Precise Detection for every agent",
                        body: """
                            Claude Code, Codex, and Cline can tell Belay the exact moment \
                            work starts, finishes, or waits for you. One click in Settings.
                            """,
                        directOnly: true),
                    .init(
                        symbol: Mark.team,
                        title: "Agent teams in the panel",
                        body: """
                            When Cline spawns teammate agents, they appear under their \
                            session, just like Claude Code subagents.
                            """),
                    .init(
                        symbol: Mark.toggle,
                        title: "Settings, sharpened",
                        body: """
                            Each agent's detection now lives in its own tile, and every \
                            pane reads cleaner.
                            """)
                ]
            )
        ]
    }
}
