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
    /// The Mac: a MacBook, opaque and with some thickness to it.
    ///
    /// Recognisably the machine rather than a grey rectangle: a bezel with a
    /// notch cut into it, a lid that sits on a base rather than floating, and a
    /// front lip so the base has a depth. No logo, because that is somebody
    /// else's mark to put on things.
    struct Laptop: View {
        /// 1 while the Mac is being held awake, 0 once it is asleep.
        var lit: Double
        /// 1 while the agent is producing output.
        var working: Double
        var time: Double

        private static let widths: [CGFloat] = [0.8, 0.55, 0.9, 0.45]
        /// The aluminium the whole machine is cut from.
        private static let shell = Color(red: 0.30, green: 0.33, blue: 0.40)
        private static let shellDark = Color(red: 0.20, green: 0.22, blue: 0.28)
        private static let glass = Color(red: 0.07, green: 0.09, blue: 0.14)

        var body: some View {
            VStack(spacing: 0) {
                lid
                base
            }
        }

        /// The lid: aluminium, a black bezel, and the screen inside it.
        private var lid: some View {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Self.shell)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Self.glass)
                        .overlay { display }
                        .overlay(alignment: .top) { notch }
                        .padding(3)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }

        /// The camera housing every MacBook has had since 2021. Three points
        /// wide is enough at this size; any more and it reads as a bite.
        private var notch: some View {
            UnevenRoundedRectangle(
                bottomLeadingRadius: 3, bottomTrailingRadius: 3, style: .continuous
            )
            .fill(Self.glass)
            .frame(width: 26, height: 5)
        }

        /// What is on the screen: the work, or a moon once it has stopped.
        private var display: some View {
            ZStack {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.14 * lit))
                lines
                    .padding(.horizontal, 10)
                    .padding(.top, 13)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(lit)
                Image(systemName: "moon.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .opacity(1 - lit)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }

        /// The base, seen at a slight angle, with a lip along the front so it
        /// has a thickness. Flat, it read as a sheet of paper.
        private var base: some View {
            VStack(spacing: 0) {
                Deck()
                    .fill(
                        LinearGradient(
                            colors: [Self.shell, Self.shellDark],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 5)
                Deck()
                    .fill(Self.shellDark)
                    .overlay(Deck().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    .frame(height: 4)
            }
        }

        /// The work, as lines arriving one after another.
        private var lines: some View {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(Self.widths.enumerated()), id: \.offset) { index, width in
                    Capsule()
                        .fill(index == 0 ? Color.accentColor : Color.white.opacity(0.75))
                        .frame(width: 62 * width, height: 4)
                        .opacity(lineOpacity(index))
                }
            }
        }

        /// Minus the index, not plus it. With a positive term the later lines
        /// led the earlier ones and the screen filled from the bottom up, which
        /// is a terminal scrolling the wrong way.
        private func lineOpacity(_ index: Int) -> Double {
            let step = (time * 1.6 - Double(index) * 0.5).truncatingRemainder(dividingBy: 2.4)
            let shown = 0.1 + 0.9 * min(1, max(0, 1.35 - abs(step - 1.2)))
            return 0.2 + (shown - 0.2) * working
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

    /// The charge at the machine while it is held, and the sleep once it is not.
    ///
    /// One turns into the other rather than one leaving and the other arriving:
    /// the bolts shrink away on the spot as the letters grow out of it, so the
    /// eye reads a single thing changing its mind. Cartoons have drawn sleep as
    /// three rising Zs for a century and there is no reason to invent a
    /// second way.
    struct ChargeBolts: View {
        /// 1 while Belay is holding the Mac awake.
        var charge: Double
        /// 1 once the Mac has gone to sleep.
        var sleeping: Double
        var time: Double

        private struct Spark {
            var dx: CGFloat
            var dy: CGFloat
            var size: CGFloat
            var phase: Double
        }

        private static let sparks = [
            Spark(dx: 2, dy: -13, size: 11, phase: 0),
            Spark(dx: 11, dy: -1, size: 9, phase: 0.9),
            Spark(dx: 1, dy: 11, size: 8, phase: 1.7)
        ]

        var body: some View {
            ZStack {
                ForEach(Array(Self.sparks.enumerated()), id: \.offset) { index, spark in
                    Image(systemName: "bolt.fill")
                        .font(.system(size: spark.size, weight: .semibold))
                        .foregroundStyle(.tint)
                        .offset(x: spark.dx, y: spark.dy)
                        .opacity(flicker(spark.phase) * charge)
                        .scaleEffect(1 - sleeping)

                    // The same three places, becoming letters. Each drifts up
                    // and fades on its own beat, so they rise in a line rather
                    // than as a block.
                    // Verbatim: this is a drawing of a snore, not a word
                    // anybody should be asked to translate.
                    Text(verbatim: "z")
                        .font(.system(size: spark.size + 3, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .offset(
                            x: spark.dx + CGFloat(index) * 3,
                            y: spark.dy - CGFloat(drift(index)) * 9
                        )
                        .opacity(sleeping * (0.35 + 0.65 * fade(index)))
                        .scaleEffect(sleeping * (0.8 + 0.2 * Double(index)))
                }
            }
            .accessibilityHidden(true)
        }

        /// Each on its own phase, so the three never blink as one. Never fully
        /// out while the power is on: a bolt that reaches zero reads as a fault
        /// rather than as current.
        private func flicker(_ phase: Double) -> Double {
            0.45 + 0.55 * (0.5 + 0.5 * sin(time * 3.1 + phase * 6.283))
        }

        /// How far up this letter has floated on its own cycle.
        private func drift(_ index: Int) -> Double {
            let step = (time * 0.55 + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
            return step
        }

        /// In at the bottom, out at the top.
        private func fade(_ index: Int) -> Double {
            sin(drift(index) * .pi)
        }
    }
}
