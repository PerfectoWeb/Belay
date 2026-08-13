import SwiftUI

/// The two moving pieces of the About pane, kept together and kept cheap.
///
/// Measured, then cut down. The first version rebuilt the mark from its vector
/// paths on every tick and the About pane cost **8.3% CPU** — indefensible in an
/// app whose whole argument is that it does not waste the machine's time.
///
/// Caching the mark's frames is where nearly all of that went, which is why the
/// field can now afford 90 stars at 20 fps where the expensive version managed
/// 28 at 6: the cost was never the drifting, it was the redrawing. Both pieces
/// stop dead when the window is not frontmost.

/// A drifting field of faint stars. Positions come from a fixed seed so the
/// layout is the same every launch and nothing has to be stored.
struct Starfield: View {
    var animated: Bool

    /// Ninety stars, drifting.
    ///
    /// The previous version respawned a star in a new place every so often, and
    /// that reads as exactly what it is: a layer being swapped. Stars move.
    /// Each one here has its own constant velocity and wraps at the edges, and
    /// the speed scales with the size, so the big ones cross the field while the
    /// small ones barely creep — parallax, which is what makes a flat canvas
    /// look deep.
    nonisolated private static let count = 90
    /// 20 fps. The whole field is one `Canvas` pass drawing circles, with no
    /// allocation and no state, and this pane stops dead when its window is not
    /// in front — see `AboutPane.isAnimating`.
    private static let tick: TimeInterval = 1.0 / 20

    /// When the window stopped being frontmost, and how much time has been spent
    /// stopped. Without these the field jumped back to its first frame the
    /// moment focus moved, which looks like a glitch in a window you can still
    /// see. It now freezes where it is and carries on from there.
    @State private var pausedAt: TimeInterval?
    @State private var paused: TimeInterval = 0

