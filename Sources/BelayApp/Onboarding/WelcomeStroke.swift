import SwiftUI

/// The word "Welcome", as one continuous line.
///
/// Traced from `Promo/Animations/Welcome.svg`, which is a single `<path>` of
/// thirty-one cubic segments drawn with `stroke-dasharray` and a moving
/// `stroke-dashoffset`. That is exactly what `trim(from:to:)` does, so the
/// motion here is the one the reference describes rather than an imitation of
/// it. Nothing is parsed at runtime and no animation library is linked: the
/// curve is source.
///
/// The points are the artwork's own, normalised into a unit box, so the shape
/// fills whatever rectangle it is given. Give it one of proportion `aspect` or
/// the hand comes out stretched.
struct WelcomeStroke: Shape {
    /// Width over height of the artwork.
    static let aspect: CGFloat = 4.0882

    /// One cubic segment, in unit coordinates. `one` and `two` are its control
    /// points, named short because at thirty-one segments that is what lets one
    /// fit on two lines and stay readable.
    private struct Curve {
        var to: CGPoint
        var one: CGPoint
        var two: CGPoint
    }

    private static let start = CGPoint(x: 0.01648, y: 0.00000)

    private static let curves: [Curve] = [
        Curve(
            to: .init(x: 0.05130, y: 0.90492),
            one: .init(x: 0.01648, y: 0.00000), two: .init(x: 0.00000, y: 0.94485)),
        Curve(
            to: .init(x: 0.11293, y: 0.31523),
            one: .init(x: 0.08793, y: 0.87640), two: .init(x: 0.11293, y: 0.31523)),
        Curve(
            to: .init(x: 0.14230, y: 0.90549),
            one: .init(x: 0.11293, y: 0.31523), two: .init(x: 0.09382, y: 0.93782)),
        Curve(
            to: .init(x: 0.20339, y: 0.07955),
            one: .init(x: 0.18099, y: 0.87969), two: .init(x: 0.25404, y: 0.06602)),
        Curve(
            to: .init(x: 0.23638, y: 0.77307),
            one: .init(x: 0.17243, y: 0.08782), two: .init(x: 0.17414, y: 0.68826)),
        Curve(
            to: .init(x: 0.31767, y: 0.59555),
            one: .init(x: 0.27550, y: 0.82638), two: .init(x: 0.31571, y: 0.71873)),
        Curve(
            to: .init(x: 0.25828, y: 0.60626),
            one: .init(x: 0.31994, y: 0.45350), two: .init(x: 0.27280, y: 0.42950)),
        Curve(
            to: .init(x: 0.31853, y: 0.90642),
            one: .init(x: 0.24493, y: 0.76879), two: .init(x: 0.26802, y: 0.96663)),
        Curve(
            to: .init(x: 0.43521, y: 0.20721),
            one: .init(x: 0.39062, y: 0.82046), two: .init(x: 0.43148, y: 0.36719)),
        Curve(
            to: .init(x: 0.39066, y: 0.17240),
            one: .init(x: 0.43914, y: 0.03850), two: .init(x: 0.40900, y: 0.02243)),
        Curve(
            to: .init(x: 0.40704, y: 0.91691),
            one: .init(x: 0.37353, y: 0.31249), two: .init(x: 0.34533, y: 0.91691)),
        Curve(
            to: .init(x: 0.49449, y: 0.53406),
            one: .init(x: 0.44107, y: 0.91691), two: .init(x: 0.45865, y: 0.62012)),
        Curve(
            to: .init(x: 0.53733, y: 0.48993),
            one: .init(x: 0.51994, y: 0.47296), two: .init(x: 0.53733, y: 0.48993)),
        Curve(
            to: .init(x: 0.46723, y: 0.69591),
            one: .init(x: 0.53733, y: 0.48993), two: .init(x: 0.47864, y: 0.50356)),
        Curve(
            to: .init(x: 0.53856, y: 0.88545),
            one: .init(x: 0.46169, y: 0.78922), two: .init(x: 0.48512, y: 1.00000)),
        Curve(
            to: .init(x: 0.63267, y: 0.50388),
            one: .init(x: 0.58822, y: 0.77899), two: .init(x: 0.57083, y: 0.53614)),
        Curve(
            to: .init(x: 0.67278, y: 0.70400),
            one: .init(x: 0.65776, y: 0.49080), two: .init(x: 0.67444, y: 0.61584)),
        Curve(
            to: .init(x: 0.61448, y: 0.91290),
            one: .init(x: 0.67049, y: 0.82586), two: .init(x: 0.64232, y: 0.92897)),
        Curve(
            to: .init(x: 0.58271, y: 0.66250),
            one: .init(x: 0.58905, y: 0.89822), two: .init(x: 0.57276, y: 0.75081)),
        Curve(
            to: .init(x: 0.63267, y: 0.50388),
            one: .init(x: 0.59836, y: 0.52357), two: .init(x: 0.61672, y: 0.50922)),
        Curve(
            to: .init(x: 0.70301, y: 0.69606),
            one: .init(x: 0.67153, y: 0.49088), two: .init(x: 0.68232, y: 0.70635)),
        Curve(
            to: .init(x: 0.73712, y: 0.57167),
            one: .init(x: 0.72324, y: 0.68601), two: .init(x: 0.73712, y: 0.57167)),
        Curve(
            to: .init(x: 0.72236, y: 0.90338),
            one: .init(x: 0.73712, y: 0.57167), two: .init(x: 0.72236, y: 0.90338)),
        Curve(
            to: .init(x: 0.77624, y: 0.53293),
            one: .init(x: 0.72236, y: 0.90338), two: .init(x: 0.75200, y: 0.52370)),
        Curve(
            to: .init(x: 0.78828, y: 0.81910),
            one: .init(x: 0.80377, y: 0.54341), two: .init(x: 0.78828, y: 0.81910)),
        Curve(
            to: .init(x: 0.84144, y: 0.53885),
            one: .init(x: 0.78828, y: 0.81910), two: .init(x: 0.81449, y: 0.51578)),
        Curve(
            to: .init(x: 0.85526, y: 0.90202),
            one: .init(x: 0.86752, y: 0.56118), two: .init(x: 0.82691, y: 0.84407)),
        Curve(
            to: .init(x: 0.96019, y: 0.60094),
            one: .init(x: 0.88714, y: 0.96718), two: .init(x: 0.95823, y: 0.72413)),
        Curve(
            to: .init(x: 0.90080, y: 0.61165),
            one: .init(x: 0.96246, y: 0.45889), two: .init(x: 0.91532, y: 0.43489)),
        Curve(
            to: .init(x: 0.95051, y: 0.91859),
            one: .init(x: 0.88912, y: 0.75387), two: .init(x: 0.91049, y: 0.91823)),
        Curve(
            to: .init(x: 1.00000, y: 0.84415),
            one: .init(x: 0.97585, y: 0.91882), two: .init(x: 0.99483, y: 0.86076))
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: at(Self.start, in: rect))
        for curve in Self.curves {
            path.addCurve(
                to: at(curve.to, in: rect),
                control1: at(curve.one, in: rect),
                control2: at(curve.two, in: rect))
        }
        return path
    }

    /// A point given as a fraction of the artwork, placed in `rect`.
    private func at(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * point.x, y: rect.minY + rect.height * point.y)
    }
}
