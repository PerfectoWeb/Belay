import SwiftUI

/// The first thing anyone sees: what Belay does, shown rather than described.
///
/// One laptop, and above it the mark, holding a rope. The rope runs on down to
/// a plug, which sits in its socket while the Mac is being held awake and is
/// lifted out once Belay lets go. The screen says who is doing what: lines of
/// output while the agent works, a moon once the Mac is allowed to sleep.
///
/// The earlier drawing was two grey rectangles with a rope between them, and it
/// needed the sentence underneath to say which rectangle was which. This one
/// has a single subject. The agent's work happens on the Mac's own screen,
/// which is where it happens in life, and that frees the right-hand side for
/// the thing actually worth showing: a plug, which is what "keeps your Mac
/// awake" looks like when you draw it.
///
/// Shown instead of a third paragraph because the product is a behaviour over
/// time, and a behaviour over time is the one thing prose is worst at. The whole
/// loop is nine seconds and repeats, so nobody has to catch the beginning.
struct OnboardingScene: View {
    /// One pass: work, then quiet, then sleep, then wake and round again.
    nonisolated static let loop: Double = 9

    /// Everything is placed by hand against this box rather than stacked.
    ///
    /// A stack lays itself out, and a picture with a rope in it cannot afford
    /// that: move the plug by a point and the rope arrives somewhere the plug
    /// no longer is. Absolute points mean the two ends are the same two numbers
    /// in both places.
    static let box = CGSize(width: 340, height: 132)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When this view first appeared, which is where the loop starts.
    ///
    /// It ran off the wall clock, and on a screen shown exactly once that is a
    /// coin toss: roughly a fifth of first launches opened on the sleeping
    /// frame, so the first thing a new user saw was a dark laptop and a plug
    /// hanging out of its socket — the end of the story, told first. Anchored
    /// here, everybody gets it in order: working, then stopping, then let go.
    @State private var began = Date()

