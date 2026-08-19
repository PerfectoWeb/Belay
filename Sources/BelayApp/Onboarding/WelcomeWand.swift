import SwiftUI

/// The wand behind the word: dust that trails the pen while "Welcome" writes
/// itself, then flies on past the last letter and comes apart.
///
/// Three promises, in the order they matter:
///
/// - **The dust never leads.** Every grain is born where the pen tip *was*, a
///   beat ago — inertia, not escort. A sparkle ahead of the stroke would say
///   the magic writes the word; the word writes the word.
/// - **It leaves when the word is done.** Past the final letter the trail
///   head lifts off along its own curve, sheds the last grains wider and
///   slower, and is gone as the word starts to fade.
/// - **Nothing here is a particle system.** Like the scene next door, every
///   grain is a pure function of the time and its own index: no state per
///   frame, no allocations, nothing survives between redraws.
struct WelcomeWand: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var began = Date()

    /// The stroke's own frame, handed in by the flourish so the tip table and
    /// the visible word cannot disagree about geometry.
    let wordSize: CGSize

    /// How far dust may travel past the word's frame: room for the fly-off to
    /// the right, a margin everywhere else. A `Canvas` clips to its bounds,
    /// so the canvas is grown by these and the caller pulls the padding back
    /// out — same arrangement as `SparkHalo`.
    static let margin: CGFloat = 56
    static let flight: CGFloat = 150

    /// The pen tip at each trim fraction, sampled once: trimming the path per
    /// grain per frame would do the same work two hundred times a second.
    private let tips: [CGPoint]

    init(wordSize: CGSize) {
        self.wordSize = wordSize
        let rect = CGRect(
            x: Self.margin, y: Self.margin,
            width: wordSize.width, height: wordSize.height)
        let path = WelcomeStroke().path(in: rect)
        let fallback = CGPoint(x: rect.minX, y: rect.midY)
        tips = (0...Self.samples).map { step in
            let fraction = CGFloat(step) / CGFloat(Self.samples)
            guard fraction > 0 else { return path.trimmedPath(from: 0, to: 0.001).currentPoint ?? fallback }
            return path.trimmedPath(from: 0, to: fraction).currentPoint ?? fallback
        }
    }

    private static let samples = 160
    /// The flourish's own timings, mirrored: the writing takes 1.5 s, and the
    /// fly-off happens inside the hold so the dust is gone before the fade.
    private static let writing = 1.5
    private static let flying = 0.9
    private static let grains = 70

    /// After this the dust has all burned out; drawing nothing lets the
    /// timeline's later frames cost a comparison instead of a canvas.
    private static let over = 3.4

    var body: some View {
        if !reduceMotion {
            // The scene's own idiom: time comes down from the timeline into a
            // canvas that is a pure function of it. Reading the clock inside
            // the canvas instead would draw one frame and never be told again.
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                let time = timeline.date.timeIntervalSince(began)
                if time < Self.over {
                    Canvas { context, _ in
                        Self.draw(in: &context, at: time, tips: tips)
                    }
                }
            }
            .frame(
                width: wordSize.width + Self.margin * 2 + Self.flight,
                height: wordSize.height + Self.margin * 2
            )
            // Centre the word's rect over the stroke: the canvas carries the
            // flight room on its right, so it sits offset by half of it.
            .offset(x: Self.flight / 2)
            .allowsHitTesting(false)
        }
    }

    /// Where the trail head is at `time`: the pen tip while writing, then its
    /// own curve up and out. Eased the same way the stroke is drawn, so the
    /// dust tracks the letters and not a linear ghost of them.
    private static func head(at time: Double, tips: [CGPoint]) -> CGPoint? {
        if time < writing {
            let linear = max(0, time / writing)
            let eased = linear * linear * (3 - 2 * linear)
            let index = min(samples, Int(eased * Double(samples)))
            return tips[index]
        }
        let flown = (time - writing) / flying
        guard flown < 1.2 else { return nil }
        let end = tips[samples]
        // Quick off the page and arcing upward, the way a hand finishes an
        // autograph: accelerating out, rising, and easing flat at the top.
        let out = pow(flown, 1.6)
        return CGPoint(
            x: end.x + flight * out,
            y: end.y - 44 * out + 14 * out * out)
    }

    private static func draw(in context: inout GraphicsContext, at time: Double, tips: [CGPoint]) {
        for grain in 0..<grains {
            let seed = Double(grain)
            // Births spread across the writing and the fly-off, jittered so
            // the trail breathes instead of ticking.
            let birth = (seed / Double(grains - 1)) * (writing + flying * 0.7) + hash(seed, 1) * 0.08
            let age = time - birth
            let life = 0.4 + hash(seed, 2) * 0.4
            guard age > 0, age < life, let born = head(at: birth, tips: tips) else { continue }

            let progress = age / life
            // In and out at the ends, like every spark in the app: a grain at
            // full brightness from nowhere reads as a pixel fault.
            let burn = sin(progress * .pi)
            // Late grains are the evaporation: wider drift, floating up.
            let scatter = birth > writing ? 2.2 : 1.0
            let drift = 1 - pow(1 - progress, 2)
            let point = CGPoint(
                x: born.x + (hash(seed, 3) - 0.5) * 26 * scatter * drift,
                y: born.y - (6 + hash(seed, 4) * 16) * scatter * drift)
            let width = (2.4 + hash(seed, 5) * 3.0) * (0.6 + 0.4 * burn)

            // A soft accent glow under a white core, which is the stroke's own
            // colouring read back as dust. Every third grain is the mark in
            // miniature; the rest are motes.
            let glow = SparkHalo.sparkle(at: point, across: width * 1.9)
            context.fill(glow, with: .color(.accentColor.opacity(pow(burn, 1.5) * 0.26)))
            if grain.isMultiple(of: 3) {
                let core = SparkHalo.sparkle(at: point, across: width)
                context.fill(core, with: .color(.white.opacity(pow(burn, 1.2) * 0.85)))
            } else {
                let dot = Path(
                    ellipseIn: CGRect(
                        x: point.x - width / 4, y: point.y - width / 4,
                        width: width / 2, height: width / 2))
                context.fill(dot, with: .color(.white.opacity(pow(burn, 1.2) * 0.8)))
            }
        }
    }

    /// Deterministic per-grain noise, the shader idiom: no generator, no
    /// state, the same dust on every showing.
    private static func hash(_ seed: Double, _ salt: Double) -> Double {
        let value = sin(seed * 127.1 + salt * 311.7) * 43758.5453
        return value - value.rounded(.down)
    }
}
