import SwiftUI

/// Remaining time, written the same everywhere it appears: two digits per
/// unit, always — `02:30:00`, `01:59` — because a clock whose width changes
/// as it counts is a clock that fidgets.
///
/// `Text(timerInterval:)` ticked by itself but would not pad, so this is a
/// `TimelineView` that redraws once a second, only while it is on screen.
struct Countdown: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.string(remaining: deadline.timeIntervalSince(context.date)))
                .monospacedDigit()
        }
    }

    /// Hours appear only once there are any; minutes and seconds always.
    static func string(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
