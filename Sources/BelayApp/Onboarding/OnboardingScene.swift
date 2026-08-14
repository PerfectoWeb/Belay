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
    nonisolated static let box = CGSize(width: 360, height: 150)

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
            }
        }
        .frame(width: Self.box.width, height: Self.box.height)
        .accessibilityElement()
        .accessibilityLabel(
            "An agent works, Belay holds the Mac awake, and the Mac sleeps once the work stops")
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
    nonisolated static func asleep(at time: Double) -> Double {
        if time < 8.3 { return 0 }
        if time < 9.2 { return (time - 8.3) / 0.9 }
        if time < 10.8 { return 1 }
        return max(0, 1 - (time - 10.8) / 0.8)
    }

    /// How far gone an agent is: nought while it runs, one once it has popped.
    /// They go one at a time, in order, because four bubbles bursting together
    /// is a glitch and four in a row is a queue emptying.
    nonisolated static func popped(_ index: Int, at time: Double) -> Double {
        let start = 5.0 + Double(index) * 0.55
        if time < start { return time > 11.0 ? max(0, 1 - (time - 11.0) / 0.6) : 0 }
        return min(1, (time - start) / 0.5)
    }

    /// The mark's own light. Steady while it holds, two blinks as it lets go,
    /// then down with the screen.
    nonisolated static func glow(at time: Double) -> Double {
        let dark = 1 - asleep(at: time)
        guard time >= 7.4, time < 8.3 else { return dark }
        // Two on-off beats across nine tenths of a second.
        let beat = (time - 7.4) / 0.45
        return (beat.truncatingRemainder(dividingBy: 1) < 0.5 ? 0.15 : 1) * dark
    }

    /// One frame of the scene. Static so a test can render it without a window.
    @MainActor static func still(at time: Double) -> some View {
        let live = working(at: time)
        let sleep = asleep(at: time)
        let held = 1 - sleep
        return ZStack(alignment: .topLeading) {
            Laptop(lit: held, working: live, time: time)
                .frame(width: 150, height: 86)
                .position(x: 96, y: 92)

            ChargeBolts(charge: held, time: time)
                .frame(width: 26, height: 58)
                .position(x: 26, y: 76)

            AgentOrbit(
                popped: (0..<4).map { popped($0, at: time) },
                glow: glow(at: time),
                time: time
            )
            .frame(width: 150, height: 116)
            .position(x: 176, y: 52)

            Bouncer(resting: sleep, time: time)
                .frame(width: 108, height: 140)
                .position(x: 296, y: 74)
        }
        .frame(width: box.width, height: box.height)
    }
}
