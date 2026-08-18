import AppKit
import BelayCore

/// Belay's mark: a large sparkle with two smaller ones that twinkle while an
/// agent is working.
///
/// Drawn from vector paths rather than looked up as an SF Symbol. `moon.slash`
/// once shipped as the Off icon and does not exist on macOS 26 —
/// `NSImage(systemSymbolName:)` returned nil, the button got no image, and the
/// status item vanished from the menu bar with the app still running. A drawing
/// cannot go missing.
///
/// Every frame is a template image, so light, dark, tinted and reduced-
/// transparency menu bars are AppKit's problem and no colour appears here.
///
/// Main-actor bound because `NSBezierPath` is not `Sendable` and the parsed
/// artwork is cached; all drawing happens on the main thread anyway.
@MainActor
enum BelayGlyph {
    /// What the mark shows. Fewer looks than there are `BelayState` cases on
    /// purpose: the user needs "is my Mac being held awake", not a state dump.
    enum Look: Hashable {
        /// Always on: all three sparkles lit and still. A chosen mode should not
        /// twitch — the animation means "an agent is doing something", and in
        /// this mode nothing is.
        case alwaysOn
        /// At least one session is actually working: the small sparkles twinkle.
        case working
        /// Auto with everything idle, including the grace period. The big
        /// sparkle stays lit; the small ones drop to a whisper.
        case resting
        /// An agent needs the user. All three, breathing slowly — deliberately
        /// unlike the twinkle, because this one wants attention.
        case calling
        /// Belay is holding nothing: all three, dim.
        case off
        /// Battery guard or the maximum-awake cap.
        case blocked

        init(state: BelayState) {
            switch state {
            case .alwaysOn: self = .alwaysOn
            case .working: self = .working
            // Cooling down means no session is working any more, so by the same
            // rule the sparkles settle even though the assertion is still held.
            case .coolingDown, .armed: self = .resting
            case .awaitingUser: self = .calling
            case .off: self = .off
            case .suspended: self = .blocked
            }
        }

        var isAnimated: Bool { self == .working || self == .calling }
    }

    /// How dim a resting sparkle is. Not zero — they still have to be findable
    /// in a crowded menu bar — and not lower than this, because below roughly a
    /// quarter they disappear against a busy wallpaper.
    private static let dim: CGFloat = 0.26

    /// Twinkle steps. Menu bar redraws are the cost, not the drawing — the
    /// frames are cached — so CPU tracks the *tick rate*, almost linearly:
    ///
    ///     8.3 Hz  2.10%   over the docs/08 active budget of 1.0%
    ///     4.0 Hz  0.96%   inside, but with no room for the detection work
    ///     3.0 Hz  0.48%   inside, and dull
    ///
    /// A flat rate makes that a choice between "lively" and "affordable". So the
    /// rate is not flat: the sparkles run a quick shimmer and then hold still.
    /// The shimmer is fast enough to read as *working*, and the hold costs one
    /// timer wake, so the average lands where a slow flat tick did.
    nonisolated static let frameCount = 12

    /// Seconds each frame is held.
    ///
    /// Eleven frames at 80 ms — a shimmer of just under a second — then one
    /// frame held for two. Twelve wakes per 2.88 s is 4.2 a second on average,
    /// which by the table above lands near 0.65%: inside the budget, with the
    /// headroom the flat 8 Hz version did not have, and motion that reads far
    /// livelier than 3 Hz ever did.
    ///
    /// Measured on the machine this was written on: 0.7–1.2% for the whole
    /// process with three agents running, which is detection as well as this.
    nonisolated static func frameDuration(_ frame: Int) -> TimeInterval {
        frame == frameCount - 1 ? 2.0 : 0.08
    }

    /// The frame this schedule is showing at `date`, so anything that draws the
    /// mark stays in step with the menu bar rather than running its own clock.
    nonisolated static func frame(at date: Date) -> Int {
        let cycle = (0..<frameCount).map(frameDuration).reduce(0, +)
        var offset = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        for index in 0..<frameCount {
            offset -= frameDuration(index)
            if offset < 0 { return index }
        }
        return frameCount - 1
    }

    private static let artwork =
        "M19.5,24a1,1,0,0,1-.929-.628l-.844-2.113-2.116-.891a1.007,1.007,0,0,1,.035-1.857l2.088-.791"
        + ".837-2.092a1.008,1.008,0,0,1,1.858,0l.841,2.1,2.1.841a1.007,1.007,0,0,1,0,1.858l-2.1.841"
        + "-.841,2.1A1,1,0,0,1,19.5,24ZM10,21a2,2,0,0,1-1.936-1.413L6.45,14.54,1.387,12.846a2.032,"
        + "2.032,0,0,1,.052-3.871L6.462,7.441,8.154,2.387A1.956,1.956,0,0,1,10.108,1a2,2,0,0,1,1.917,"
        + "1.439l1.532,5.015,5.03,1.61a2.042,2.042,0,0,1,0,3.872h0l-5.039,1.612-1.612,5.039A2,2,0,0,1,"
        + "10,21ZM20.5,7a1,1,0,0,1-.97-.757l-.357-1.43L17.74,4.428a1,1,0,0,1,.034-1.94l1.4-.325L19.53"
        + ".757a1,1,0,0,1,1.94,0l.354,1.418,1.418.355a1,1,0,0,1,0,1.94l-1.418.355L21.47,6.243A1,1,0,0,"
        + "1,20.5,7Z"

