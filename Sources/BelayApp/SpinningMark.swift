import SwiftUI

/// The mark, whose three sparkles turn on their own centres now and then.
///
/// Not a constant spin. A logo that never stops moving stops being a logo and
/// becomes a loading indicator, and About is a page people leave open. The
/// sparkles are still for most of the cycle, take one turn, and settle.
///
/// Each turns at its own rate and its own way round. Three identical rotations
/// read as one rotating picture; three different ones read as three objects
/// that happen to be near each other, which is what they are.
///
/// Drawn in a `Canvas` rather than as three rotated views: the artwork is three
/// subpaths of one 24-unit drawing, and keeping them in that coordinate space
/// means the layout cannot drift away from the menu bar's copy of the same mark.
struct SpinningMark: View {
    var colour: Color

    /// The one screen this appears on before Settings is the welcome window, so
    /// a user who has asked macOS for less motion must not meet a spinning logo
    /// on first launch. Every other animated view in the app honours this.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Parsed *and converted* once. The parse was already cached; `cgPath`
    /// builds a fresh path every time it is read, so asking for it inside the
    /// timeline was nine path allocations a frame, thirty times a second, for
    /// the three quarters of the cycle when nothing is turning.
    @MainActor private static let parts = BelayGlyph.artworkSubpaths.map { Path($0.cgPath) }

    /// How long between one set of turns and the next.
    private static let cycle: Double = 11

    /// One sparkle's turn: when in the cycle it starts, how long it takes, and
    /// how far it goes. Signed, because the big one goes clockwise and the
    /// small ones the other way, at different speeds, so the three never look
    /// geared to each other.
    private struct Turn {
        var delay: Double
        var duration: Double
        var revolutions: Double
    }

    private static let turns = [
        Turn(delay: 0.55, duration: 1.35, revolutions: -1),  // top-right, quickest
        Turn(delay: 0, duration: 2.20, revolutions: 1),  // the big one, slowest
        Turn(delay: 0.95, duration: 1.70, revolutions: -2)  // bottom-right, twice round
    ]

    var body: some View {
        // 30 a second. The turn is slow and eased, and the difference against
        // the display's own rate is not visible at this size.
        Group {
            if reduceMotion {
                canvas(at: Self.cycle)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                    canvas(
                        at: timeline.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: Self.cycle))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(at time: Double) -> some View {
        let shapes: [(Path, Double)] = Self.parts.enumerated().compactMap { index, part in
            guard index < Self.turns.count else { return nil }
            return (part, Self.angle(at: time, Self.turns[index]))
        }
        return Canvas { context, size in
            let scale = size.width / 24
            for (path, angle) in shapes {
                let box = path.boundingRect
                let centre = CGPoint(x: box.midX, y: box.midY)
                // Scaled last so the turn happens in artwork units and the
                // sparkle goes about itself rather than about the whole mark.
                var transform = CGAffineTransform(scaleX: scale, y: scale)
                transform = transform.translatedBy(x: centre.x, y: centre.y)
                transform = transform.rotated(by: angle)
                transform = transform.translatedBy(x: -centre.x, y: -centre.y)
                context.fill(path.applying(transform), with: .color(colour))
            }
        }
    }

    /// Eased with a smoothstep so the sparkle leans into the turn and settles
    /// out of it. A linear revolution starts and stops with a jolt, which at
    /// this size reads as a dropped frame.
    private static func angle(at time: Double, _ spec: Turn) -> Double {
        let progress = (time - spec.delay) / spec.duration
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return 0 }
        let eased = progress * progress * (3 - 2 * progress)
        return eased * spec.revolutions * 2 * .pi
    }
}
