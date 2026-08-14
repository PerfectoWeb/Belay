import SwiftUI

/// The things the welcome scene is drawn out of.
///
/// Split from `OnboardingScene` because that file was the whole picture and had
/// grown past what one file is allowed to be here. The division is the useful
/// one anyway: `OnboardingScene` owns the story — the two ramps, where every
/// piece sits, and what the three states look like — and this owns the pieces,
/// none of which knows what time it is.
///
/// Nested inside the scene rather than left at file scope. `Plug`, `Socket` and
/// `Deck` are names an app of this size will want again, and a second `Rope` in
/// another file would collide with this one on a day nobody was thinking about
/// onboarding.
extension OnboardingScene {
    /// The Mac: a screen on a deck. Lines of output arrive on it while the agent
    /// works, and it goes dark under a moon once Belay lets go.
    struct Laptop: View {
        /// 1 while the Mac is being held awake, 0 once it is asleep.
        var lit: Double
        /// 1 while the agent is producing output.
        var working: Double
        var time: Double

        private static let widths: [CGFloat] = [0.8, 0.55, 0.9, 0.45]

        var body: some View {
            VStack(spacing: 0) {
                screen
                Deck()
                    .fill(.quaternary)
                    .overlay(Deck().stroke(.separator, lineWidth: 1))
                    .frame(
                        width: OnboardingScene.Place.deck.width,
                        height: OnboardingScene.Place.deck.height)
            }
        }

        private var screen: some View {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.quaternary)
                // A screen that is on is not the same grey as a screen that is off.
                // Swapping the picture on it for a moon changes the symbol and
                // leaves the panel behind it exactly as bright, so the one thing
                // the eye reads at this size — how lit the rectangle is — says
                // nothing at all.
                .overlay(wash(Color.accentColor.opacity(0.16 * lit)))
                .overlay(wash(Color.black.opacity(0.34 * (1 - lit))))
                .overlay(alignment: .topLeading) {
                    lines.padding(13).opacity(lit)
                }
                .overlay {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                        .opacity(1 - lit)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                        // The outline stays, dimmer. Without it a sleeping Mac
                        // loses its edge against the night sky and the scene ends
                        // up with nothing holding its left-hand side.
                        .opacity(1 - 0.45 * (1 - lit))
                )
                .frame(
                    width: OnboardingScene.Place.screen.width,
                    height: OnboardingScene.Place.screen.height)
        }

        private var lines: some View {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(Self.widths.enumerated()), id: \.offset) { index, width in
                    Capsule()
                        .fill(index == 0 ? Color.accentColor.opacity(0.8) : Color.secondary)
                        .frame(width: 74 * width, height: 5)
                        // Each line fades in a beat after the one above, so the
                        // screen reads as filling up rather than blinking.
                        .opacity(lineOpacity(index))
                }
            }
        }

        /// A wash the exact shape of the screen. Named because it is applied twice
        /// and the shape has to be the same both times: a rectangle a corner radius
        /// out of step shows as a bright hairline along the rounding.
        private func wash(_ colour: Color) -> some View {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(colour)
        }

        /// Minus the index, not plus it. With a positive term the later lines led
        /// the earlier ones and the screen filled from the bottom up, which is a
        /// terminal scrolling the wrong way.
        ///
        /// Scaled by `working` rather than gated on it, so the lines settle with
        /// the same ramp as the rope instead of snapping to rest a frame after it
        /// starts moving.
        private func lineOpacity(_ index: Int) -> Double {
            let step = (time * 1.6 - Double(index) * 0.5).truncatingRemainder(dividingBy: 2.4)
            let lit = 0.1 + 0.9 * min(1, max(0, 1.35 - abs(step - 1.2)))
            return 0.25 + (lit - 0.25) * working
        }
    }

    /// The keyboard half, wider at the front than at the back. Two rectangles one
    /// above the other read as a screen sitting on a box; the taper is the whole of
    /// what makes it read as a laptop seen from slightly above.
    struct Deck: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            let inset = rect.width * 0.085
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    /// The socket, which belongs to the Mac and never changes. What changes is
    /// whether anything is in it.
    struct Socket: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.quaternary)
                .overlay(alignment: .top) {
                    HStack(spacing: 6) {
                        hole
                        hole
                    }
                    .padding(.top, 5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                )
                .frame(width: 26, height: 20)
        }

        private var hole: some View {
            Capsule().fill(.black.opacity(0.5)).frame(width: 3, height: 7)
        }
    }

    /// Belay's end of the rope. Accent-coloured, because it is the one object in
    /// the picture that belongs to this app: the laptop and the socket are the
    /// user's, and the plug is the thing Belay puts in and takes out.
    struct Plug: View {
        var body: some View {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 19, height: 13)
                HStack(spacing: 6) {
                    prong
                    prong
                }
            }
        }

        private var prong: some View {
            Capsule().fill(Color.accentColor).frame(width: 3, height: 6)
        }
    }

    /// Power arriving, drawn as it is drawn everywhere: three bolts, of three
    /// sizes, off to one side. They are the only thing in the picture that says the
    /// holding is active rather than merely connected, so they go out the moment
    /// Belay lets go and come back when it takes hold again.
    struct Bolts: View {
        var intensity: Double
        var time: Double

        /// One bolt: where it sits beside the socket, how big it is drawn, and
        /// where it is in its own flicker. Named fields rather than a tuple of
        /// four, which nothing can read at the point it is written down.
        private struct Spark {
            var dx: CGFloat
            var dy: CGFloat
            var size: CGFloat
            var phase: Double
        }

        private static let bolts = [
            Spark(dx: 2, dy: -13, size: 10, phase: 0),
            Spark(dx: 10, dy: -2, size: 8, phase: 0.9),
            Spark(dx: 1, dy: 10, size: 7, phase: 1.7)
        ]

        var body: some View {
            ZStack {
                ForEach(Array(Self.bolts.enumerated()), id: \.offset) { _, bolt in
                    Image(systemName: "bolt.fill")
                        .font(.system(size: bolt.size, weight: .semibold))
                        .foregroundStyle(.tint)
                        .offset(x: bolt.dx, y: bolt.dy)
                        .opacity(flicker(bolt.phase) * intensity)
                }
            }
        }

        /// Each on its own phase, so the three never blink as one. Never fully out
        /// while the power is on: a bolt that reaches zero reads as a fault rather
        /// than as current.
        private func flicker(_ phase: Double) -> Double {
            0.45 + 0.55 * (0.5 + 0.5 * sin(time * 3.1 + phase * 6.283))
        }
    }

    /// The rope. Straight under load, and it bellies when the load comes off.
    struct Rope: Shape {
        var from: CGPoint
        var to: CGPoint
        var sag: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: from)
            // A quadratic is enough: a real catenary is a nicer curve and nobody
            // can tell the difference across ninety points.
            path.addQuadCurve(
                to: to,
                control: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + sag))
            return path
        }
    }
}
