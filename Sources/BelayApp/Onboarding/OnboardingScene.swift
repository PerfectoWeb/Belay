import SwiftUI

/// The first thing anyone sees: what Belay does, shown rather than described.
///
/// An agent on the left, the Mac on the right, a rope between them. While the
/// agent works the rope is taut and the screen is lit; when it stops, the rope
/// goes slack and the Mac sleeps. Then it starts again.
///
/// Shown instead of a third paragraph because the product is a behaviour over
/// time, and a behaviour over time is the one thing prose is worst at. The whole
/// loop is eight seconds and repeats, so nobody has to catch the beginning.
struct OnboardingScene: View {
    /// One pass: work, then quiet, then sleep, then round again.
    private static let loop: Double = 8

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.loop)
            scene(at: time)
        }
        .frame(height: 132)
        .accessibilityElement()
        .accessibilityLabel(
            "An agent works, Belay holds the Mac awake, and the Mac sleeps once the work stops")
    }

    /// 0 to 1 across the working half, then 0 for the rest.
    private func working(at time: Double) -> Double {
        time < 4.4 ? 1 : max(0, 1 - (time - 4.4) / 0.7)
    }

    /// How far the Mac has gone to sleep. Lags the agent by the grace period,
    /// which is the part people do not expect and the part worth showing.
    private func asleep(at time: Double) -> Double {
        guard time > 5.6 else { return 0 }
        return min(1, (time - 5.6) / 0.9)
    }

    private func scene(at time: Double) -> some View {
        let live = working(at: time)
        let sleep = asleep(at: time)
        return HStack(spacing: 0) {
            AgentBlock(activity: live, time: time)
                .frame(width: 118, height: 96)
            Rope(slack: 1 - live)
                .stroke(
                    Color.accentColor.opacity(0.25 + 0.75 * live),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(height: 96)
                .frame(maxWidth: .infinity)
            MacBlock(asleep: sleep)
                .frame(width: 132, height: 96)
        }
        .padding(.horizontal, 26)
    }
}

/// The agent: a window with lines of output that keep arriving while it works.
private struct AgentBlock: View {
    var activity: Double
    var time: Double

    private static let widths: [CGFloat] = [0.8, 0.55, 0.9, 0.45]

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.quaternary)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(Self.widths.enumerated()), id: \.offset) { index, width in
                        Capsule()
                            .fill(index == 0 ? Color.accentColor.opacity(0.8) : Color.secondary)
                            .frame(width: 74 * width, height: 5)
                            // Each line fades in a beat after the one above, so
                            // the block reads as filling up rather than blinking.
                            .opacity(lineOpacity(index))
                    }
                }
                .padding(14)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1))
    }

    private func lineOpacity(_ index: Int) -> Double {
        guard activity > 0 else { return 0.25 }
        let step = (time * 1.6 + Double(index) * 0.5).truncatingRemainder(dividingBy: 2.4)
        return 0.35 + 0.65 * min(1, max(0, 1.6 - abs(step - 1.2)))
    }
}

/// The Mac: a lit screen with the mark on it while it is held, a moon once it
/// has been let go.
private struct MacBlock: View {
    var asleep: Double

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .overlay(
                    ZStack {
                        Image(nsImage: BelayGlyph.image(.alwaysOn, size: 26))
                            .renderingMode(.template)
                            .foregroundStyle(.tint)
                            .opacity(1 - asleep)
                        Image(systemName: "moon.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .opacity(asleep)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )
                .frame(height: 76)
            // The foot, so the block reads as a display rather than as a second
            // window: two rectangles side by side and nobody knows which is the
            // computer.
            Capsule()
                .fill(.quaternary)
                .frame(width: 46, height: 5)
                .padding(.top, 4)
        }
    }
}

/// The rope. Straight under load, and it bellies when the load comes off.
private struct Rope: Shape {
    var slack: Double

    var animatableData: Double {
        get { slack }
        set { slack = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = CGPoint(x: rect.minX, y: rect.midY)
        let right = CGPoint(x: rect.maxX, y: rect.midY)
        path.move(to: left)
        // A quadratic is enough: a real catenary is a nicer curve and nobody
        // can tell the difference across ninety points.
        path.addQuadCurve(
            to: right,
            control: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.42 * slack))
        return path
    }
}
