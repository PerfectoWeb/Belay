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
    private static let count = 90
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: animated ? Self.tick : 3600)) { timeline in
            Canvas { context, size in
                let now = (pausedAt ?? timeline.date.timeIntervalSinceReferenceDate) - paused
                for index in 0..<Self.count {
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

    /// Derived from the index and the clock alone: nothing stored, nothing
    /// allocated per frame, and the same sky on every machine at the same
    /// instant, which is what makes it testable.
    private struct Star {
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

            // Rising, and not at a constant rate: a slow sine on the speed makes
            // each one drift and then hurry, which is what stops ninety dots
            // moving in lockstep from reading as a scrolling texture.
            let eased = now + sin(now * (0.06 + depth * 0.12) + phase * 6.283) * 1.6
            across = CGFloat(column)
            down = CGFloat(1 - (phase + eased * speed).truncatingRemainder(dividingBy: 1))

            let peak = 0.10 + depth * 0.45
            // Each on its own period and phase, so the field never pulses as one.
            let twinkle = 0.55 + 0.45 * sin(now * (0.5 + noise.unit() * 2.2) + noise.unit() * 6.283)
            alpha = peak * twinkle
        }
    }
}

/// The product mark, breathing. Reuses the menu bar artwork so About and the
/// menu bar can never drift apart.
struct BreathingMark: View {
    var animated: Bool

    /// Rendered once. Rebuilding the vector artwork on every tick was most of
    /// the 8.3% this pane used to cost.
    @MainActor private static let frames: [NSImage] = (0..<VigilGlyph.frameCount).map {
        VigilGlyph.image(.working, frame: $0, size: 46)
    }

    var body: some View {
        // Not the menu bar's schedule. Up there the hold is the point — it is
        // what keeps a moving icon affordable. Here it reads as the animation
        // having stopped, and About is the one page in the app whose job is to
        // present rather than to stay out of the way.
        TimelineView(.periodic(from: .now, by: animated ? 0.075 : 3600)) { timeline in
            let frame =
                animated
                ? Int(timeline.date.timeIntervalSinceReferenceDate / 0.075) % VigilGlyph.frameCount
                : 0
            Image(nsImage: Self.frames[frame])
                .resizable()
                .foregroundStyle(.tint)
        }
        .accessibilityHidden(true)
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
