import SwiftUI

/// Sparks leaving the top of whatever it is put over.
///
/// Lifted out of `MagicButtonStyle`, which had it inline, because a second
/// control now wants it: the green **Update Now** button in Settings, on the one
/// occasion it appears. Two copies of a drawing drift, and this one is made of
/// six hand-tuned constants that would drift silently.
///
/// It draws nothing but white sparkles and hit-tests nothing, so it goes over a
/// button as an overlay without changing the button's size, shape or colour.
/// `halo` is how far past the edges a spark may travel: a `Canvas` clips to its
/// own bounds, so the canvas is grown by that much and the padding pulled back
/// out again by the caller.
struct SparkHalo: View {
    /// Nil stands still and draws nothing, which is what Reduce Motion gets.
    let time: Double?
    var halo: CGFloat = 26

    var body: some View {
        if let time {
            Canvas { context, size in
                let button = CGRect(
                    x: halo, y: halo,
                    width: size.width - halo * 2, height: size.height - halo * 2)
                for spec in Spark.all {
                    guard let spark = spec.at(time, over: button) else { continue }
                    context.fill(
                        Self.sparkle(at: spark.point, across: spark.width),
                        with: .color(.white.opacity(spark.alpha)))
                }
            }
        }
    }

    /// A four-armed sparkle with concave sides, which is Belay's mark in
    /// miniature. Written out as four quadrants rather than looped: a loop over
    /// the sign pairs was longer than this and harder to check against the
    /// drawing.
    static func sparkle(at centre: CGPoint, across width: CGFloat) -> Path {
        let arm = width / 2
        let waist = arm * 0.24
        var path = Path()
        path.move(to: CGPoint(x: centre.x, y: centre.y - arm))
        path.addQuadCurve(
            to: CGPoint(x: centre.x + arm, y: centre.y),
            control: CGPoint(x: centre.x + waist, y: centre.y - waist))
        path.addQuadCurve(
            to: CGPoint(x: centre.x, y: centre.y + arm),
            control: CGPoint(x: centre.x + waist, y: centre.y + waist))
        path.addQuadCurve(
            to: CGPoint(x: centre.x - arm, y: centre.y),
            control: CGPoint(x: centre.x - waist, y: centre.y + waist))
        path.addQuadCurve(
            to: CGPoint(x: centre.x, y: centre.y - arm),
            control: CGPoint(x: centre.x - waist, y: centre.y - waist))
        path.closeSubpath()
        return path
    }
}

/// One spark: where it leaves from, where it goes, and when.
struct Spark {
    /// Where along the button's width it leaves from.
    var across: CGFloat
    /// How far sideways and how far up it travels before it goes out.
    var drift: CGFloat
    var rise: CGFloat
    var width: CGFloat
    var period: Double
    var phase: Double

    static let all: [Spark] = [
        Spark(across: 0.16, drift: -6, rise: 22, width: 5.0, period: 2.3, phase: 0.00),
        Spark(across: 0.33, drift: 4, rise: 17, width: 3.6, period: 2.9, phase: 0.42),
        Spark(across: 0.50, drift: -3, rise: 25, width: 5.6, period: 2.6, phase: 0.77),
        Spark(across: 0.67, drift: 7, rise: 19, width: 3.2, period: 3.3, phase: 0.21),
        Spark(across: 0.84, drift: 3, rise: 23, width: 4.4, period: 2.1, phase: 0.58),
        Spark(across: 0.96, drift: 9, rise: 15, width: 3.0, period: 3.7, phase: 0.09)
    ]

    /// A quarter of the period, so five sixths of the time there is nothing
    /// where this spark will be.
    private static let life = 0.42

    /// Where this spark is, how big and how bright, or nothing at all because
    /// most of the time it is between lives.
    struct Lit {
        var point: CGPoint
        var width: CGFloat
        var alpha: Double
    }

    func at(_ now: Double, over button: CGRect) -> Lit? {
        let position = now / period + phase
        let progress = (position - position.rounded(.down)) / Self.life
        guard progress < 1 else { return nil }
        // Out at both ends: a spark that appears at full brightness reads as a
        // pixel fault, and one that vanishes at full brightness reads as a
        // dropped frame.
        let burn = sin(progress * .pi)
        // Eased upward, so it leaves quickly and drifts to a stop.
        let travel = 1 - pow(1 - progress, 2)
        return Lit(
            point: CGPoint(
                x: button.minX + button.width * across + drift * travel,
                y: button.minY + 3 - rise * travel),
            width: width * (0.55 + 0.45 * burn),
            alpha: pow(burn, 1.3) * 0.9)
    }
}
