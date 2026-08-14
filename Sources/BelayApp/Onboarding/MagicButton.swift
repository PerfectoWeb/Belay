import SwiftUI

/// The one button on the welcome screen that is asking to be pressed.
///
/// A first-launch screen has two buttons and only one of them is the answer.
/// The standard prominent button says that with colour alone, which on a dark
/// window next to a second button of nearly the same size is not much. This one
/// breathes and throws off sparks, which is a liberty taken exactly once, on a
/// screen shown exactly once.
///
/// The wand lives here rather than in the string, so every language gets it
/// without six translations having to agree about where an icon goes.
struct MagicButtonStyle: ButtonStyle {
    /// Somebody who has asked macOS for less motion gets the same button,
    /// standing still. It is still the coloured one, so it is still the answer.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Face(label: configuration.label, pressed: configuration.isPressed, animated: !reduceMotion)
    }
}

/// Split out because a `ButtonStyle` cannot hold the environment it needs to
/// decide whether to animate, and because the drawing wants somewhere to live.
private struct Face<Label: View>: View {
    let label: Label
    let pressed: Bool
    let animated: Bool

    /// 30 a second. The breathing is slow and the sparks are small; the
    /// difference against the display's own rate is not visible at this size,
    /// and this window is open for less than a minute.
    private static var tick: TimeInterval { 1.0 / 30 }

    /// One breath. Slow enough to read as alive rather than as a control
    /// flashing for attention: at two seconds it was a notification badge.
    private static var breath: Double { 3.2 }

    /// How far past the button the sparks are allowed to travel. The canvas is
    /// grown by this much in every direction, because a canvas clips to its own
    /// bounds and sparks that stop dead at the button's edge read as a texture
    /// rather than as something leaving.
    private static var halo: CGFloat { 26 }

    var body: some View {
        Group {
            if animated {
                TimelineView(.periodic(from: .now, by: Self.tick)) { timeline in
                    face(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                face(at: nil)
            }
        }
    }

    /// `nil` means standing still: the button at the top of its breath, with no
    /// sparks at all.
    private func face(at time: Double?) -> some View {
        let swell = time.map { (sin($0 * 2 * .pi / Self.breath) + 1) / 2 } ?? 1

        return HStack(spacing: 7) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
            label
        }
        // Sized to the button beside it, not to itself. A primary action that
        // is also physically larger than the secondary one reads as a different
        // kind of control, and the row stops looking like a row.
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(Color.accentColor)
                // Brightness rather than opacity: fading a button towards the
                // window behind it makes it look disabled on the way down.
                .brightness(0.03 + 0.05 * swell)
                .shadow(color: Color.accentColor.opacity(0.25 + 0.3 * swell), radius: 6 + 7 * swell)
        }
        .overlay {
            sparks(at: time)
                .padding(-Self.halo)
                .allowsHitTesting(false)
        }
        .scaleEffect(pressed ? 0.97 : 1)
        .opacity(pressed ? 0.85 : 1)
        .animation(.easeOut(duration: 0.12), value: pressed)
    }

    @ViewBuilder private func sparks(at time: Double?) -> some View {
        if let time {
            Canvas { context, size in
                let button = CGRect(
                    x: Self.halo, y: Self.halo,
                    width: size.width - Self.halo * 2, height: size.height - Self.halo * 2)
                for spec in Spark.all {
                    guard let spark = spec.at(time, over: button) else { continue }
                    context.fill(
                        Self.sparkle(at: spark.point, across: spark.width),
                        with: .color(.white.opacity(spark.alpha)))
                }
            }
        }
    }

    /// A four-pointed sparkle, the same shape as the mark's. Concave sides are
    /// the whole of it: four straight triangles read as a plus sign.
    private static func sparkle(at centre: CGPoint, across width: CGFloat) -> Path {
        let arm = width / 2
        // Concave sides, and how far in they pinch. Written out as four
        // quadrants rather than looped: a loop over the sign pairs was longer
        // than this and harder to check against the drawing.
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

/// One spark's whole life, as numbers rather than as state.
///
/// Six of them, on six periods that do not divide into each other, each lit for
/// under half of its own. The gaps are the point: a button with a constant
/// stream of particles coming off it is a loading indicator.
private struct Spark {
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