    /// Parsed once. Three subpaths: [0] top-right spark, [1] the big one,
    /// [2] bottom-right spark.
    private static let parts = SVGPath.subpaths(artwork, flipHeight: 24)

    /// The same three, for anything that wants to move them independently.
    /// Exposed rather than re-parsed, so a second copy of the mark cannot drift
    /// away from the one in the menu bar.
    static var artworkSubpaths: [NSBezierPath] { parts }

    /// Menu bar images are in points; 17 leaves the usual breathing room.
    static func statusItemImage(_ look: Look, frame: Int = 0, waiting: Bool = false) -> NSImage {
        image(look, frame: frame, size: 17, waiting: waiting)
    }

    static func image(
        _ look: Look, frame: Int = 0, size: CGFloat, waiting: Bool = false
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(look, frame: frame, size: size, waiting: waiting)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ look: Look, frame: Int, size: CGFloat, waiting: Bool) {
        guard parts.count == 3 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let scale = size / 24
        (AffineTransform(scaleByX: scale, byY: scale) as NSAffineTransform).concat()

        let big = parts[1]
        // An update is waiting, and this is the only place the app says so
        // without being asked.
        //
        // Not while an agent is working, and not while one is waiting on the
        // user. Belay exists to protect exactly those two moments, and a mark
        // changing in the middle of a run is the app interrupting the thing it
        // is for. The rule lives here rather than at the call site so that no
        // caller can get it wrong.
        let showsUpdate = waiting && look != .working && look != .calling
        // The refresh mark stands where the lower right sparkle would, so that
        // one is not drawn underneath it.
        let small = showsUpdate ? [parts[2]] : [parts[0], parts[2]]

        switch look {
        case .working:
            fill(big, alpha: 1)
            for (index, spark) in small.enumerated() {
                // Half a cycle apart, so one is always rising as the other falls,
                // and the pair reads as a shimmer travelling across the mark
                // rather than as two lights blinking together.
                let level = twinkle(frame: frame, phase: index * frameCount / 2)
                fill(spark, alpha: level, scale: 0.62 + 0.38 * level)
            }
        default:
            let levels = brightness(look, frame: frame)
            fill(big, alpha: levels.big)
            for spark in small { fill(spark, alpha: levels.small) }
            // "The battery guard stopped me" must never look like "you turned me
            // off" — they are different situations and only one is the user's
            // doing.
            if look == .blocked { pausedBars() }
            // Floored rather than matching the sparkle it replaces: in the
            // dimmed looks a sparkle is a whisper on purpose, and a whisper is
            // not what "there is a newer version" should be.
            if showsUpdate { updateMark(alpha: max(levels.small, 0.62)) }
        }
    }

    /// How bright each part is for the looks that light everything uniformly.
    private static func brightness(_ look: Look, frame: Int) -> (big: CGFloat, small: CGFloat) {
        switch look {
        case .alwaysOn:
            return (1, 1)
        case .calling:
            // Deep, and phase-shifted so it starts at the trough: at full
            // brightness this look was pixel-identical to Always-on, and
            // "an agent needs you" has to be unmistakable at a glance.
            let breath = 0.45 + 0.55 * twinkle(frame: frame, phase: frameCount / 2)
            return (breath, breath)
        case .resting:
            return (1, dim)
        default:
            return (dim, dim)
        }
    }

    /// 0…1 along a cosine, offset per spark so the two are never in step.
    /// Bottoms out at `dim` rather than nothing: a sparkle that vanishes
    /// entirely reads as a glitch, not as a shimmer.
    private static func twinkle(frame: Int, phase: Int) -> CGFloat {
        let step = CGFloat((frame + phase) % frameCount) / CGFloat(frameCount)
        return dim + (1 - dim) * (0.5 + 0.5 * cos(step * 2 * .pi))
    }

    /// Template images are black-on-transparent; AppKit tints them for the menu
    /// bar, so alpha here reads as "dimmer", not "grey".
    static func fill(_ path: NSBezierPath, alpha: CGFloat, scale: CGFloat = 1) {
        guard alpha > 0.01 else { return }
        NSColor(calibratedWhite: 0, alpha: alpha).setFill()
        guard scale != 1 else { return path.fill() }

        let box = path.bounds
        var transform = AffineTransform(translationByX: box.midX, byY: box.midY)
        transform.scale(scale)
        transform.translate(x: -box.midX, y: -box.midY)
        let scaled = NSBezierPath()
        scaled.append(path)
        scaled.transform(using: transform)
        scaled.fill()
    }

    private static func dot(at box: NSRect, alpha: CGFloat) {
        NSColor(calibratedWhite: 0, alpha: alpha).setFill()
        let radius: CGFloat = 1.15
        NSBezierPath(
            ovalIn: NSRect(
                x: box.midX - radius, y: box.midY - radius, width: radius * 2, height: radius * 2)
        ).fill()
    }
}
