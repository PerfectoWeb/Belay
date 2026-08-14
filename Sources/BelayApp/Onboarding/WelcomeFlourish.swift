import SwiftUI

/// The word that writes itself once, when the welcome window opens, and is
/// never seen again.
///
/// It is a greeting, so it is over before it is in the way: the panel holds it
/// for two seconds and then hands the space to the scene, which is the part
/// that has something to say. Coming back to it on every loop would turn a
/// greeting into a slogan.
///
/// Drawn here rather than played from a file. An animation format would mean a
/// runtime, an asset and a dependency, in an app whose whole argument is that it
/// brings nothing with it; and a file would carry one hard-coded language, while
/// this is the reader's own word in the reader's own script.
///
/// The stroke is a mask travelling along the line rather than an outline being
/// traced. A traced outline is what a font can give you and it reads as a letter
/// being *drawn around*; ink arriving along the pen's own path is what writing
/// looks like, and against a connected script it is the same picture.
struct WelcomeFlourish: View {
    /// Called once the word has been written, held and faded.
    var onFinished: () -> Void

    /// How far the ink has travelled, nought to one.
    @State private var written: CGFloat = 0
    @State private var faded = false

    /// Long enough to be read as writing rather than as a wipe, short enough
    /// that nobody waits for it. The rest of the budget is the pause afterwards,
    /// which is what stops it feeling like a transition.
    private static let writing: Double = 1.25
    private static let holding: Double = 0.45
    private static let fading: Double = 0.5

    /// The soft leading edge, as a fraction of the width. Without it the ink has
    /// a straight vertical end and the word reads as being uncovered by a card.
    private static let nib: CGFloat = 0.06

    var body: some View {
        Text("Welcome")
            // Snell Roundhand is on every Mac and it is a connected script, so
            // the mask travels along one continuous line instead of jumping
            // between separate letters. Where it has no glyphs, as in Chinese,
            // the system substitutes and the same sweep still reads as strokes
            // arriving.
            .font(.custom("SnellRoundhand-Black", size: 52))
            .foregroundStyle(.white.opacity(0.95))
            .shadow(color: Color.accentColor.opacity(0.35), radius: 12)
            .lineLimit(1)
            // Some languages need most of the panel for this word. Shrinking is
            // better than clipping, and better than a second size chosen by
            // guessing which language is longest.
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 24)
            .mask(alignment: .leading) { ink }
            .opacity(faded ? 0 : 1)
            .task { await run() }
            .accessibilityHidden(true)
    }

    /// White where the ink has been, clear where it has not, with the nib's
    /// width of gradient between the two.
    private var ink: some View {
        GeometryReader { geometry in
            let head = written * (1 + Self.nib)
            let tail = max(0, head - Self.nib)
            LinearGradient(
                stops: [
                    .init(color: .white, location: min(tail, 0.999)),
                    .init(color: .clear, location: min(max(head, 0.001), 1))
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// Written, held, faded, gone. Eased in and out because a hand starts and
    /// stops; a linear sweep is a machine printing.
    private func run() async {
        withAnimation(.easeInOut(duration: Self.writing)) { written = 1 }
        try? await Task.sleep(for: .seconds(Self.writing + Self.holding))
        withAnimation(.easeIn(duration: Self.fading)) { faded = true }
        try? await Task.sleep(for: .seconds(Self.fading))
        onFinished()
    }
}