    /// How many comets can be in flight at once. Three slots on periods that do
    /// not divide into each other, each dark for most of its period: one crosses
    /// every few seconds, two overlap rarely, and the sky is never busy.
    nonisolated static let cometSlots = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: animated ? Self.tick : 3600)) { timeline in
            Canvas { context, size in
                Self.paint(
                    at: (pausedAt ?? timeline.date.timeIntervalSinceReferenceDate) - paused,
                    into: &context, size: size)
            }
        }
        .drawingGroup()
        .onChange(of: animated) { _, isAnimating in
            let now = Date().timeIntervalSinceReferenceDate
            if isAnimating {
                paused += now - (pausedAt ?? now)
                pausedAt = nil
            } else {
                pausedAt = now
            }
        }
    }

    /// The whole frame, given a time. Split out of `body` so a test can render
    /// the sky to a file and look at it, which is the only way to tell whether a
    /// comet reads as a comet.
    nonisolated static func paint(
        at now: TimeInterval, into context: inout GraphicsContext, size: CGSize
    ) {
        for index in 0..<count {
            let star = Star(index: index, at: now)
            let radius = star.size / 2
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: star.across * size.width - radius,
                        y: star.down * size.height - radius,
                        width: star.size, height: star.size)),
                with: .color(.white.opacity(star.alpha)))
        }
        for slot in 0..<cometSlots {
            guard let comet = Comet(slot: slot, at: now, in: size) else { continue }
            draw(comet, into: &context)
        }
    }

    /// The tail is a gradient rather than a line of constant colour, and the
    /// head is a separate dot: without the dot a comet reads as a scratch on the
    /// glass, and with a flat tail it reads as a line that happens to be moving.
    nonisolated private static func draw(_ comet: Comet, into context: inout GraphicsContext) {
        var tail = Path()
        tail.move(to: comet.head)
        tail.addLine(to: comet.tail)
        context.stroke(
            tail,
            with: .linearGradient(
                Gradient(colors: [.white.opacity(comet.alpha), .white.opacity(0)]),
                startPoint: comet.head, endPoint: comet.tail),
            style: StrokeStyle(lineWidth: comet.width, lineCap: .round))
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: comet.head.x - comet.width, y: comet.head.y - comet.width,
                    width: comet.width * 2, height: comet.width * 2)),
            with: .color(.white.opacity(comet.alpha)))
    }

    /// Derived from the index and the clock alone: nothing stored, nothing
    /// allocated per frame, and the same sky on every machine at the same
    /// instant, which is what makes it testable.
    struct Star {
        let across: CGFloat
        let down: CGFloat
        let size: CGFloat
        let alpha: Double

        init(index: Int, at now: TimeInterval) {
            var noise = SplitMix(seed: UInt64(index) &* 0x9E37_79B9 &+ 0x5EED)
            let depth = noise.unit()
            size = 0.8 + CGFloat(depth) * 1.9
            // Near stars travel faster and shine brighter. One number, two jobs,
            // and they agree, which is the whole of the parallax.
            let speed = 0.006 + depth * 0.028
            let column = noise.unit()
            let phase = noise.unit()

            // Falling, and not at a constant rate: a slow sine on the speed
            // makes each one drift and then hurry, which is what stops ninety
            // dots moving in lockstep from reading as a scrolling texture. The
            // wobble stays well under the drift, so nothing ever backs up.
            let eased = now + sin(now * (0.06 + depth * 0.12) + phase * 6.283) * 1.6
            across = CGFloat(column)
            down = CGFloat((phase + eased * speed).truncatingRemainder(dividingBy: 1))

            let peak = 0.10 + depth * 0.45
            // Each on its own period and phase, so the field never pulses as one.
            let twinkle = 0.55 + 0.45 * sin(now * (0.5 + noise.unit() * 2.2) + noise.unit() * 6.283)
            alpha = peak * twinkle
        }
    }

    /// One comet, or nothing at all, which is what it is most of the time.
    ///
    /// Each slot runs on its own period and is lit for a fifth of it. The rest
    /// is deliberately empty: a comet is worth watching because you waited for
    /// it, and a sky with one going past at all times is just weather.
    struct Comet {
        let head: CGPoint
        let tail: CGPoint
        let alpha: Double
        let width: CGFloat

        init?(slot: Int, at now: TimeInterval, in size: CGSize) {
            // Periods that do not divide into each other, so the three never
            // fall into a rhythm.
            let period = 8.5 + Double(slot) * 3.7
            let lit = 0.2
            // Offset as well as detuned. Without this every slot is lit at t=0
            // and the pane opens on all three at once, which is the one moment
            // anybody is looking at it.
            let position = now / period + Double(slot) * 0.41
            let cycle = position.rounded(.down)
            let phase = position - cycle
            guard phase < lit else { return nil }
            let progress = phase / lit

            // Re-seeded per pass, so a comet does not retrace the last one.
            var pass = SplitMix(seed: UInt64(bitPattern: Int64(cycle)) &* 0x9E37 &+ UInt64(slot))
            let fromX = 0.05 + pass.unit() * 0.9
            let fromY = -0.15 + pass.unit() * 0.35
            let leftward = pass.unit() < 0.5
            let tilt = 0.35 + pass.unit() * 0.35
            let angle: Double = .pi / 2 + (leftward ? tilt : -tilt)
            let span = (0.55 + pass.unit() * 0.4) * size.height

            // Bright in the middle of the pass and gone at both ends, so it
            // arrives and burns out rather than being switched on and off.
            let burn = sin(progress * .pi)
            alpha = pow(burn, 1.4) * 0.85
            width = 1.1 + CGFloat(pass.unit()) * 0.6

            let travelled = progress * span
            head = CGPoint(
                x: fromX * size.width + cos(angle) * travelled,
                y: fromY * size.height + sin(angle) * travelled)
            // The tail is the ground it has just covered, capped so a comet at
            // the end of its run is a short bright dash and not a long streak.
            let length = min(travelled, span * 0.28 * burn)
            tail = CGPoint(x: head.x - cos(angle) * length, y: head.y - sin(angle) * length)
        }
    }
}

/// Deterministic noise. `SystemRandomNumberGenerator` would move the stars on
/// every launch, which reads as a rendering bug rather than as a starfield.
private struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func unit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return Double(mixed >> 11) / Double(1 << 53)
    }
}
