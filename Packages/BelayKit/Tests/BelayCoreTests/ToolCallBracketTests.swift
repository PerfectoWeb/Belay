import Foundation
import Testing

@testable import BelayCore

/// R6, the risk the whole hook tier exists to close: a tool call that runs for
/// half an hour writes nothing, so every inferred reading calls the turn over.
@Suite("Open tool calls")
struct ToolCallBracketTests {
    private func coordinator(_ clock: TestClock) -> ActivityCoordinator {
        ActivityCoordinator(clock: clock, policy: .default)
    }

    @Test("A tool call still running outranks the file watcher long after the hook")
    func openBracketOutlivesFreshness() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(60)
        // What the transcript says while a test suite runs: nothing new, so the
        // sweep calls it finished.
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        clock.advance(30 * 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
        #expect(await coordinator.snapshot.state.holdsAssertion)
    }

    @Test("The tool returning hands the session back to the file watcher")
    func closedBracketReleases() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(30 * 60)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .exact, toolCall: .returned))

        clock.advance(1)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .idle)
    }

    /// Hooks are fire-and-forget posts stamped on receipt, so between
    /// back-to-back tool calls the first call's return can land milliseconds
    /// *after* the second call's open — with the newer timestamp. That return
    /// must not wipe the bracket protecting the new call.
    @Test("A reordered return does not wipe the bracket of the next call")
    func reorderedReturnSparesTheNewBracket() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        // Tool 2 opens; tool 1's return arrives just behind it.
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(0.05)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .returned))
        clock.advance(60)
        // Tool 2 is a long build: the transcript goes quiet and the sweep
        // calls the turn finished.
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        clock.advance(30 * 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
        #expect(await coordinator.snapshot.state.holdsAssertion)
    }

    /// The grace is for returns only. A Stop landing right after an open is
    /// not a race — it is the turn ending — and must still close the bracket.
    @Test("Stop closes the bracket even inside the grace window")
    func stopClosesInsideGrace() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(0.5)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .exact, toolCall: .closed))
        clock.advance(60)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        // Past the freshness window, short of the session TTL: the bracket is
        // the only thing that could keep this working, and it must be gone.
        clock.advance(6 * 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .idle)
    }

    /// An agent killed between the two hooks fires neither, and a bracket with
    /// nobody left to close it must not hold the Mac for the awake limit.
    @Test("A bracket nobody closed expires on its own budget")
    func lostBracketExpires() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(60)
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        clock.advance(AwakePolicy.openToolCallBudget + 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] != .working)
    }

    /// The session TTL is ten minutes and a tool call emits nothing, so without
    /// the exemption the ledger evicts the session the bracket is protecting.
    @Test("A bracketed session is not evicted while it runs")
    func bracketSurvivesSessionTTL() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)

        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        clock.advance(AwakePolicy.default.sessionTTL + 5 * 60)
        await coordinator.evaluate()

        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
    }

    /// A hook that arrives out of order is normal; one that closes a bracket a
    /// newer hook already opened would sleep the Mac mid-tool.
    @Test("A late close does not undo a newer open")
    func lateCloseIgnored() async {
        let clock = TestClock()
        let coordinator = coordinator(clock)
        let stale = clock.now

        clock.advance(10)
        await coordinator.ingest(.make(.working, at: clock.now, confidence: .exact, toolCall: .opened))
        await coordinator.ingest(.make(.idle, at: stale, confidence: .exact, toolCall: .closed))
        await coordinator.ingest(.make(.idle, at: clock.now, confidence: .inferred))

        clock.advance(20 * 60)
        await coordinator.evaluate()
        #expect(await coordinator.snapshot.activities[SessionID("s1")] == .working)
    }
}
