import SwiftUI

/// The first thing anyone sees: what Belay does, shown rather than described.
///
/// An agent on the left, the Mac on the right, a rope between them. While the
/// agent works the rope is taut and the screen is lit; when it stops, the rope
/// goes slack and the Mac sleeps. Then it starts again.
///
/// Shown instead of a third paragraph because the product is a behaviour over
/// time, and a behaviour over time is the one thing prose is worst at. The whole
/// loop is nine seconds and repeats, so nobody has to catch the beginning.
struct OnboardingScene: View {
    /// One pass: work, then quiet, then sleep, then wake and round again.
    static let loop: Double = 9

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // The middle of the working half: the state the sentence under
                // it describes, held still.
                scene(at: 2)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                    scene(
                        at: timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: Self.loop))
                }
            }
        }
        .frame(height: 132)
        .accessibilityElement()
        .accessibilityLabel(
            "An agent works, Belay holds the Mac awake, and the Mac sleeps once the work stops")
    }

    /// How hard the agent is working: 1 through the working half, down to 0
    /// while it winds down, and back up again before the loop repeats.
    ///
    /// That last ramp is the whole reason the loop is nine seconds and not
    /// eight. Without it the wrap put the rope from a full belly to dead
    /// straight in one frame, on the first animation anybody ever sees.
    ///
    /// Static and internal so a test can walk the seam: this and `asleep` both
    /// have to arrive back where they started.
    static func working(at time: Double) -> Double {
        if time < 4.4 { return 1 }
        if time < 5.1 { return 1 - (time - 4.4) / 0.7 }
        if time < 8.2 { return 0 }
        return (time - 8.2) / 0.8
    }

    /// How far the Mac has gone to sleep. Lags the agent by the grace period,
    /// which is the part people do not expect and the part worth showing, and
    /// wakes again as the next turn of work starts.
    static func asleep(at time: Double) -> Double {
        if time < 5.6 { return 0 }
        if time < 6.5 { return (time - 5.6) / 0.9 }
        if time < 8.1 { return 1 }
        return max(0, 1 - (time - 8.1) / 0.7)
    }

    private func scene(at time: Double) -> some View {
        let live = Self.working(at: time)
        let sleep = Self.asleep(at: time)
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

    /// Minus the index, not plus it. With a positive term the later lines led
    /// the earlier ones and the block filled from the bottom up, which is a
    /// terminal scrolling the wrong way.
    ///
    /// Scaled by `activity` rather than gated on it, so the lines fade out with
    /// the same ramp as the rope instead of snapping to rest a frame after it
    /// starts moving.
    private func lineOpacity(_ index: Int) -> Double {
        let step = (time * 1.6 - Double(index) * 0.5).truncatingRemainder(dividingBy: 2.4)
        let lit = 0.1 + 0.9 * min(1, max(0, 1.35 - abs(step - 1.2)))
        return 0.25 + (lit - 0.25) * activity
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
