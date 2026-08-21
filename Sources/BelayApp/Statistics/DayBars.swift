import SwiftUI

/// A bar per day, scaled to the busiest one. Empty days keep their slot so the
/// shape of a week is readable.
///
/// Hovering a bar with anything in it lifts it and tells the pane, which
/// re-points the figure row at that day; the other bars step back a little so
/// the eye lands where the cursor is. Empty days do not react: there is
/// nothing to show, and a lift with no numbers behind it is a lie.
struct DayBars: View {
    let days: [UsageStatistics.Day]
    var reveal: Double = 1
    var hovered: UsageStatistics.Day?
    var onHover: (UsageStatistics.Day?) -> Void = { _ in }
    /// The cursor left this bar. Separate from `onHover(nil)` on purpose: when
    /// the cursor crosses straight from bar A to bar B, AppKit's enter and
    /// exit arrive in no particular order, both before a re-render, so the
    /// exit handler here would compare against a stale `hovered`. The owner
    /// holds the live state; only it can decide whether the leave still
    /// matters.
    var onLeave: (UsageStatistics.Day) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let peak = max(days.map(\.heldSeconds).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                let lit = hovered?.id == day.id
                let dimmed = hovered != nil && !lit
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
                                .fill(.tint.opacity(lit ? 0.4 : 0.25))
                                .frame(height: max(held, day.heldSeconds > 0 ? 2 : 1))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.tint)
                                .frame(height: max(away, 0))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        // A lift from the baseline, the way Screen Time does
                        // it: the bar grows, it does not float.
                        .scaleEffect(
                            y: lit && !reduceMotion ? 1.06 : 1, anchor: .bottom
                        )
                        .opacity(dimmed ? 0.55 : 1)
                    }
                    Text(Self.weekday(day.date))
                        .font(.system(size: 8, weight: lit ? .semibold : .regular))
                        .foregroundStyle(lit ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.25), value: hovered?.id)
                .onHover { inside in
                    if inside {
                        // A note per bar, pitched by height, only on arrival
                        // at a new bar: the hover fires again on every
                        // re-render while the cursor rests.
                        if day.heldSeconds > 0, hovered?.id != day.id {
                            Feedback.playBar(step: Feedback.barStep(held: day.heldSeconds, peak: peak))
                        }
                        onHover(day.heldSeconds > 0 ? day : nil)
                    } else {
                        onLeave(day)
                    }
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
