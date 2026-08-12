import SwiftUI

/// What Statistics shows before there is anything to show.
///
/// It used to be a left-aligned heading over a four-line paragraph explaining
/// what would eventually appear. Nobody reads a paragraph in an empty state:
/// they look at it, understand there is nothing here, and leave. So it is now
/// the shape of the thing that is missing, centred, with one line under it.
///
/// The bars run and then stop. A version before this had them breathing
/// continuously and it was worse than still: slow perpetual movement in a
/// corner with nothing to say reads as a progress indicator for something that
/// is not happening. A short burst says the pane is alive, and the stillness
/// afterwards says there is nothing to wait for.
struct EmptyStatistics: View {
    /// Resting heights, so the shape is a plausible chart rather than a ramp.
    private static let bars: [CGFloat] = [0.42, 0.68, 0.5, 0.85, 0.6]

    /// How long between one burst and the next.
    static let cycle: Double = 7
    /// How long the bars move for. Two passes along the row inside it.
    static let burst: Double = 1.8

    /// Measured from when the pane appeared, not from the epoch.
    ///
    /// Phased to wall-clock, the burst was over before three quarters of the
    /// people who opened this pane could see it, and they waited up to five
    /// seconds for the one thing the rewrite was for.
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .onAppear { start = Date() }
    }

    @ViewBuilder private var chart: some View {
        if reduceMotion {
            bars(at: Self.cycle)
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                bars(
                    at: timeline.date.timeIntervalSince(start)
                        .truncatingRemainder(dividingBy: Self.cycle))
            }
        }
    }

    private func bars(at time: Double) -> some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, base in
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: max(4, proxy.size.height * Self.height(base, index, time)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// A bar's height as a fraction of the frame.
    ///
    /// Eased at both ends. An earlier version eased only the end, so every
    /// seventh second the row jolted out of rest — one bar lost a third of its
    /// height between two frames — and then settled gracefully, which is the
    /// flicker this whole view exists to avoid.
    ///
    /// Static and internal so a test can walk the cycle. The seam is the thing
    /// worth asserting: `height(base, i, 0)` has to equal `height(base, i,
    /// cycle)` for every bar, and it did not.
    static func height(_ base: CGFloat, _ index: Int, _ time: Double) -> CGFloat {
        guard time > 0, time < burst else { return base }
        let ramp = min(1, min(time, burst - time) / 0.5)
        // Two passes across five bars, each a beat behind the one to its left,
        // so the movement travels rather than pulsing as one block.
        let wave = sin(time / burst * 2 * 2 * .pi - Double(index) * 0.9)
        return base * (1 + 0.28 * ramp * CGFloat(wave))
    }
}
