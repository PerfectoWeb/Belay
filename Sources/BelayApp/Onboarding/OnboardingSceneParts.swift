import SwiftUI

/// The things the welcome scene is drawn out of.
///
/// Split from `OnboardingScene` because that file was the whole picture and had
/// grown past what one file is allowed to be here. The division is the useful
/// one anyway: `OnboardingScene` owns the story — the two ramps, where every
/// piece sits, and what the three states look like — and this owns the pieces,
/// none of which knows what time it is.
///
/// Nested inside the scene rather than left at file scope. `Laptop` is a name an
/// app of this size will want again, and a second one in another file would
/// collide with this on a day nobody was thinking about onboarding.
extension OnboardingScene {
    /// The Mac: Apple's own MacBook Pro artwork, with our screen behind it.
    ///
    /// This was a drawn machine for a long while and it never quite became one.
    /// The proportion of the lid, the radius of its corners and the depth of the
    /// base are the whole of what makes a MacBook recognisable as a MacBook, and
    /// none of the three survives being approximated by hand at this size.
    ///
    /// Apple publishes the bezel for exactly this, and the display is cut out of
    /// it, so our screen needs no mask: it is laid down first and the artwork
    /// goes over the top. Two PNGs, fifteen kilobytes together, decoded once by
    /// the asset catalogue. The notch comes with it, as an opaque tab hanging
    /// into the cut-out, and so do the display's rounded corners.
    struct Laptop: View {
        /// 1 while the Mac is being held awake, 0 once it is asleep.
        var lit: Double
        /// 1 while the agent is producing output.
        var working: Double
        var time: Double

        /// The artwork's own proportion, and the caller has to honour it. The
        /// display is placed as fractions of the frame, so a frame of the wrong
        /// shape slides our screen out from behind the bezel.
        static let aspect: CGFloat = 4221.0 / 2578.0
        /// How wide the machine is drawn. Kept here beside the proportion so
        /// the two are never changed apart.
        static let width: CGFloat = 150

        /// Where the display is cut out of the artwork, as fractions of it.
        ///
        /// Measured off its alpha channel, and measured away from the middle.
        /// The first reading was taken down the centre column, which runs
        /// straight through the notch: it put the top of the screen sixty-four
        /// artwork pixels too low and left a torn strip of window showing
        /// between the bezel and our screen.
        private struct Hole {
            var left: CGFloat
            var top: CGFloat
            var width: CGFloat
            var height: CGFloat
        }

        private static let hole = Hole(
            left: 0.0905, top: 0.0217, width: 0.8188, height: 0.8666)
        /// Six now, not four. The screen is a terminal with an agent talking
        /// into it, and four lines read as a form with four fields.
        private static let widths: [CGFloat] = [0.8, 0.55, 0.9, 0.45, 0.7, 0.35]
        private static let glass = Color(red: 0.07, green: 0.09, blue: 0.14)

        var body: some View {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    display
                        .frame(
                            width: size.width * Self.hole.width,
                            height: size.height * Self.hole.height
                        )
                        .offset(x: size.width * Self.hole.left, y: size.height * Self.hole.top)
                    Image("macbook-bezel")
                        .resizable()
                        .frame(width: size.width, height: size.height)
                }
            }
            .accessibilityHidden(true)
        }

        /// What is on the screen: the work, or a moon once it has stopped.
        private var display: some View {
            ZStack {
                Rectangle().fill(Self.glass)
                Rectangle().fill(Color.accentColor.opacity(0.16 * lit))
                lines
                    .padding(.horizontal, 12)
                    .padding(.top, 15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .opacity(lit)
                Image(systemName: "moon.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .opacity(1 - lit)
            }
        }

        /// The work, as lines arriving one after another, with something still
        /// thinking at the end of the last of them.
        private var lines: some View {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(Self.widths.enumerated()), id: \.offset) { index, width in
                    HStack(spacing: 5) {
                        Capsule()
                            .fill(index == 0 ? Color.accentColor : Color.white.opacity(0.75))
                            .frame(width: 68 * width, height: 4)
                            .opacity(lineOpacity(index))
                        if index == Self.widths.count - 1 {
                            // Steady while the line it sits on comes and goes.
                            // The lines are output arriving; this is the thing
                            // producing them, and it does not flicker.
                            Thinking(time: time)
                                .frame(width: 11, height: 11)
                                .opacity(working)
                        }
                    }
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
            Spark(dx: -2, dy: -19, size: 11, phase: 0),
            Spark(dx: 7, dy: -7, size: 9, phase: 0.9),
            Spark(dx: -3, dy: 5, size: 8, phase: 1.7)
        ]

        var body: some View {
            ZStack {
                ForEach(Array(Self.sparks.enumerated()), id: \.offset) { index, spark in
                    Image(systemName: "bolt.fill")
                        .font(.system(size: spark.size, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: spark.dx, y: spark.dy)
                        .opacity(flicker(spark.phase) * charge * (1 - sleeping))

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
                        .opacity(sleeping * fade(index))
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

        /// In at the bottom, out at the top, and nought at both ends. Any
        /// floor under this and the letter is still visible at the moment it
        /// jumps back down to start again, which is the one frame that must
        /// not be seen.
        private func fade(_ index: Int) -> Double {
            sin(drift(index) * .pi)
        }
    }
}
