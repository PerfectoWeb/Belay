import SwiftUI

/// The pane's pure helpers, beside it for the file-length rule.
extension StatisticsPane {
    /// Ease out, so the numbers sprint and then arrive rather than crawling to
    /// a stop. Static and internal so a test can walk it: it has to be 0 at 0
    /// and exactly 1 at the end, and the first version of this was neither.
    static func eased(_ progress: Double) -> Double {
        let clamped = min(1, max(0, progress))
        return 1 - pow(1 - clamped, 3)
    }

    /// "FRIDAY, 15 AUGUST" in the user's locale, for the chart label while a
    /// bar is hovered. Uppercased to sit where LAST 14 DAYS sits.
    static func named(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }

    var since: String? {
        statistics.firstRun.map {
            $0.formatted(.dateTime.day().month(.wide).year())
        }
    }

    /// The Sessions side of the headline: same weight, its own subject. The
    /// number is the agents' time across every folder for all time — a row
    /// count was a number about the table, not about the work — and the
    /// caption carries the sessions and tokens behind it. All of it comes
    /// from the running totals, so nothing here shrinks as the list forgets.
    var sessionsHeadline: some View {
        let overall = ProjectTotals.over(history)
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: ElapsedTime.compact(overall.seconds))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(verbatim: overall.caption(withTime: false))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}
