import Foundation
import Testing

@testable import BelayModules

@Suite("Nudge watch")
struct NudgeWatchTests {
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

    // MARK: finishing

    @Test("A run that lasted the minimum finishes, and a shorter one does not")
    func finishThreshold() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.working)], at: 0)
        #expect(run(&watch, [session(.other)], at: 30) == [.finished(session: "a", ran: 30)])

        _ = run(&watch, [session(.working)], at: 100)
        #expect(run(&watch, [session(.other)], at: 129.9).isEmpty)
    }

    @Test("The minimum is the user's to choose")
    func finishFollowsRules() {
        var watch = NudgeWatch()
        let patient = NudgeRules(minimumRunSeconds: 300)
        _ = run(&watch, [session(.working)], at: 0, rules: patient)
        #expect(run(&watch, [session(.other)], at: 299, rules: patient).isEmpty)
        _ = run(&watch, [session(.working)], at: 400, rules: patient)
        let events = run(&watch, [session(.other)], at: 700, rules: patient)
        #expect(events == [.finished(session: "a", ran: 300)])
    }

    @Test("Time spent waiting is not time worked")
    func waitingIsNotWork() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.working)], at: 0)
        _ = run(&watch, [session(.waiting)], at: 20)
        _ = run(&watch, [session(.working)], at: 620)
        // 20 s before the wait, 15 s after it: 35 s of work across 635 s.
        #expect(run(&watch, [session(.other)], at: 635) == [.finished(session: "a", ran: 35)])
    }

    @Test("A run that stops to wait and never resumes did not finish")
    func waitingThenGone() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.working)], at: 0)
        _ = run(&watch, [session(.waiting)], at: 60)
        let events = run(&watch, [session(.other)], at: 90)
        #expect(events == [.resumed(session: "a")])
    }

    @Test("Each run is counted on its own")
    func runsDoNotAdd() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.working)], at: 0)
        _ = run(&watch, [session(.other)], at: 20)
        _ = run(&watch, [session(.working)], at: 100)
        #expect(run(&watch, [session(.other)], at: 115).isEmpty)
    }

    @Test("A subagent finishing is not the person's run ending")
    func subagentsStaySilent() {
        var watch = NudgeWatch()
        let parent = session("p", .working)
        _ = run(&watch, [parent, session("c", .working, parent: "p")], at: 0)
        let events = run(&watch, [parent, session("c", .other, parent: "p")], at: 100)
        #expect(events.isEmpty)
    }

    // MARK: waiting and reminders

    @Test("Starting to wait is said once")
    func waitingOnce() {
        var watch = NudgeWatch()
        #expect(run(&watch, [session(.working)], at: 0).isEmpty)
        #expect(run(&watch, [session(.waiting)], at: 5) == [.waiting(session: "a")])
        #expect(run(&watch, [session(.waiting)], at: 10).isEmpty)
        #expect(watch.waitingCount == 1)
    }

    @Test("A subagent that waits is said, because the run is stuck on it")
    func subagentWaiting() {
        var watch = NudgeWatch()
        let events = run(&watch, [session("p", .working), session("c", .waiting, parent: "p")], at: 0)
        #expect(events == [.waiting(session: "c")])
    }

    @Test("The first reminder comes after the interval, not before")
    func reminderThreshold() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.waiting)], at: 0)
        #expect(run(&watch, [session(.waiting)], at: 299).isEmpty)
        let events = run(&watch, [session(.waiting)], at: 300)
        #expect(events == [.reminder(session: "a", waited: 300, count: 1)])
    }

    @Test("Reminders repeat at the interval and stop at the cap")
    func reminderCadenceAndCap() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.waiting)], at: 0)
        var counts: [Int] = []
        for minute in 1...40 {
            let events = run(&watch, [session(.waiting)], at: TimeInterval(minute * 60))
            for case .reminder(_, _, let count) in events {
                counts.append(count)
                #expect(minute.isMultiple(of: 5))
            }
        }
        #expect(counts == [1, 2, 3])
    }

    @Test("The interval and the cap are the user's to choose")
    func reminderFollowsRules() {
        var watch = NudgeWatch()
        let brisk = NudgeRules(repeatAfterMinutes: 2, repeatAtMost: 1)
        _ = run(&watch, [session(.waiting)], at: 0, rules: brisk)
        #expect(run(&watch, [session(.waiting)], at: 119, rules: brisk).isEmpty)
        #expect(run(&watch, [session(.waiting)], at: 120, rules: brisk).count == 1)
        #expect(run(&watch, [session(.waiting)], at: 600, rules: brisk).isEmpty)
    }

    @Test("Never means never")
    func reminderOff() {
        var watch = NudgeWatch()
        let silent = NudgeRules(repeatAfterMinutes: 0)
        _ = run(&watch, [session(.waiting)], at: 0, rules: silent)
        #expect(run(&watch, [session(.waiting)], at: 86_400, rules: silent).isEmpty)
    }

    @Test("A long gap yields one reminder, then the cadence carries on from it")
    func reminderAfterSleep() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.waiting)], at: 0)
        let events = run(&watch, [session(.waiting)], at: 3_600)
        #expect(events == [.reminder(session: "a", waited: 3_600, count: 1)])
        #expect(run(&watch, [session(.waiting)], at: 3_601).isEmpty)
        #expect(run(&watch, [session(.waiting)], at: 3_900).count == 1)
    }

    @Test("Resuming resets the count, and the next wait starts over")
    func resumeResets() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.waiting)], at: 0)
        _ = run(&watch, [session(.waiting)], at: 300)
        #expect(run(&watch, [session(.working)], at: 330) == [.resumed(session: "a")])
        #expect(watch.waitingCount == 0)

        #expect(run(&watch, [session(.waiting)], at: 400) == [.waiting(session: "a")])
        #expect(run(&watch, [session(.waiting)], at: 699).isEmpty)
        let events = run(&watch, [session(.waiting)], at: 700)
        #expect(events == [.reminder(session: "a", waited: 300, count: 1)])
    }

    @Test("Waiting sessions are counted per session")
    func waitingCount() {
        var watch = NudgeWatch()
        _ = run(&watch, [session("a", .waiting), session("b", .waiting), session("c", .working)], at: 0)
        #expect(watch.waitingCount == 2)
        _ = run(&watch, [session("a", .waiting), session("b", .other), session("c", .working)], at: 5)
        #expect(watch.waitingCount == 1)
    }

    // MARK: going quiet

    @Test("A working session that vanishes went quiet")
    func quiet() {
        var watch = NudgeWatch()
        _ = run(&watch, [session(.working)], at: 0)
        #expect(run(&watch, [], at: 10) == [.quiet(session: "a")])
        #expect(run(&watch, [], at: 20).isEmpty)
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
}
