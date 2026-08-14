import SwiftUI

/// The person, on a trampoline, having a better time than their Mac.
///
/// Drawn here rather than imported. The reference in `Promo/Animations/user.svg`
/// is a hundred and eighty paths and two hundred and forty-five keyframes in a
/// style of its own; what is wanted is that character in this app's style, so
/// the shapes are rebuilt from circles and strokes and the palette is taken from
/// the file: teal body, magenta mouth, amber trampoline.
///
/// The point it makes: while the agent works, the person is away from the
/// keyboard. That is who Belay is for, and it is why the figure keeps bouncing
/// long after the screen has gone quiet.
struct Bouncer: View {
    /// Nought while the agent works and the bouncing is high, one once the Mac
    /// has gone to sleep and the bouncing has settled.
    var resting: Double
    var time: Double

    private static let body = Color(red: 0.129, green: 0.620, blue: 0.737)
    private static let mouth = Color(red: 0.855, green: 0.067, blue: 0.408)
    private static let mat = Color.white
    private static let ring = Color(red: 1.0, green: 0.718, blue: 0.012)
    private static let ringEdge = Color(red: 0.984, green: 0.522, blue: 0.0)

    /// One bounce every this many seconds.
    /// Slower than a real bounce on purpose. The reference moves gently and so
    /// should this: at one and a bit seconds it read as bouncing, at one and
    /// three quarters it reads as enjoying itself.
    private static let beat: Double = 1.75

    /// One arm or leg: where it leaves the body, how far it reaches, and how
    /// much it swings as the jump opens out.
    private struct Limb {
        var angle: Double
        var length: Double
        var swing: Double

        // Arms leave at the shoulder, barely above the middle, and the bend
        // carries them up. Leaving at a third of a turn from horizontal they
        // came out of the top of the head and read as antennae.
        static let all = [
            Limb(angle: .pi * 1.09, length: 0.95, swing: -0.26),
            Limb(angle: .pi * 1.91, length: 0.95, swing: 0.26),
            Limb(angle: .pi * 0.70, length: 0.86, swing: -0.16),
            Limb(angle: .pi * 0.30, length: 0.86, swing: 0.16)
        ]
    }

    var body: some View {
        Canvas { context, size in
            let unit = size.height / 100
            let matY = size.height - 24 * unit
            let phase = (time / Self.beat).truncatingRemainder(dividingBy: 1)
            // A ball's flight: fast off the mat, slow at the top, fast back.
            // 4t(1-t) is that curve and needs no easing table.
            let flight = 4 * phase * (1 - phase)
            // Kept inside the frame: at forty-six the head left the top of it.
            let height = (30 * unit) * flight * (1 - resting)
            // Squashed where the mat catches them, stretched on the way up.
            let squash = 1 - 0.18 * (1 - min(1, flight * 4)) * (1 - resting)

            draw(
                trampoline: &context, size: size, unit: unit, matY: matY,
                dip: (1 - min(1, flight * 4)) * (1 - resting))
            draw(
                figure: &context, unit: unit,
                centre: CGPoint(x: size.width / 2, y: matY - 22 * unit - height),
                squash: squash, flight: flight)
        }
        .accessibilityHidden(true)
    }

    private func draw(
        trampoline context: inout GraphicsContext,
        size: CGSize,
        unit: CGFloat,
        matY: CGFloat,
        dip: Double
    ) {
        let width = 58 * unit
        let sag = 5 * unit * dip
        // Legs first, so the mat sits over them.
        for side in [-1.0, 1.0] {
            var leg = Path()
            leg.move(to: CGPoint(x: size.width / 2 + width * 0.36 * side, y: matY + 3 * unit))
            leg.addLine(to: CGPoint(x: size.width / 2 + width * 0.46 * side, y: matY + 18 * unit))
            context.stroke(
                leg, with: .color(Self.ringEdge.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2.4 * unit, lineCap: .round))
        }
        let mat = CGRect(
            x: size.width / 2 - width / 2, y: matY - 4 * unit + sag,
            width: width, height: 9 * unit)
        context.fill(Path(ellipseIn: mat), with: .color(Self.mat))
        context.stroke(
            Path(ellipseIn: mat), with: .color(Self.ring),
            style: StrokeStyle(lineWidth: 3.4 * unit))
    }

    private func draw(
        figure context: inout GraphicsContext,
        unit: CGFloat,
        centre: CGPoint,
        squash: Double,
        flight: Double
    ) {
        let radius = 17 * unit
        let ball = CGRect(
            x: centre.x - radius, y: centre.y - radius * squash,
            width: radius * 2, height: radius * 2 * squash)
        // Limbs leave the body at its edge, not from its middle. Drawn from the
        // centre they crossed behind the head and the figure read as a star.
        let spread = 0.35 + 0.65 * flight
        let limbs = Limb.all
        for limb in limbs {
            let angle = limb.angle + limb.swing * spread
            let from = CGPoint(
                x: centre.x + cos(angle) * radius * 0.88,
                y: centre.y + sin(angle) * radius * 0.88 * squash)
            let reach = radius * limb.length * (0.72 + 0.28 * spread)
            let to = CGPoint(
                x: centre.x + cos(angle) * (radius + reach),
                y: centre.y + sin(angle) * (radius + reach))
            let bend = CGPoint(
                x: (from.x + to.x) / 2 + cos(angle + .pi / 2) * radius * 0.30,
                y: (from.y + to.y) / 2 + sin(angle + .pi / 2) * radius * 0.30)
            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: bend)
            context.stroke(
                path, with: .color(Self.body),
                style: StrokeStyle(lineWidth: 2.8 * unit, lineCap: .round))
        }
        context.fill(Path(ellipseIn: ball), with: .color(Self.body))
        // The face, which is the whole of the character. The eyes are tilted
        // towards each other, which is the difference between a face and two
        // dots, and the mouth is open because the figure is having a good time.
        let eye = CGSize(width: 2.6 * unit, height: 3.4 * unit)
        for side in [-1.0, 1.0] {
            var oval = Path(
                ellipseIn: CGRect(
                    x: -eye.width, y: -eye.height, width: eye.width * 2, height: eye.height * 2))
            oval = oval.applying(CGAffineTransform(rotationAngle: 0.22 * side))
            oval = oval.applying(
                CGAffineTransform(
                    translationX: centre.x + 5.8 * unit * side, y: centre.y - 4.6 * unit))
            context.fill(oval, with: .color(.black))
        }
        let grin = CGRect(
            x: centre.x - 3 * unit, y: centre.y + 1.5 * unit,
            width: 6 * unit, height: 5 * unit)
        context.fill(Path(ellipseIn: grin), with: .color(Self.mouth))
    }
}
