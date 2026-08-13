import AppKit
import SwiftUI

/// What Belay has done for you.
///
/// The headline is deliberately **not** total time held. The Mac was not going
/// to sleep while you were typing, so that number flatters the app without
/// meaning anything. Time held *while you were away* is the part that would
/// otherwise have ended in a dead run.
struct StatisticsPane: View {
    let statistics: UsageStatistics
    /// Throwing the numbers away is the one destructive thing in Settings, so
    /// it asks first and the pane does not own the data it would be discarding.
    var onReset: () -> Void = {}

    @State private var isConfirmingReset = false

    /// 0 when the pane appears, 1 once it has settled. Everything that is a
    /// number counts up to it and every bar grows into it.
    ///
    /// Not decoration. The pane is a wall of figures, and a wall of figures
    /// that is simply *there* when you arrive gives the eye nowhere to start;
    /// counting up puts the headline first and the chart last in the order they
    /// should be read. It runs once, on arrival, and then holds still.
    @State private var reveal: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 1.8, not the 1.15 it started at. At the shorter length the chart filled
    // in about a fifth of a second, which is quick enough that the eye reads
    // the finished state and never sees it happen.
    static let revealSeconds: Double = 1.8

    /// Ease out, so the numbers sprint and then arrive rather than crawling to
    /// a stop. Static and internal so a test can walk it: it has to be 0 at 0
    /// and exactly 1 at the end, and the first version of this was neither.
    static func eased(_ progress: Double) -> Double {
        let clamped = min(1, max(0, progress))
        return 1 - pow(1 - clamped, 3)
    }

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
                StarAsk(rescued: statistics.totalRescued)
                shareRow
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Driven by hand rather than by `withAnimation`.
        //
        // The first attempt set `reveal` to 0 and then animated it to 1 inside
        // the same `onAppear`. SwiftUI coalesced the two into one update, the
        // pane arrived finished, and the recording of it was thirteen seconds
        // of a static screen. This walks the value itself, which cannot be
        // coalesced away, and the loop ends when it arrives so nothing is left
        // ticking behind a pane that has stopped moving.
        .task {
            guard !reduceMotion else {
                reveal = 1
                return
            }
            let start = Date()
            while reveal < 1, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                reveal = Self.eased(Date().timeIntervalSince(start) / Self.revealSeconds)
            }
        }
    }

    private var empty: some View { EmptyStatistics() }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ElapsedTime.compact(statistics.totalAway * reveal))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                // No implicit animation. SwiftUI's default for a Text whose
                // content changed is a cross-fade, and a cross-fade running
                // sixty times a second over a counter is a smear, not a count.
                .transaction { $0.animation = nil }
            Text("kept working while you were away from the keyboard")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var figures: some View {
        // Wide gaps because the captions are: "запусков спасено" is twice the
        // width of "runs saved", and four columns set to English spacing run
        // into each other in every language but English.
        HStack(alignment: .top, spacing: 34) {
            // Each one lands a beat after the one to its left, so the row
            // reads left to right rather than arriving as a block.
            Figure(
                value: "\(Int((Double(statistics.totalRescued) * counted(0)).rounded()))",
                caption: "runs rescued")
            Figure(
                value: ElapsedTime.compact(statistics.longestHold * counted(1)),
                caption: "longest run")
            Figure(
                value: "\(Int((Double(statistics.totalHolds) * counted(2)).rounded()))",
                caption: "runs watched")
            Figure(
                value: ElapsedTime.compact(statistics.totalHeld * counted(3)), caption: "total held")
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST 14 DAYS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            DayBars(days: statistics.recent(14), reveal: reveal)
                .frame(height: 56)
            if let since {
                // The scope of everything above it. Without a start date the
                // totals are a number with no denominator.
                Text("Since \(since)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// How far along the count for the figure in column `index` is. The row
    /// finishes inside the first two thirds of the reveal, so the chart is the
    /// last thing to arrive.
    private func counted(_ index: Int) -> Double {
        let start = Double(index) * 0.07
        return min(1, max(0, (reveal - start) / 0.42))
    }

    private var since: String? {
        statistics.firstRun.map {
            $0.formatted(.dateTime.day().month(.wide).year())
        }
    }

    private var shareRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Numbers stay on this Mac unless you share them.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                // Away from the two it must not be mistaken for, and quiet:
                // a bordered button beside two bordered buttons is a button you
                // click by aiming badly.
                Button("Reset…") { isConfirmingReset = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                Spacer(minLength: 8)
                CopyStatisticsCardButton(statistics: statistics)
                ShareStatisticsButton(statistics: statistics)
            }
        }
        .alert("Erase your statistics?", isPresented: $isConfirmingReset) {
            Button("Erase", role: .destructive, action: onReset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Belay keeps no copy anywhere else.")
        }
    }

    /// See the headline: a counting number has to redraw, not dissolve.
    private struct Figure: View {
        let value: String
        let caption: LocalizedStringKey

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .transaction { $0.animation = nil }
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
    var reveal: Double = 1

    var body: some View {
        let peak = max(days.map(\.heldSeconds).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 3) {
                    GeometryReader { geometry in
                        let full = geometry.size.height
                        // The chart fills left to right across the back half of
                        // the reveal, so it arrives after the figures rather
                        // than competing with them.
                        let grown = min(1, max(0, (reveal - 0.3 - Double(index) * 0.028) / 0.3))
                        let held = full * day.heldSeconds / peak * grown
                        let away = full * day.awaySeconds / peak * grown
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
