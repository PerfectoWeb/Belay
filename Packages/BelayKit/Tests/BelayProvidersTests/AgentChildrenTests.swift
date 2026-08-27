import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

@Suite("Tier C: work that leaves no trace in the transcript", .serialized)
struct AgentChildrenTests {
    private let scratch = TranscriptScratch()

    private func provider() -> ClaudeCodeProvider {
        ClaudeCodeProvider(configuration: scratch.configuration, access: DirectFileAccess())
    }

    private func collector(on provider: ClaudeCodeProvider) async -> SignalCollector {
        let collector = SignalCollector()
        await collector.attach(to: await provider.signals)
        return collector
    }

    /// Risk R6, caught in the wild: a session whose last transcript record was
    /// `end_turn` still had a live `/bin/zsh` child — the build it had
    /// backgrounded and was waiting on. Declaring that idle lets the Mac sleep
    /// out from under a job that is still running. (What counts as "running" is
    /// now bounded by age; see `onlyRecentlyStartedChildrenCount`.)
    @Test("A quiet session with a recently started child keeps reporting work")
    func busyChildKeepsSessionAwake() async {
        let start = Date()
        let url = scratch.transcript(
            "waiting", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        scratch.processFile(pid: 9001, session: "waiting", cwd: "/Volumes/Work/Build")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)

        // The turn really did end: Tier A follows silently — an idle first
        // word is not news — and stays quiet.
        await provider.sweepForIdle(now: start.addingTimeInterval(600))
        #expect(await collector.settle().isEmpty)

        // The child is the only thing that knows the work continues.
        await provider.sweepForDeadProcesses(
            now: start.addingTimeInterval(610), isAlive: { _ in true }, busyPids: { _, _, _ in [9001] })
        #expect(await collector.wait(for: 1).map(\.activity) == [.working])
        await collector.stop()
    }

    /// The rule `docs/03` Tier C insists on, and the new signal must not break
    /// it: the agent merely being alive is not work. Only a child of it is.
    @Test("A live process with no children never reports work on its own")
    func liveProcessAloneIsNotWork() async {
        let start = Date()
        let url = scratch.transcript(
            "quiet", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        scratch.processFile(pid: 9002, session: "quiet", cwd: "/Volumes/Work/Quiet")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)
        await provider.sweepForIdle(now: start.addingTimeInterval(600))
        #expect(await collector.settle().isEmpty)

        for tick in 1...6 {
            await provider.sweepForDeadProcesses(
                now: start.addingTimeInterval(600 + Double(tick) * 15),
                isAlive: { _ in true }, busyPids: { _, _, _ in [] })
        }
        #expect(await collector.settle().isEmpty)
        await collector.stop()
    }

    /// A subagent belongs to its parent's process, but never appears in the pid
    /// sidecars Tier C reads — so when the main session is reaped, nothing else
    /// would ever end the child, and it heartbeats `.working` for the whole
    /// awaiting-assistant grace on a process that is already gone. Reaping the
    /// parent has to take its subagents with it.
    @Test("Reaping a dead main session ends its subagents too")
    func deadMainCascadesToSubagents() async {
        let start = Date()
        let main = scratch.transcript(
            "s1", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        scratch.processFile(pid: 9100, session: "s1", cwd: "/Volumes/Work/App")
        let sub = scratch.subagent(
            "agent-a1", of: "s1", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        let provider = self.provider()
        await provider.ingest(main, now: start)
        await provider.ingest(sub, now: start)
        #expect(await provider.watched[SessionID("s1")] != nil)
        #expect(await provider.watched[SessionID("agent-a1")]?.parent == SessionID("s1"))

        // The CLI dies: its pid reads as gone in the sidecar scan.
        await provider.sweepForDeadProcesses(
            now: start.addingTimeInterval(30), isAlive: { _ in false }, busyPids: { _, _, _ in [] })
        #expect(await provider.watched[SessionID("s1")] == nil, "the dead main was reaped")
        #expect(
            await provider.watched[SessionID("agent-a1")] == nil,
            "its subagent went with it, not left pinning the Mac for the full grace")
    }

    /// A crash leaves `sessions/<oldpid>.json` behind; resuming the same session
    /// writes `sessions/<newpid>.json` beside it. The dead sidecar must not end
    /// the session the live pid is keeping.
    @Test("A resumed session survives its crashed pid's leftover sidecar")
    func staleSidecarDoesNotEndALiveSession() async {
        let start = Date()
        let url = scratch.transcript(
            "resumed", lines: [TranscriptScratch.record("assistant", stop: "tool_use")])
        scratch.processFile(pid: 9200, session: "resumed", cwd: "/Volumes/Work/App")
        scratch.processFile(pid: 9300, session: "resumed", cwd: "/Volumes/Work/App")
        let provider = self.provider()
        await provider.ingest(url, now: start)
        #expect(await provider.watched[SessionID("resumed")] != nil)

        // Old pid dead, new pid alive: the session lives.
        await provider.sweepForDeadProcesses(
            now: start.addingTimeInterval(30),
            isAlive: { $0 == 9300 }, busyPids: { _, _, _ in [] })
        #expect(
            await provider.watched[SessionID("resumed")] != nil,
            "the live pid keeps the session; the crashed pid's leftover must not end it")

        // Both sidecars dead: now it genuinely ends.
        await provider.sweepForDeadProcesses(
            now: start.addingTimeInterval(60),
            isAlive: { _ in false }, busyPids: { _, _, _ in [] })
        #expect(await provider.watched[SessionID("resumed")] == nil)
    }

