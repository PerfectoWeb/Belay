import SwiftUI

/// Belay's mark, and the agents going round it.
///
/// The tile is the app icon as the app draws it everywhere else. The ring is the
/// work: four agents on one orbit, each at its own speed, so the group never
/// falls into step and reads as four things rather than one turning picture.
///
/// They pop one at a time when the work ends. A bubble is the right idea for a
/// session: it was there, it is not, and nothing is left behind.
struct AgentOrbit: View {
    /// One entry per agent, nought while it is running and one once popped.
    var popped: [Double]
    /// How lit the mark is. Blinks at the end, then settles.
    var glow: Double
    var time: Double

    /// The logos the app already ships, in the order they take the ring.
    private static let agents = ["claude", "codex", "gemini", "cline"]
    /// Each one's own rate, in turns per second, and none divides into another.
    private static let rates: [Double] = [0.085, -0.062, 0.11, -0.048]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 13
            ZStack {
                // The ring goes with the agents. Left behind after the last one
                // pops it reads as a track with nothing on it.
                Ellipse()
                    .strokeBorder(
                        Color.white.opacity(0.16 * (1 - popped.reduce(0, +) / Double(popped.count))),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 4])
                    )
                    .frame(width: radius * 2, height: radius * 2 * 0.62)
                    .position(centre)

                tile.position(centre)

                ForEach(Array(Self.agents.enumerated()), id: \.offset) { index, name in
                    chip(name, index: index, centre: centre, radius: radius)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// The app icon, on its own rounded tile, the way it appears in the Dock.
    private var tile: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.29, green: 0.56, blue: 1), Color(red: 0.13, green: 0.42, blue: 1)],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 42, height: 42)
            .overlay {
                Image(nsImage: BelayGlyph.image(.alwaysOn, size: 26))
                    .renderingMode(.template)
                    .foregroundStyle(.white)
            }
            .shadow(color: Color.accentColor.opacity(0.55 * glow), radius: 10 * glow)
            .opacity(0.55 + 0.45 * glow)
    }

    /// One agent: a white disc with its logo, riding the ellipse. The pop is a
    /// quick swell and out, which is what a bubble does.
    private func chip(_ name: String, index: Int, centre: CGPoint, radius: CGFloat) -> some View {
        let gone = popped[min(index, popped.count - 1)]
        let angle = time * Self.rates[index] * 2 * .pi + Double(index) * (2 * .pi / 4)
        let point = CGPoint(
            x: centre.x + cos(angle) * radius,
            y: centre.y + sin(angle) * radius * 0.62)
        let swell = 1 + 0.55 * sin(min(1, gone * 1.6) * .pi)
        return Circle()
            .fill(Color.white)
            .frame(width: 21, height: 21)
            .overlay {
                Image(nsImage: ProviderMark.image(preset: name, size: 13))
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .scaleEffect(gone >= 1 ? 0.001 : swell)
            .opacity(1 - gone)
            .position(point)
    }
}
