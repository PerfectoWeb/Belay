import SwiftUI

/// The one part of the welcome scene that is a character rather than a thing.
///
/// Its own file because `OnboardingSceneParts.swift` had reached the length this
/// project allows, and of everything in there this is the piece that owes the
/// least to the rest: the machine, its screen and the charge are one drawing
/// with shared measurements, and this is a mark that happens to sit at the end
/// of a line.
extension OnboardingScene {
    /// The mark at the end of the last line: an agent still thinking.
    ///
    /// Three arms crossing at a common centre, breathing together and turning
    /// slowly, which is an asterisk and not a spinner. Six of them was the
    /// first try: twelve rays at eleven points across is a loading gear.
    /// Every terminal agent draws some version of this and they are all the same
    /// idea — the answer has not arrived, but something is happening. Drawn
    /// rather than typed, because an asterisk in a font is a glyph that cannot
    /// move its own arms.
    ///
    /// Together, and that is the whole of the tuning. Each arm had its own phase
    /// at first, which is livelier and is wrong: at any given moment the six
    /// were different lengths, so the star was never round. It only had to be
    /// symmetrical to look drawn rather than dented.
    struct Thinking: View {
        var time: Double

        private static let spokes = 3

        var body: some View {
            Canvas { context, size in
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let longest = min(size.width, size.height) / 2
                // Never all the way in and never all the way out: an arm that
                // reaches zero reads as a dropped frame.
                let breath = 0.5 + 0.5 * (0.5 + 0.5 * sin(time * 3.4))
                let reach = longest * breath
                for spoke in 0..<Self.spokes {
                    let turn = Double(spoke) * (.pi / Double(Self.spokes)) + time * 0.55
                    var arm = Path()
                    arm.move(
                        to: CGPoint(
                            x: centre.x - cos(turn) * reach, y: centre.y - sin(turn) * reach))
                    arm.addLine(
                        to: CGPoint(
                            x: centre.x + cos(turn) * reach, y: centre.y + sin(turn) * reach))
                    context.stroke(
                        arm, with: .color(.white.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
            .allowsHitTesting(false)
        }
    }
}
