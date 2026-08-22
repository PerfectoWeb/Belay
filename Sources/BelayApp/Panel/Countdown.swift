import SwiftUI

/// Remaining time, written the same everywhere it appears: hours, minutes
/// and seconds, two digits each, always — `02:30:00`, `00:03:17`, `00:00:03`
/// — because a clock that drops a unit as it counts is a clock that jumps:
/// `01:00:00` becoming `59:59` moved every digit at once.
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

    static func string(remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }
}
