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
    /// 1 while the mark is lit, 0 while it is not. It is a colour change, not a
    /// fade: an icon going transparent reads as the app quitting, an icon going
    /// grey reads as the thing it does being switched off. Between the two it
    /// mixes, so the blink and the return are the same gesture at two speeds.
    var blink: Double
    var time: Double

    /// The logos the app already ships, in the order they take the ring.
    private static let agents = ["claude", "codex", "gemini", "cline"]
    /// Built once, not every timeline frame: the scene redraws at 30 fps, and
    /// rebuilding these `NSImage`s each frame is the same per-frame allocation
    /// `AboutAnimation` had to cache away as an 8.3 % CPU cost.
    @MainActor private static let marks: [String: NSImage] = Dictionary(
        uniqueKeysWithValues: agents.map { ($0, ProviderMark.image(preset: $0, size: 13)) })
    @MainActor private static let glyph: NSImage = BelayGlyph.image(.alwaysOn, size: 26)

    private static func mark(for name: String) -> NSImage {
        marks[name] ?? ProviderMark.image(preset: name, size: 13)
    }
    /// Whole turns each agent makes while it is on the ring. Whole, because a
    /// fraction of a turn is the seam: the agent pops at one angle and comes
    /// back at another, and the loop visibly cuts. Different for each, and none
    /// dividing into the next, so the four never fall into step.
    private static let turns: [Double] = [1, 2, 3, 4]
    /// The disc every agent rides on.
    private static let disc = Color(red: 0.169, green: 0.216, blue: 0.325)
    /// The tile, holding and let go.
    private static let lit = [
        Color(red: 0.29, green: 0.56, blue: 1), Color(red: 0.13, green: 0.42, blue: 1)
    ]
    private static let off = [
        Color(red: 0.40, green: 0.43, blue: 0.49), Color(red: 0.28, green: 0.31, blue: 0.36)
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            // A circle, not an ellipse. Seen head on the mark is the sun and
            // the ring is a true orbit around it; tilted, it read as a plate.
            let radius = min(size.width, size.height) / 2 - 12
            ZStack {
                if half == .behind {
                    ring(radius: radius, centre: centre)
                }
                ForEach(Array(Self.agents.enumerated()), id: \.offset) { index, name in
                    if Self.isBehind(index, at: time) == (half == .behind) {
                        chip(name, index: index, centre: centre, radius: radius)
                            // The handover between the two halves must not be
                            // animated. Left to itself SwiftUI reads it as one
                            // view leaving and another arriving, and the chip
                            // jumps as it crosses the edge of the screen.
                            .transaction { $0.animation = nil }
                    }
                }
                if half == .inFront {
                    tile.position(centre)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Whether an agent is on the side of the ring that crosses the machine.
    /// The laptop sits to the left of the mark, so that is the left half.
    static func isBehind(_ index: Int, at time: Double) -> Bool {
        cos(angle(index, at: time)) < 0
    }

    /// Where an agent is. The clock only runs while it is up: frozen from the
    /// moment it pops to the moment it returns, so it comes back exactly where
    /// it left. Combined with a whole number of turns per pass, the ring closes
    /// on itself and there is nothing to see at the wrap.
    private static func angle(_ index: Int, at time: Double) -> Double {
        let alive = OnboardingScene.aliveTime(index, at: time)
        let span = OnboardingScene.aliveSpan(index)
        return alive / span * turns[index] * 2 * .pi + Double(index) * (2 * .pi / 4)
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
            .frame(width: radius * 2, height: radius * 2)
            .position(centre)
    }

    /// The app icon, on its own rounded tile, the way it appears in the Dock.
    private var tile: some View {
        // Grey underneath and blue over it, rather than one fill chosen by a
        // threshold. A threshold could only snap, and the mark has to be able
        // to come back up with the machine over a third of a second.
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(colors: Self.off, startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    LinearGradient(colors: Self.lit, startPoint: .top, endPoint: .bottom)
                )
                .opacity(blink)
        }
        .frame(width: 42, height: 42)
        .overlay {
            Image(nsImage: Self.glyph)
                .renderingMode(.template)
                .foregroundStyle(.white)
        }
        // The halo is what the machine takes with it. The tile itself stays
        // solid: an app icon that fades out reads as the app quitting.
        .shadow(color: Color.accentColor.opacity(0.55 * glow), radius: 10 * glow)
    }

    /// One agent: a slate disc with its logo in white, riding the ellipse. The
    /// pop is a quick swell and out, which is what a bubble does.
    private func chip(_ name: String, index: Int, centre: CGPoint, radius: CGFloat) -> some View {
        let gone = popped[min(index, popped.count - 1)]
        let landed = arrived[min(index, arrived.count - 1)]
        let angle = Self.angle(index, at: time)
        let point = CGPoint(
            x: centre.x + cos(angle) * radius,
            y: centre.y + sin(angle) * radius)
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
                    Image(nsImage: Self.mark(for: name))
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