    var body: some View {
        Group {
            if reduceMotion {
                // The middle of the working half: the state the sentence under
                // it describes, held still.
                scene(at: 2)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                    scene(
                        at: timeline.date.timeIntervalSince(began)
                            .truncatingRemainder(dividingBy: Self.loop))
                }
            }
        }
        .frame(width: Self.box.width, height: Self.box.height)
        .accessibilityElement()
        // The label describes what happens, not how it is drawn. The plug and
        // the rope are this picture's way of saying "held", and a reader who
        // is being read to does not need the metaphor — which is also why this
        // string is unchanged by the redraw, and its six translations stand.
        .accessibilityLabel(
            "An agent works, Belay holds the Mac awake, and the Mac sleeps once the work stops")
    }

    /// How hard the agent is working: 1 through the working half, down to 0
    /// while it winds down, and back up again before the loop repeats.
    ///
    /// That last ramp is the whole reason the loop is nine seconds and not
    /// eight. Without it the wrap put the rope from a full belly to dead
    /// straight in one frame, on the first animation anybody ever sees.
    ///
    /// `nonisolated` and internal so a test can walk the seam: this and
    /// `asleep` both have to arrive back where they started, and neither is a
    /// function of anything but the clock, so neither needs the main actor to
    /// answer.
    nonisolated static func working(at time: Double) -> Double {
        if time < 3.6 { return 1 }
        if time < 4.2 { return 1 - (time - 3.6) / 0.6 }
        if time < 8.1 { return 0 }
        // Clamped: the division overshoots one by a rounding error at the very
        // end of the loop, and this number is read as an opacity and as a
        // fraction of a distance, where over-one is not a no-op.
        return min(1, (time - 8.1) / 0.9)
    }

    /// How far the Mac has gone to sleep. Lags the agent by the grace period,
    /// which is the part people do not expect and the part worth showing, and
    /// wakes again as the next turn of work starts.
    ///
    /// The lag was six tenths of a second and it showed nothing: the rope had
    /// barely finished falling before the screen went dark, so the pause that
    /// is the entire point of the product passed as a rendering delay. It is
    /// now a second and seven tenths, held deliberately, and it is the stretch
    /// where the work has stopped and the plug is still in.
    nonisolated static func asleep(at time: Double) -> Double {
        if time < 5.9 { return 0 }
        if time < 6.7 { return (time - 5.9) / 0.8 }
        if time < 8.1 { return 1 }
        return max(0, 1 - (time - 8.1) / 0.7)
    }

    /// Where everything sits in `box`. Named rather than inline because the
    /// rope's ends have to agree with the things they are tied to.
    enum Place {
        static let screen = CGRect(x: 30, y: 30, width: 118, height: 72)
        static let deck = CGSize(width: 142, height: 8)
        /// The mark, and how big it is drawn.
        static let anchor = CGPoint(x: 244, y: 30)
        static let anchorSize: CGFloat = 36
        static let socket = CGPoint(x: 292, y: 105)
        /// Seated deep enough that the body meets the socket's top edge and
        /// the prongs are inside it. Four points higher and the plug read as
        /// hovering above the socket rather than being in it.
        static let plugSeated = CGPoint(x: 292, y: 92)
        static let plugLifted = CGPoint(x: 292, y: 61)
        /// Where the rope leaves the laptop, and the two points on the mark it
        /// passes over. Off the mark's own centre, so the rope reads as running
        /// across it rather than disappearing behind it.
        static let tieOff = CGPoint(x: 146, y: 36)
        static let overLeft = CGPoint(x: 231, y: 27)
        static let overRight = CGPoint(x: 256, y: 38)
    }

    /// Three states, told apart without a caption:
    ///   lines running, plug in, rope taut — an agent is working
    ///   lines stopped, plug still in      — Belay is still holding
    ///   plug lifted out, screen dark      — let go, and the Mac is asleep
    ///
    /// Slack says whether the agent is working; colour and the plug say whether
    /// Belay is still holding. Driving both from the same number was the
    /// picture telling a lie about the product: the rope went dead the instant
    /// the agent stopped, when in fact that is the moment Belay carries on
    /// holding and the grace period begins.
    private func scene(at time: Double) -> some View {
        let live = Self.working(at: time)
        let sleep = Self.asleep(at: time)
        let held = 1 - sleep
        // The mark breathes, a point and a half either way. The rope is tied to
        // the same number so it moves with it instead of hanging off a point
        // the mark has drifted away from.
        let bob = sin(time * 1.15) * 1.5
        let plug = CGPoint(
            x: Place.plugSeated.x,
            y: Place.plugSeated.y + (Place.plugLifted.y - Place.plugSeated.y) * sleep)

        return ZStack(alignment: .topLeading) {
            Laptop(lit: held, working: live, time: time)
                .frame(width: Place.deck.width, height: Place.screen.height + Place.deck.height)
                .position(
                    x: Place.screen.midX,
                    y: Place.screen.midY + Place.deck.height / 2)

            Bolts(intensity: held, time: time)
                .position(x: Place.socket.x + 24, y: Place.socket.y - 6)

            // Under the mark and over the plug: the rope leaves the laptop,
            // runs across the mark and carries the plug on its other end.
            rope(
                from: Place.tieOff,
                to: shifted(Place.overLeft, by: bob),
                sag: 16 * (1 - live),
                held: held)
            rope(
                from: shifted(Place.overRight, by: bob),
                to: CGPoint(x: plug.x, y: plug.y - 8),
                sag: 3,
                held: held)

            Plug()
                .position(plug)

            // After the plug, not before it: the socket has to cover the
            // prongs, or a seated plug reads as a plug resting on top of one.
            Socket()
                .position(Place.socket)

            // Last, so both lengths of rope run behind the mark rather than
            // stopping short of it.
            Image(nsImage: BelayGlyph.image(.alwaysOn, size: Place.anchorSize))
                .renderingMode(.template)
                .foregroundStyle(.tint)
                .position(shifted(Place.anchor, by: bob))
        }
        .frame(width: Self.box.width, height: Self.box.height)
    }

    private func shifted(_ point: CGPoint, by amount: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: point.y + amount)
    }

    /// Two strokes rather than one interpolated colour: a grey rope underneath
    /// that is always there, and the accent laid over it by how much Belay is
    /// holding. Fading a single accent stroke towards nothing made the rope
    /// vanish while the Mac slept, and a rope that disappears when it is let go
    /// is not a rope.
    private func rope(from: CGPoint, to: CGPoint, sag: CGFloat, held: Double) -> some View {
        let line = StrokeStyle(lineWidth: 2.5, lineCap: .round)
        return ZStack {
            Rope(from: from, to: to, sag: sag).stroke(Color.secondary.opacity(0.4), style: line)
            Rope(from: from, to: to, sag: sag).stroke(Color.accentColor.opacity(held), style: line)
        }
    }
}
