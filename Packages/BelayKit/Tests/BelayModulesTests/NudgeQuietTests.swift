import Foundation
import Testing

@testable import BelayModules

/// The quiet nudge: a session that was at work and is gone without a finish.
@Suite("Nudge watch going quiet")
struct NudgeQuietTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let rules = NudgeRules()

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func session(_ activity: NudgeSession.Activity) -> NudgeSession {
        NudgeSession(id: "a", activity: activity)
    }

    private func session(
        _ id: String,
        _ activity: NudgeSession.Activity,
        parent: String? = nil
    ) -> NudgeSession {
        NudgeSession(id: id, activity: activity, parent: parent)
    }

    private func run(
        _ watch: inout NudgeWatch,
        _ sessions: [NudgeSession],
        at seconds: TimeInterval,
        rules: NudgeRules? = nil
    ) -> [NudgeEvent] {
        watch.advance(sessions, now: at(seconds), rules: rules ?? self.rules)
    }

    @Test("A working session that vanishes went quiet")
    func quiet() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.working)], at: 0)
        #expect(run(&watch, [], at: 60) == [.quiet(session: "a")])
        #expect(run(&watch, [], at: 70).isEmpty)
    }

    /// Found live: a session closed eight seconds after it was resumed.
    @Test("A session that vanishes before the minimum run is not quiet")
    func shortRunNotQuiet() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.working)], at: 0)
        #expect(run(&watch, [], at: 10).isEmpty)
    }

    @Test("A session that finished and then went is not quiet")
    func finishedThenGone() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.working)], at: 0)
        _ = run(&watch, [session(.other)], at: 5)
        #expect(run(&watch, [], at: 10).isEmpty)
    }

    @Test("A waiting session that vanishes says nothing and stops counting")
    func waitingThenVanished() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.waiting)], at: 0)
        #expect(run(&watch, [], at: 10).isEmpty)
        #expect(watch.waitingCount == 0)
    }

    @Test("A parent gone while its subagents work is not silence")
    func parentGoneChildrenWork() {
        var watch = NudgeWatch()
        _ = run(&watch, [session("p", .working), session("c", .working, parent: "p")], at: 0)
        #expect(run(&watch, [session("c", .working, parent: "p")], at: 10).isEmpty)
    }

    @Test("A subagent that vanishes is not the person's session going quiet")
    func subagentGone() {
        var watch = NudgeWatch()
        let parent = session("p", .working)
        _ = run(&watch, [parent, session("c", .working, parent: "p")], at: 0)
        #expect(run(&watch, [parent], at: 10).isEmpty)
    }

    @Test("Sessions are told apart")
    func twoSessions() {
        var watch = NudgeWatch()
        _ = run(&watch, [session("a", .working), session("b", .working)], at: 0)
        let events = run(&watch, [session("a", .other), session("b", .working)], at: 60)
        #expect(events == [.finished(session: "a", ran: 60)])
    }

    /// Found live: Codex resumed a thread from a week before under a new id,
    /// and the old id, heard once from the prompt hook and never again, was
    /// evicted ten minutes later as a session that went quiet.
    @Test("A session only a hook ever saw is not quiet when it vanishes")
    func hookOnlySessionNotQuiet() {
        var watch = NudgeWatch()
        _ = run(&watch, [NudgeSession(id: "a", activity: .working, isEvidenced: false)], at: 0)
        _ = run(&watch, [NudgeSession(id: "a", activity: .working, isEvidenced: false)], at: 300)
        #expect(run(&watch, [], at: 600).isEmpty)
    }
}
