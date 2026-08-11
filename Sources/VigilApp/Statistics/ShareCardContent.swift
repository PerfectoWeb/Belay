import Foundation

/// The words and numbers that go on the share card, kept apart from the drawing
/// so the honesty rules can be tested without rasterising anything.
///
/// The headline is time held *while the user was away*, for the same reason the
/// pane leads with it: total time held is a number the Mac would have survived
/// without Vigil.
struct ShareCardContent: Equatable {
    struct Figure: Equatable {
        let value: String
        let label: String
    }

    let headline: String
    let caption: String
    let figures: [Figure]
    let days: [UsageStatistics.Day]
    let link: String

    init(_ statistics: UsageStatistics, now: Date = Date()) {
        headline = ElapsedTime.compact(statistics.totalAway)
        caption = Self.caption(statistics)
        figures = [
            Figure(value: "\(statistics.totalRescued)", label: String(localized: "runs rescued")),
            Figure(
                value: ElapsedTime.compact(statistics.longestHold),
                label: String(localized: "longest run")),
            Figure(value: "\(statistics.totalHolds)", label: String(localized: "runs watched")),
            Figure(
                value: ElapsedTime.compact(statistics.totalHeld),
                label: String(localized: "total held"))
        ]
        days = statistics.recent(14, now: now)
        // Without the scheme, because the card is read, not clicked.
        link = "github.com/\(Branding.repositorySlug)"
    }

    /// Everything printed on the card, in one string. Tests assert on what this
    /// is not allowed to say.
    var text: String {
        ([headline, caption, link] + figures.flatMap { [$0.value, $0.label] })
            .joined(separator: " ")
    }

    /// A card is an advertisement, which is exactly why this sentence has to be
    /// the one Vigil can defend. Nothing was rescued until something was left
    /// unattended, so with no rescues it claims only that the work carried on.
    private static func caption(_ statistics: UsageStatistics) -> String {
        guard statistics.totalRescued > 0 else {
            return String(
                localized: "of agent work that carried on while I was away from the keyboard.")
        }
        // Whole sentences per plural case: gluing a translated "runs" into a
        // translated sentence does not survive a language with cases.
        guard statistics.totalRescued > 1 else {
            return String(
                localized: "of agent work while I was away. Sleep would have interrupted one of those runs.")
        }
        return String(
            localized: """
                of agent work while I was away. Sleep would have interrupted \
                \(statistics.totalRescued) of those runs.
                """)
    }
}
