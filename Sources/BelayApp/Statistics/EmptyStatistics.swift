import SwiftUI

/// What Statistics shows before there is anything to show.
///
/// It used to be a left-aligned heading over a four-line paragraph explaining
/// what would eventually appear. Nobody reads a paragraph in an empty state:
/// they look at it, understand there is nothing here, and leave. So it is now
/// the shape of the thing that is missing, centred, with one line under it.
///
/// The bars breathe rather than sit still. A static grey glyph reads as a
/// screenshot of a broken pane; the same glyph moving slowly reads as a thing
/// that is waiting.
struct EmptyStatistics: View {
    /// Relative heights, so the shape is a plausible chart rather than a ramp.
    private static let bars: [CGFloat] = [0.42, 0.68, 0.5, 0.85, 0.6]

    var body: some View {
        VStack(spacing: 14) {
            chart
                .frame(width: 96, height: 56)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text("Nothing to show yet")
                    .font(.system(size: 15, weight: .semibold))
                Text("Your first agent run fills this in.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Nothing here ever leaves this Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 200)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        // Slow on purpose. Anything quick enough to notice is asking to be
        // watched, and this is the corner of the app with the least to say.
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(Self.bars.enumerated()), id: \.offset) { index, base in
                        // A third of a cycle between neighbours, so the movement
                        // travels along the row instead of pulsing as one block.
                        let wave = sin(time * 0.9 + Double(index) * 0.7)
                        let height = base * (0.82 + 0.18 * (0.5 + 0.5 * wave))
                        Capsule()
                            .fill(.quaternary)
                            .frame(height: max(6, proxy.size.height * height))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}
