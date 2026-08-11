import AppKit
import SwiftUI

/// What Vigil has done for you.
///
/// The headline is deliberately **not** total time held. The Mac was not going
/// to sleep while you were typing, so that number flatters the app without
/// meaning anything. Time held *while you were away* is the part that would
/// otherwise have ended in a dead run.
struct StatisticsPane: View {
    let statistics: UsageStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if statistics.isEmpty {
                empty
            } else {
                headline
                Divider()
                figures
                Divider()
                chart
                shareRow
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing to show yet")
                .font(.system(size: 15, weight: .semibold))
            Text(
                """
                Once Vigil has held your Mac awake through an agent run, this is \
                where you will see what that was worth: how long it kept working \
                while you were away, and how many runs would otherwise have died \
                when the Mac went to sleep.
                """
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("Nothing here ever leaves this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 120, alignment: .top)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ElapsedTime.compact(statistics.totalAway))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("kept working while you were away from the keyboard")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var figures: some View {
        HStack(alignment: .top, spacing: 26) {
            Figure(value: "\(statistics.totalRescued)", caption: "runs rescued")
            Figure(value: ElapsedTime.compact(statistics.longestHold), caption: "longest run")
            Figure(value: "\(statistics.totalHolds)", caption: "runs watched")
            Figure(value: ElapsedTime.compact(statistics.totalHeld), caption: "total held")
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST 14 DAYS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            DayBars(days: statistics.recent(14))
                .frame(height: 56)
        }
    }

    private var shareRow: some View {
        HStack(spacing: 8) {
            Text("Numbers stay on this Mac unless you share them.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            CopyStatisticsCardButton(statistics: statistics)
            ShareStatisticsButton(statistics: statistics)
        }
    }

    private struct Figure: View {
        let value: String
        let caption: LocalizedStringKey

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A bar per day, scaled to the busiest one. Empty days keep their slot so the
/// shape of a week is readable.
private struct DayBars: View {
    let days: [UsageStatistics.Day]

    var body: some View {
        let peak = max(days.map(\.heldSeconds).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(days) { day in
                VStack(spacing: 3) {
                    GeometryReader { geometry in
                        let full = geometry.size.height
                        let held = full * day.heldSeconds / peak
                        let away = full * day.awaySeconds / peak
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.tint.opacity(0.25))
                                .frame(height: max(held, day.heldSeconds > 0 ? 2 : 1))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.tint)
                                .frame(height: max(away, 0))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                    Text(Self.weekday(day.date))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel(Self.spoken(day))
            }
        }
    }

    /// Built once. `DateFormatter` is among the more expensive things in
    /// Foundation and this ran fourteen times per body pass.
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private static func weekday(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    private static func spoken(_ day: UsageStatistics.Day) -> String {
        guard day.heldSeconds > 0 else { return String(localized: "no runs") }
        return String(
            localized:
                "\(ElapsedTime.spoken(day.heldSeconds)) held, \(ElapsedTime.spoken(day.awaySeconds)) away")
    }
}
