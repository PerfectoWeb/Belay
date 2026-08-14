import SwiftUI

/// Belay's mark, and the agents going round it.
///
/// The tile is the app icon as the app draws it everywhere else. The ring is the
/// work: four agents on one orbit, each at its own rate, so the group never
/// falls into step and reads as four things rather than one turning picture.
///
/// Drawn in two halves. The scene puts `.behind` under the laptop and
/// `.inFront` over it, so an agent crossing the back of the orbit goes behind
/// the machine and comes out the other side. An orbit whose far half passes in
/// front of the thing it circles is a flat ring with icons stuck to it.
///
/// They pop one at a time when the work ends. A bubble is the right idea for a
/// session: it was there, it is not, and nothing is left behind.
struct AgentOrbit: View {
    enum Half {
        case behind
        case inFront
    }

    var half: Half
    /// One entry per agent, nought while it runs and one once popped.
    var popped: [Double]
    /// One entry per agent, nought before it lands and one once it has.
    var arrived: [Double]
    /// The halo behind the mark. Goes out with the machine.
    var glow: Double
    /// The mark's own brightness. Only the two beats as Belay lets go.
    var blink: Double
    var time: Double

    /// The logos the app already ships, in the order they take the ring.
    private static let agents = ["claude", "codex", "gemini", "cline"]
    /// Each one's own rate, in turns per second, and none divides into another.
    private static let rates: [Double] = [0.085, -0.062, 0.11, -0.048]
    /// The disc every agent rides on.
    private static let disc = Color(red: 0.169, green: 0.216, blue: 0.325)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 13
            ZStack {
                if half == .behind {
                    ring(radius: radius, centre: centre)
                }
                ForEach(Array(Self.agents.enumerated()), id: \.offset) { index, name in
                    if Self.isBehind(index, at: time) == (half == .behind) {
                        chip(name, index: index, centre: centre, radius: radius)
                    }
                }
                if half == .inFront {
                    tile.position(centre)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Whether an agent is on the far side of the ring at this moment.
    static func isBehind(_ index: Int, at time: Double) -> Bool {
        sin(angle(index, at: time)) < 0
    }

    private static func angle(_ index: Int, at time: Double) -> Double {
        time * rates[index] * 2 * .pi + Double(index) * (2 * .pi / 4)
    }

    /// The track. It goes with the agents: left behind after the last one pops,
    /// it reads as a lane with nothing in it.
    private func ring(radius: CGFloat, centre: CGPoint) -> some View {
        let left = 1 - popped.reduce(0, +) / Double(popped.count)
        return Ellipse()
            .strokeBorder(
                Color.white.opacity(0.16 * left),
                style: StrokeStyle(lineWidth: 1, dash: [2, 4])
            )
            .frame(width: radius * 2, height: radius * 2 * 0.62)
            .position(centre)
    }

    /// The app icon, on its own rounded tile, the way it appears in the Dock.
    private var tile: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.29, green: 0.56, blue: 1),
                        Color(red: 0.13, green: 0.42, blue: 1)
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 42, height: 42)
            .overlay {
                Image(nsImage: BelayGlyph.image(.alwaysOn, size: 26))
                    .renderingMode(.template)
                    .foregroundStyle(.white)
            }
            // The halo is what the machine takes with it. The tile itself stays
            // solid: an app icon that fades out reads as the app quitting.
            .shadow(color: Color.accentColor.opacity(0.55 * glow), radius: 10 * glow)
            .opacity(blink)
    }

    /// One agent: a slate disc with its logo in white, riding the ellipse. The
    /// pop is a quick swell and out, which is what a bubble does.
    private func chip(_ name: String, index: Int, centre: CGPoint, radius: CGFloat) -> some View {
        let gone = popped[min(index, popped.count - 1)]
        let landed = arrived[min(index, arrived.count - 1)]
        let angle = Self.angle(index, at: time)
        let point = CGPoint(
            x: centre.x + cos(angle) * radius,
            y: centre.y + sin(angle) * radius * 0.62)
        // Swells before it goes, the way a bubble does.
        let swell = 1 + 0.55 * sin(min(1, gone * 1.6) * .pi)
        return ZStack {
            Circle()
                .fill(Self.disc)
                .frame(width: 21, height: 21)
                .overlay {
                    // Drawn as a template so every agent arrives the same weight
                    // of white. Their own artwork is six different colours, and
                    // at this size that reads as confetti rather than as a set.
                    Image(nsImage: ProviderMark.image(preset: name, size: 13))
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                }
                .scaleEffect(gone >= 1 ? 0.001 : swell * Self.landing(landed))
                .opacity((1 - gone) * min(1, landed * 3))

            Burst(progress: gone)
                .frame(width: 44, height: 44)
        }
        .position(point)
    }

    /// A back-out: overshoots a little and settles. An agent that scales
    /// straight to one arrives like a switch being thrown.
    private static func landing(_ progress: Double) -> Double {
        guard progress < 1 else { return 1 }
        let back = progress - 1
        return 1 + 2.2 * back * back * back + 1.4 * back * back
    }
}

/// What is left of an agent for the moment after it pops: a few short strokes
/// going out from where it was. A bubble that simply vanishes reads as a
/// dropped frame; the same bubble that throws something reads as bursting.
private struct Burst: View {
    var progress: Double

    var body: some View {
        Canvas { context, size in
            guard progress > 0, progress < 1 else { return }
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            // Out fast, then slowing, and gone before it has travelled far.
            let travel = 1 - pow(1 - progress, 2)
            let fade = 1 - progress
            for spoke in 0..<7 {
                let angle = Double(spoke) * (2 * .pi / 7) + 0.4
                let near = 9 + 9 * travel
                let far = near + 5 * (1 - travel * 0.5)
                var stick = Path()
                stick.move(
                    to: CGPoint(
                        x: centre.x + cos(angle) * near,
                        y: centre.y + sin(angle) * near))
                stick.addLine(
                    to: CGPoint(
                        x: centre.x + cos(angle) * far,
                        y: centre.y + sin(angle) * far))
                context.stroke(
                    stick, with: .color(.white.opacity(0.85 * fade)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}
