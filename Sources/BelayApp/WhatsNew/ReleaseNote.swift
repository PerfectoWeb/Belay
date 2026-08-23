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
                version: "1.4.0",
                items: [
                    .init(
                        symbol: Mark.timer,
                        title: "Keep your Mac awake for a set time",
                        body: """
                            Choose 15 minutes to 12 hours from the menu bar. Belay shows the countdown and \
                            lets your Mac sleep when time's up.
                            """),
                    .init(
                        symbol: Mark.safety,
                        title: "Hold again with one click",
                        body: """
                            If a timer or awake limit ends the hold, the panel tells you why and offers Hold \
                            Again. Unlocking your Mac resumes it automatically.
                            """),
                    .init(
                        symbol: Mark.night,
                        title: "Countdown on the dimmed screen",
                        body: """
                            When Belay dims the display at night, the time left appears in the center.
                            """),
                    .init(
                        symbol: Mark.chart,
                        title: "Hear your week",
                        body: """
                            Move across the chart in Statistics and each day plays a note. Busier days sound \
                            higher.
                            """)
                ]
            )
        ]
    }
}
