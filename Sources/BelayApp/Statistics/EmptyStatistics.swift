import SwiftUI

/// What Statistics shows before there is anything to show.
///
/// It used to be a left-aligned heading over a four-line paragraph explaining
/// what would eventually appear. Nobody reads a paragraph in an empty state:
/// they look at it, understand there is nothing here, and leave. So it is now
/// the shape of the thing that is missing, centred, with one line under it.
///
/// The bars run and then stop. A first pass had them breathing continuously and
/// it was worse than still: slow perpetual movement in a corner with nothing to
/// say reads as a progress indicator for something that is not happening. A
/// short burst says the pane is alive, and the stillness afterwards says there
/// is nothing to wait for.
struct EmptyStatistics: View {
    /// Resting heights, so the shape is a plausible chart rather than a ramp.
    private static let bars: [CGFloat] = [0.42, 0.68, 0.5, 0.85, 0.6]

    /// How long between one burst and the next.
    private static let cycle: Double = 7
    /// How long the bars move for. Three passes along the row inside it.
    private static let burst: Double = 1.8

    var body: some View {
        VStack(spacing: 12) {
            chart
                .frame(width: 48, height: 28)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Nothing to show yet")
                    .font(.system(size: 15, weight: .semibold))
                Text("Your first agent run fills this in.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.cycle)
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, base in
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: max(4, proxy.size.height * height(base, index, time)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    /// Full swing during the burst, eased out at its end so the bars settle onto
    /// their resting heights instead of being cut off mid-move.
    private func height(_ base: CGFloat, _ index: Int, _ time: Double) -> CGFloat {
        guard time < Self.burst else { return base }
        let fade = min(1, (Self.burst - time) / 0.45)
        // Three passes across five bars, each a beat behind the one to its left,
        // so the movement travels rather than pulsing as one block.
        let wave = sin(time / Self.burst * 3 * 2 * .pi - Double(index) * 0.9)
        return base * (1 - 0.45 * fade * (0.5 + 0.5 * CGFloat(wave)))
    }
}
