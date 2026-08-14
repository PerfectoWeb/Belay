import SwiftUI

/// The word that writes itself once, when the welcome window opens, and is
/// never seen again.
///
/// It is a greeting, so it is over before it is in the way: the panel holds it
/// for a moment and then hands the space to the scene, which is the part with
/// something to say. Coming back to it every loop would turn a greeting into a
/// slogan.
///
/// Written rather than revealed. A nib as tall as the line travels along the
/// word's own midline and the letters appear where it has been, which is what
/// writing looks like; the first version slid a straight vertical edge across
/// finished text, and that is a card being pulled away.
///
/// No animation runtime and no asset. The motion is one number going from
/// nought to one under `withAnimation`, so SwiftUI interpolates it on the
/// render thread at the display's own rate: no timer, no frame loop, nothing
/// per-frame to allocate, and it is as smooth as the panel it sits in.
struct WelcomeFlourish: View {
    /// Called when the word has been written and held, at the moment it starts
    /// to fade. The sky comes up on this, so the two cross rather than queue.
    var onWritten: () -> Void
    /// Called once the word is gone and the space is free.
    var onFinished: () -> Void

    /// How far the nib has travelled, nought to one.
    @State private var written: CGFloat = 0
    @State private var faded = false

    /// Long enough to be read as writing rather than as a wipe, short enough
    /// that nobody waits for it.
    private static let writing: Double = 1.5
    /// Long enough to be a pause and not a beat. Under half a second the word
    /// read as a transition; a greeting waits.
    private static let holding: Double = 1.2
    private static let fading: Double = 0.5

    var body: some View {
        Text("Welcome")
            // A rounded brush script, and connected, so the nib crosses from
            // one letter into the next instead of stepping between islands.
            // It is on every Mac; where it has no glyphs, as in Chinese, the
            // system substitutes and the same hand still writes them.
            .font(.custom("SignPainter-HouseScript", size: 64))
            .foregroundStyle(.white.opacity(0.97))
            .shadow(color: Color.accentColor.opacity(0.30), radius: 14)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 24)
            .mask(alignment: .center) { nib }
            .opacity(faded ? 0 : 1)
            .task { await run() }
            .accessibilityHidden(true)
    }

    /// The nib: a stroke as tall as the line, trimmed to how far it has gone.
    /// Trimming a shape is animated by SwiftUI itself, which is why this needs
    /// no clock of its own.
    private var nib: some View {
        Stroke()
            .trim(from: 0, to: written)
            .stroke(style: StrokeStyle(lineWidth: 150, lineCap: .round, lineJoin: .round))
    }

    /// Written, held, faded, gone. Eased because a hand starts and stops; a
    /// linear sweep is a machine printing.
    private func run() async {
        withAnimation(.easeInOut(duration: Self.writing)) { written = 1 }
        try? await Task.sleep(for: .seconds(Self.writing + Self.holding))
        onWritten()
        withAnimation(.easeIn(duration: Self.fading)) { faded = true }
        try? await Task.sleep(for: .seconds(Self.fading))
        onFinished()
    }
}

/// The path the nib takes: left to right along the middle, rising and falling
/// gently. The wander is what stops the leading edge reading as a ruler; it is
/// small, because a hand writing a word this size does not swing.
private struct Stroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 120
        // Started and finished outside the text, so the first letter is not
        // already half-inked at nought and the last is fully inked at one.
        let lead = rect.height * 0.6
        for step in 0...steps {
            let along = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: rect.minX - lead + (rect.width + lead * 2) * along,
                y: rect.midY + sin(along * .pi * 2.6) * rect.height * 0.12)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
