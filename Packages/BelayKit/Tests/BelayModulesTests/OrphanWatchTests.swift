import Foundation
import Testing

@testable import BelayModules

@Suite("Orphan ledger")
struct OrphanLedgerTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    private let rules = OrphanRules()

    private func process(
        _ pid: pid_t,
        parent: pid_t = 1,
        _ name: String,
        started: TimeInterval = 0,
        cpu: Double? = nil
    ) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid, parent: parent, name: name, startedAt: base.addingTimeInterval(started),
            cpuSeconds: cpu)
    }

    private func look(
        _ ledger: inout OrphanLedger,
        _ table: [ProcessSnapshot],
        at seconds: TimeInterval = 0,
        working: Set<OrphanAgent> = [],
        rules: OrphanRules? = nil
    ) -> OrphanFindings {
        ledger.observe(
            table: table, candidates: OrphanRoots.resolve(table: table, registry: [:]),
            workingAgents: working, rules: rules ?? self.rules,
            now: base.addingTimeInterval(seconds))
    }

    private var session: [ProcessSnapshot] {
        [
            process(100, "claude"), process(101, parent: 100, "zsh"),
            process(102, parent: 101, "node", started: 5)
        ]
    }

    @Test("While the agent lives nothing is left behind, and its tree is remembered")
    func alive() {
        var ledger = OrphanLedger()
        let found = look(&ledger, session)
        #expect(found.leftBehind.isEmpty)
        #expect(found.roots == 1)
        #expect(found.tracked == 2)
    }

    @Test("When the agent exits, what it started and still runs is left behind")
    func rootExits() {
        var ledger = OrphanLedger()
        _ = look(&ledger, session)
        let after = [process(102, parent: 1, "node", started: 5), process(300, "Finder")]
        let found = look(&ledger, after, at: 60)
        #expect(found.leftBehind == [LeftBehind(pid: 102, name: "node", startedAt: base + 5, agent: .claude)])
        #expect(found.roots == 0)
    }

    @Test("Codex is followed the same way, and named as itself")
    func codex() {
        var ledger = OrphanLedger()
        _ = look(&ledger, [process(200, "codex"), process(201, parent: 200, "python3")])
        let found = look(&ledger, [process(201, "python3")], at: 60)
        #expect(found.leftBehind.map(\.agent) == [.codex])
    }

    @Test("A pid handed to a different process is not the one that was remembered")
    func childPidReused() {
        var ledger = OrphanLedger()
        _ = look(&ledger, session)
        let stranger = [process(102, "Safari", started: 9_000)]
        #expect(look(&ledger, stranger, at: 60).leftBehind.isEmpty)
    }

    @Test("A child that exits leaves the list")
    func childExits() {
        var ledger = OrphanLedger()
        _ = look(&ledger, session)
        #expect(look(&ledger, [process(102, "node", started: 5)], at: 60).leftBehind.count == 1)
        #expect(look(&ledger, [], at: 120).leftBehind.isEmpty)
    }

    @Test("An agent whose pid was reused by something else is gone")
    func rootPidReused() {
        var ledger = OrphanLedger()
        _ = look(&ledger, session)
        let table = [
            process(100, "Mail", started: 7_000),
            process(102, "node", started: 5)
        ]
        let found = look(&ledger, table, at: 60)
        #expect(found.leftBehind.map(\.pid) == [102])
        #expect(found.roots == 0)
    }

    @Test("A new agent on a reused pid is a new root, not the old one")
    func rootPidReusedByAgent() {
        var ledger = OrphanLedger()
        _ = look(&ledger, session)
        let table = [
            process(100, "claude", started: 7_000), process(102, "node", started: 5)
        ]
        let found = look(&ledger, table, at: 60)
        #expect(found.leftBehind.map(\.pid) == [102])
        #expect(found.roots == 1)
    }

    @Test("What was never seen under a live agent is not claimed")
    func neverSeen() {
        var ledger = OrphanLedger()
        _ = look(&ledger, [process(100, "claude")])
        let found = look(&ledger, [process(102, "node", started: 5)], at: 60)
        #expect(found.leftBehind.isEmpty)
    }

    @Test("A process re-parented to launchd while its agent lives is still the agent's")
    func reparented() {
        var ledger = OrphanLedger()
        _ = look(&ledger, session)
        let reparented = [process(100, "claude"), process(102, parent: 1, "node", started: 5)]
        #expect(look(&ledger, reparented, at: 60).leftBehind.isEmpty)
        #expect(look(&ledger, [process(102, "node", started: 5)], at: 120).leftBehind.count == 1)
    }

    @Test("Another agent below the first is not orphaned when the first exits")
    func nestedAgent() {
        var ledger = OrphanLedger()
        let table = session + [process(110, parent: 101, "claude", started: 20)]
        _ = look(&ledger, table)
        let after = [
            process(110, "claude", started: 20), process(102, "node", started: 5)
        ]
        #expect(look(&ledger, after, at: 60).leftBehind.map(\.pid) == [102])
    }

    @Test("The walk stops eight levels down")
    func depth() {
        var ledger = OrphanLedger()
        var table = [process(100, "claude")]
        for level in 1...10 {
            table.append(process(100 + pid_t(level), parent: 99 + pid_t(level), "sh"))
        }
        let found = look(&ledger, table)
        #expect(found.tracked == 8)
    }

    @Test("Ignored names are neither listed nor counted")
    func ignored() {
        var ledger = OrphanLedger()
        _ = look(&ledger, session)
        var ignoring = rules
        ignoring.ignore("node")
        let found = look(&ledger, [process(102, "node", started: 5)], at: 60, rules: ignoring)
        #expect(found.leftBehind.isEmpty)
        #expect(look(&ledger, [process(102, "node", started: 5)], at: 70).leftBehind.count == 1)
    }

    @Test("The oldest is listed first")
    func order() {
        var ledger = OrphanLedger()
        let table = [
            process(100, "claude"), process(103, parent: 100, "vite", started: 50),
            process(102, parent: 100, "node", started: 5)
        ]
        _ = look(&ledger, table)
        let found = look(&ledger, Array(table.dropFirst()), at: 60)
        #expect(found.leftBehind.map(\.name) == ["node", "vite"])
    }
}