    /// A failed `sysctl` must mean "ask again later", never "nothing is running".
    @Test("An unreadable process table does not resurrect or end anything")
    func unreadableProcessTableIsIgnored() async {
        let start = Date()
        let url = scratch.transcript(
            "unknown", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        scratch.processFile(pid: 9003, session: "unknown", cwd: "/Volumes/Work/Unknown")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)
        await provider.sweepForIdle(now: start.addingTimeInterval(600))
        #expect(await collector.settle().isEmpty)

        await provider.sweepForDeadProcesses(
            now: start.addingTimeInterval(615), isAlive: { _ in true }, busyPids: { _, _, _ in nil })
        #expect(await collector.settle().isEmpty)
        await collector.stop()
    }

    /// The bound itself, against the real process table. Without it the second
    /// answer is the same as the first for as long as the child lives, which is
    /// how an MCP server or a backgrounded dev server pins the Mac awake next to
    /// an idle agent until the max-duration cap trips.
    @Test("Only recently started children count as work")
    func onlyRecentlyStartedChildrenCount() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer {
            child.terminate()
            child.waitUntilExit()
        }

        let now = Date()
        let me = getpid()
        #expect(AgentChildren.busy(among: [me], youngerThan: 60, now: now)?.contains(me) == true)
        // The same child, one horizon later: still alive, no longer evidence.
        #expect(AgentChildren.busy(among: [me], youngerThan: 45, now: now.addingTimeInterval(600)) == [])
    }

    /// The shape that actually occurs. Claude Code runs its Bash tool inside one
    /// long-lived shell, so the process doing the work is a grandchild and the
    /// direct-children-only probe saw an old shell and nothing else — the Mac
    /// slept ninety seconds into a half-hour test run.
    @Test("Work started deeper than one level still counts")
    func grandchildrenCount() throws {
        // A stand-in for the persistent tool shell: started long before the
        // work, and never restarted.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Backgrounded and waited on, so the shell has to fork rather than
        // exec `sleep` in its own place and leave one level where there
        // should be two.
        shell.arguments = ["-c", "/bin/sleep 30 & wait"]
        try shell.run()
        defer {
            shell.terminate()
            shell.waitUntilExit()
        }
        // Proof there is a second level at all: without it this test would
        // pass on the direct-children probe it exists to catch.
        var descendants = 0
        for _ in 0..<50 {
            descendants = AgentChildren.descendantCount(of: shell.processIdentifier)
            if descendants > 0 { break }
            usleep(20_000)
        }
        try #require(descendants > 0, "the shell forked; there is a second level to see")

        let me = getpid()
        let now = Date()
        // The shell is the only direct child and it is old news by this horizon;
        // everything young lives one level below it.
        #expect(AgentChildren.busy(among: [me], youngerThan: 60, now: now)?.contains(me) == true)
    }

    /// The wiring: the sweep has to hand the probe its own idle horizon and its
    /// own clock, or the bound above is computed against the wrong numbers. The
    /// probe answers "busy" only when given both, so a `.working` here is proof.
    @Test("The sweep bounds the child probe by inferredIdleAfter")
    func sweepPassesTheIdleHorizon() async {
        let start = Date()
        let url = scratch.transcript(
            "wired", lines: [TranscriptScratch.record("assistant", stop: "end_turn")])
        scratch.processFile(pid: 9004, session: "wired", cwd: "/Volumes/Work/Wired")
        let provider = self.provider()
        let collector = await self.collector(on: provider)
        await provider.ingest(url, now: start)
        await provider.sweepForIdle(now: start.addingTimeInterval(600))
        #expect(await collector.settle().isEmpty)

        let swept = start.addingTimeInterval(610)
        let horizon = scratch.configuration.inferredIdleAfter
        await provider.sweepForDeadProcesses(
            now: swept, isAlive: { _ in true },
            busyPids: { pids, maxAge, now in maxAge == horizon && now == swept ? pids : [] })
        #expect(await collector.wait(for: 1).map(\.activity) == [.working])
        await collector.stop()
    }
}
