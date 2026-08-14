import SwiftUI

/// The first thing anyone sees: what Belay does, shown rather than described.
///
/// A laptop with work running on it, Belay's mark beside it with the agents in
/// orbit, a charge arcing at the machine while it is being held, and the person
/// who owns it out on a trampoline. The agents finish and pop one at a time; the
/// mark blinks; the screen goes dark under a moon. The person keeps bouncing,
/// because that was the point.
///
/// Shown instead of a third paragraph because the product is a behaviour over
/// time, and a behaviour over time is the one thing prose is worst at. The loop
/// is twelve seconds and repeats, so nobody has to catch the beginning.
struct OnboardingScene: View {
    /// One pass: work, agents finishing, sleep, and round again.
    nonisolated static let loop: Double = 12

    /// Everything is placed by hand against this box rather than stacked. A
    /// stack lays itself out, and a picture with an orbit in it cannot afford
    /// that: move the mark by a point and the ring is no longer around it.
    ///
    /// Narrowed when the trampoline left: a box kept at the old width put the
    /// machine in its left third and left a third of the panel empty.
    nonisolated static let box = CGSize(width: 280, height: 150)

    /// The middle of the machine, and the middle of the picture.
    ///
    /// Centring the group instead of the machine is what was wrong before. The
    /// orbit reaches further right than the charge reaches left, so balancing
    /// the two pushed the machine off to the left of a window whose heading,
    /// buttons and lockup are all measured against the middle. The subject sits
    /// in the middle and the two loose things are allowed to hang off it.
    nonisolated static let machine = CGPoint(x: box.width / 2, y: 94)

    /// The mark, and the charge, as offsets from the machine. Held here rather
    /// than as absolute points so that moving the machine moves the picture
    /// with it instead of taking it apart.
    nonisolated static let markAt = CGSize(width: 72, height: -40)
    nonisolated static let chargeAt = CGSize(width: -58, height: -48)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When this view appeared, which is where the loop starts. Off the wall
    /// clock it was a coin toss which frame a first launch opened on.
    @State private var began = Date()

