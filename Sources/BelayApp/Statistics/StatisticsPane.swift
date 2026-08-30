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
    var history: [SessionRecord] = []
    /// Throwing the numbers away is the one destructive thing in Settings, so
    /// it asks first and the pane does not own the data it would be discarding.
    var onReset: () -> Void = {}

    /// The day under the cursor, if it has anything to say. While set, the
    /// figure row speaks for that day and the chart label names its date.
    @State private var hovered: UsageStatistics.Day?
    /// Cursor on the headline's caption: the figure flips to the time Belay
    /// held while you were at the Mac.
    @State private var hoveringPresence = false
    /// True one pass after the reveal lands. Gating the figure morph on this
    /// rather than on `reveal >= 1` keeps the count-up's final tick a hard
    /// redraw instead of a lone animated digit-roll.
    @State private var settled = false

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
                if !history.isEmpty {
                    Divider()
                    RecentSessions(records: history)
                }
                StarAsk(rescued: statistics.totalRescued)
                StatisticsFooter(statistics: statistics, onReset: onReset)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Driven by hand rather than by `withAnimation`.
        //
        // Setting `reveal` to 0 and animating it to 1 inside the same
        // `onAppear` does not work: SwiftUI coalesces the two into one update
        // and the pane arrives finished. Walking the value cannot be coalesced
        // away, and the loop ends when it arrives, so nothing is left ticking
        // behind a pane that has stopped moving.
        .task {
            guard !reduceMotion else {
                reveal = 1
                settled = true
                return
            }
            let start = Date()
            while reveal < 1, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                reveal = Self.eased(Date().timeIntervalSince(start) / Self.revealSeconds)
            }
            settled = true
        }
    }

    private var empty: some View { EmptyStatistics() }

    private var headline: some View {
        // The headline's flip side: held minus away is the part that ran with
        // you right there. Hovering the caption shows it, same rolling morph
        // as the figures.
        let withYou = max(0, statistics.totalHeld - statistics.totalAway)
        let present = hoveringPresence && settled
        return VStack(alignment: .leading, spacing: 4) {
            Text(ElapsedTime.compact(present ? withYou : statistics.totalAway * reveal))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                // No implicit animation while counting up. SwiftUI's default
                // for a Text whose content changed is a cross-fade, and a
                // cross-fade running sixty times a second over a counter is a
                // smear, not a count. The morph switches on once settled.
                .transaction { $0.animation = morphs ? .easeOut(duration: 0.25) : nil }
            // Both variants sit hidden underneath so the caption keeps one
            // size whichever is showing. Without the reservation, hovering
            // the tail of the long string shrank the text out from under the
            // cursor, the hover ended, the text grew back — and the two
            // morphs ran in a loop for as long as the cursor sat there.
            ZStack(alignment: .leading) {
                Text("kept working while you were right here").hidden()
                Text("kept working while you were away from the keyboard").hidden()
                Text(
                    present
                        ? "kept working while you were right here"
                        : "kept working while you were away from the keyboard"
                )
                .contentTransition(.numericText())
                .transaction { $0.animation = morphs ? .easeOut(duration: 0.25) : nil }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .onHover { hoveringPresence = $0 }
        }
    }

    private var figures: some View {
        // Wide gaps because the captions are: "запусков спасено" is twice the
        // width of "runs saved", and four columns set to English spacing run
        // into each other in every language but English.
        // A hovered day borrows the whole row: same captions, its numbers.
        // The morph is on only after the reveal, so the opening count-up
        // stays a hard redraw and never smears (see Figure).
        HStack(alignment: .top, spacing: 34) {
            // Each one lands a beat after the one to its left, so the row
            // reads left to right rather than arriving as a block.
            Figure(
                value: hovered.map { "\($0.rescued)" }
                    ?? "\(Int((Double(statistics.totalRescued) * counted(0)).rounded()))",
                caption: "runs rescued", morphs: morphs)
            Figure(
                value: ElapsedTime.compact(hovered?.longestHold ?? statistics.longestHold * counted(1)),
                caption: "longest run", morphs: morphs)
            Figure(
                value: hovered.map { "\($0.holds)" }
                    ?? "\(Int((Double(statistics.totalHolds) * counted(2)).rounded()))",
                caption: "runs watched", morphs: morphs)
            Figure(
                value: ElapsedTime.compact(hovered?.heldSeconds ?? statistics.totalHeld * counted(3)),
                caption: "total held", morphs: morphs)
        }
    }

    /// Digit-rolls are motion too: Reduce Motion turns the hover swap into a
    /// plain redraw, the same way it flattens the reveal.
    private var morphs: Bool { settled && !reduceMotion }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let hovered {
                    Text(verbatim: Self.named(hovered.date))
                } else {
                    Text("LAST 14 DAYS")
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered?.id)
            DayBars(
                days: statistics.recent(14), reveal: reveal, hovered: hovered,
                onHover: { hovered = $0 },
                onLeave: { day in
                    // Live read: an enter for the next bar may already have
                    // landed, and its hover must survive this bar's exit.
                    if hovered?.id == day.id { hovered = nil }
                }
            )
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

    /// "FRIDAY, 15 AUGUST" in the user's locale, for the chart label while a
    /// bar is hovered. Uppercased to sit where LAST 14 DAYS sits.
    static func named(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }

    private var since: String? {
        statistics.firstRun.map {
            $0.formatted(.dateTime.day().month(.wide).year())
        }
    }

    /// See the headline: a counting number has to redraw, not dissolve —
    /// until the reveal is over. After it, the only changes are the hover
    /// borrowing the row and handing it back, and those roll digit by digit
    /// (`numericText`), which is the system's own way of saying "same
    /// counter, different value".
    private struct Figure: View {
        let value: String
        let caption: LocalizedStringKey
        var morphs = false

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .transaction { $0.animation = morphs ? .easeOut(duration: 0.25) : nil }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
