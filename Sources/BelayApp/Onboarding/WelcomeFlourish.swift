import SwiftUI

/// The word that writes itself once, when the welcome window opens, and is
/// never seen again.
///
/// It is a greeting, so it is over before it is in the way: the panel holds it
/// for a moment and then hands the space to the scene, which is the part with
/// something to say. Coming back to it every loop would turn a greeting into a
/// slogan.
///
/// The line is `WelcomeStroke`, traced from the reference artwork, and it is
/// drawn by trimming that line rather than by uncovering finished text. Two
/// earlier attempts used a font and a moving mask; both were a card being
/// pulled away from a word that was already there, which is not writing.
///
/// No animation runtime and no asset is loaded. The motion is one number going
/// from nought to one under `withAnimation`, so SwiftUI interpolates it on the
/// render thread at the display's own rate: no timer, no frame loop, nothing
/// allocated per frame, and one stroked path on screen.
struct WelcomeFlourish: View {
    /// Called when the word has been written and held, at the moment it starts
    /// to fade. The sky comes up on this, so the two cross rather than queue.
    var onWritten: () -> Void
    /// Called once the word is gone and the space is free.
    var onFinished: () -> Void

    /// How much of the line has been drawn, nought to one.
    @State private var written: CGFloat = 0
    @State private var faded = false

    /// How wide the word is drawn. The height follows from the artwork's own
    /// proportion, so the hand is never stretched.
    private static let width: CGFloat = 262
    private static let writing: Double = 1.5
    /// Long enough to be a pause and not a beat. Under half a second the word
    /// read as a transition; a greeting waits.
    private static let holding: Double = 1.2
    private static let fading: Double = 0.5
    /// How far the scene's music leads its picture. The cinematic starts
    /// inside the held word, so the sky rises into a piece already playing —
    /// anticipation, the way a score enters before the cut. Tuned by ear:
    /// at a full second the music felt early, at nought it felt late.
    private static let musicLead: Double = 0.7

    /// The reference draws a 9-unit stroke across an artwork 95.34 units tall.
    /// Kept as that ratio rather than as a number of points, so the weight of
    /// the line stays right at any size.
    private static let weight: CGFloat = 9 / 95.34

    var body: some View {
        let height = Self.width / WelcomeStroke.aspect
        return WelcomeStroke()
            .trim(from: 0, to: written)
            .stroke(
                style: StrokeStyle(
                    lineWidth: height * Self.weight, lineCap: .round, lineJoin: .round)
            )
            .foregroundStyle(.white.opacity(0.97))
            .shadow(color: Color.accentColor.opacity(0.30), radius: 14)
            .frame(width: Self.width, height: height)
            // The wand: dust trailing the pen, then flying off the last
            // letter. An overlay so it shares the stroke's frame exactly, and
            // it fades with the word rather than outliving it.
            .overlay { WelcomeWand(wordSize: CGSize(width: Self.width, height: height)) }
            .opacity(faded ? 0 : 1)
            .task { await run() }
            .accessibilityHidden(true)
    }

    /// Written, held, faded, gone. Eased because a hand starts and stops; a
    /// linear draw is a machine printing.
    private func run() async {
        // The spell starts with the stroke and is left to ring right through
        // the fade and into the scene: it is eight seconds long on purpose,
        // and stopping it at any picture boundary would cut a tail everyone
        // can hear. Gated inside `Feedback` like every other sound.
        Feedback.play(.welcomeSpell)
        withAnimation(.easeInOut(duration: Self.writing)) { written = 1 }
        try? await Task.sleep(for: .seconds(Self.writing + Self.holding - Self.musicLead))
        // A cancelled sleep returns at once rather than throwing out of a
        // `try?`, so without this a window closed mid-word still runs the rest
        // of the script — starting the scene's music over a window that is
        // already gone. The soundtrack loop next door guards the same way.
        guard !Task.isCancelled else { return }
        Feedback.play(.welcomeCinematic)
        try? await Task.sleep(for: .seconds(Self.musicLead))
        guard !Task.isCancelled else { return }
        onWritten()
        withAnimation(.easeIn(duration: Self.fading)) { faded = true }
        try? await Task.sleep(for: .seconds(Self.fading))
        guard !Task.isCancelled else { return }
        onFinished()
    }
}