    var body: some View {
        Group {
            if reduceMotion {
                Self.still(at: 2)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                    Self.still(
                        at: timeline.date.timeIntervalSince(began)
                            .truncatingRemainder(dividingBy: Self.loop))
                }
                .task { await soundtrack() }
            }
        }
        .frame(width: Self.box.width, height: Self.box.height)
        .accessibilityElement()
        .accessibilityLabel(
            "An agent works, Belay holds the Mac awake, and the Mac sleeps once the work stops")
    }

    // MARK: - The one pass that makes a noise

    /// What is heard, and when. Four agents finishing, the Mac letting go, and
    /// the Mac coming back.
    ///
    /// Gated the same way every other sound in the app is — the system's
    /// interface-sounds preference first, then Belay's own switch — because a
    /// welcome screen is the worst possible place to be the exception.
    private static var cues: [(at: Double, sound: Feedback.Sound)] {
        (0..<4).map { (at: popTime($0), sound: Feedback.Sound.agentPop) }
            + [(at: 8.35, sound: .driftingOff), (at: 10.8, sound: .wakingUp)]
    }

    /// Walks the cues in order, sleeping the gap between each, and goes round
    /// with the picture. Cancelled with the view, so a window closed mid-pass
    /// makes no noise afterwards.
    private func soundtrack() async {
        while !Task.isCancelled {
            var played = 0.0
            for cue in Self.cues {
                try? await Task.sleep(for: .seconds(cue.at - played))
                if Task.isCancelled { return }
                Feedback.play(cue.sound)
                played = cue.at
            }
            try? await Task.sleep(for: .seconds(Self.loop - played))
        }
    }

    // MARK: - The clock
    //
    // Every moving thing below is one of these functions wearing a different
    // coat. They are `nonisolated` and internal so the tests can walk them:
    // none is a function of anything but the time, so none needs the main actor.

    /// How hard the agent is working. Down as the last sessions end, back up as
    /// the loop comes round.
    nonisolated static func working(at time: Double) -> Double {
        if time < 5.0 { return 1 }
        if time < 5.4 { return 1 - (time - 5.0) / 0.4 }
        if time < 11.2 { return 0 }
        return min(1, (time - 11.2) / 0.8)
    }

    /// How far the Mac has gone to sleep. Lags the work by the grace period,
    /// which is the part people do not expect and the part worth showing.
    /// A crossfade rather than a dissolve: the work and the moon are two states
    /// of one screen, and a long ramp between them shows a third that is
    /// neither. Just over a third of a second each way, which is about as fast
    /// as a change of state can be and still be seen to happen.
    nonisolated static func asleep(at time: Double) -> Double {
        if time < 8.3 { return 0 }
        if time < 8.65 { return (time - 8.3) / 0.35 }
        if time < 10.8 { return 1 }
        return max(0, 1 - (time - 10.8) / 0.35)
    }

    /// How far gone an agent is: nought while it runs, one once it has popped.
    /// They go one at a time, in order, because four bubbles bursting together
    /// is a glitch and four in a row is a queue emptying.
    nonisolated static func popped(_ index: Int, at time: Double) -> Double {
        let start = popTime(index)
        if time < start { return 0 }
        if time < 10.9 { return min(1, (time - start) / 0.45) }
        // Past this the arrival has the chip and the pop must let go of it, or
        // the two fight over the same scale.
        return 0
    }

    /// When an agent pops, and when it comes back.
    nonisolated static func popTime(_ index: Int) -> Double { 5.0 + Double(index) * 0.55 }
    nonisolated static func birthTime(_ index: Int) -> Double { 10.9 + Double(index) * 0.22 }

    /// How long an agent is on the ring across one pass: from the top of the
    /// loop to its pop, plus from its return to the end.
    nonisolated static func aliveSpan(_ index: Int) -> Double {
        popTime(index) + (loop - birthTime(index))
    }

    /// How much of that it has used by now. Frozen while it is away, which is
    /// what puts it back exactly where it left.
    nonisolated static func aliveTime(_ index: Int, at time: Double) -> Double {
        if time < popTime(index) { return time }
        if time < birthTime(index) { return popTime(index) }
        return popTime(index) + (time - birthTime(index))
    }

    /// How far an agent has arrived at the top of a pass. They come back one
    /// after another rather than all at once, and each overshoots and settles,
    /// so they land rather than switch on.
    nonisolated static func arrived(_ index: Int, at time: Double) -> Double {
        if time < 10.9 { return 1 }
        let start = birthTime(index)
        if time < start { return 0 }
        return min(1, (time - start) / 0.6)
    }

    /// The mark's own light: full while it holds, gone once it sleeps. This is
    /// the halo only. The tile itself never fades.
    nonisolated static func glow(at time: Double) -> Double {
        1 - asleep(at: time)
    }

    /// Two beats as Belay lets go. It is the one moment the mark is allowed to
    /// go dim, and it comes back to full before the screen does.
    nonisolated static func blink(at time: Double) -> Double {
        if time < 7.4 { return 1 }
        if time < 8.3 {
            let beat = (time - 7.4) / 0.45
            return beat.truncatingRemainder(dividingBy: 1) < 0.5 ? 0.3 : 1
        }
        // And then it stays down. The blink is Belay letting go, so the mark
        // going back to blue while the Mac is dark would say it had taken hold
        // of nothing. It comes back with the machine, on the same ramp, which
        // is what makes the two read as one event.
        if time < 10.8 { return 0 }
        return min(1, (time - 10.8) / 0.35)
    }

    /// One half of the ring, placed. Both halves take the same frame, so an
    /// agent handed from one to the other does not jump.
    @MainActor private static func orbit(_ half: AgentOrbit.Half, at time: Double) -> some View {
        AgentOrbit(
            half: half,
            popped: (0..<4).map { popped($0, at: time) },
            arrived: (0..<4).map { arrived($0, at: time) },
            glow: glow(at: time),
            blink: blink(at: time),
            time: time
        )
        // Sized so the ring clears the top of the box: any wider and the
        // agents at twelve o'clock are cut in half by the edge of the panel.
        .frame(width: 112, height: 112)
        // On the machine's top right corner, so the mark reads as sitting on it
        // rather than floating beside it.
        .position(x: machine.x + markAt.width, y: machine.y + markAt.height)
    }

    /// One frame of the scene. Static so a test can render it without a window.
    @MainActor static func still(at time: Double) -> some View {
        let live = working(at: time)
        let sleep = asleep(at: time)
        let held = 1 - sleep
        return ZStack(alignment: .topLeading) {
            // The far half of the orbit first, so the machine covers it.
            orbit(.behind, at: time)

            Laptop(lit: held, working: live, time: time)
                // Height from the artwork's own proportion: the display is
                // placed inside it by fractions, so a guessed height would put
                // our screen through the bezel.
                .frame(width: Laptop.width, height: Laptop.width / Laptop.aspect)
                .position(machine)

            // Rising off the top left corner of the screen: the lowest bolt is
            // on the glass and the other two are already above the machine, so
            // the three read as leaving it rather than as sitting on it.
            ChargeBolts(charge: held, sleeping: sleep, time: time)
                .frame(width: 30, height: 58)
                .position(x: machine.x + chargeAt.width, y: machine.y + chargeAt.height)

            orbit(.inFront, at: time)
        }
        .frame(width: box.width, height: box.height)
    }
}
