import Foundation
import Testing

@testable import BelayModules

@Suite("Orphan ledger, running hot")
struct OrphanHotTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    /// One minute between looks, a process that uses `rate` cores, for `minutes`.
    private func run(
        rate: Double,
        minutes: Int,
        rules: OrphanRules = OrphanRules(),
        working: (Int) -> Set<OrphanAgent> = { _ in [] },
        readable: Bool = true,
        ledger: inout OrphanLedger
    ) -> OrphanFindings {
        var found = OrphanFindings()
        for minute in 0...minutes {
            let now = base.addingTimeInterval(Double(minute) * 60)
            let cpu = readable ? rate * Double(minute) * 60 : nil
            let table = [
                ProcessSnapshot(pid: 100, parent: 1, name: "claude", startedAt: base),
                ProcessSnapshot(
                    pid: 101, parent: 100, name: "node", startedAt: base, cpuSeconds: cpu)
            ]
            found = ledger.observe(
                table: table, candidates: [100: .claude], workingAgents: working(minute),
                rules: rules, now: now)
        }
        return found
    }

    @Test("Above the threshold for the whole window is hot")
    func above() {
        var ledger = OrphanLedger()
        let found = run(rate: 0.9, minutes: 10, ledger: &ledger)
        #expect(found.hot.map(\.pid) == [101])
        #expect(found.hot.first?.percent == 90)
        #expect(found.hot.first?.agent == .claude)
    }

    @Test("At or below the threshold is not")
    func below() {
        var ledger = OrphanLedger()
        #expect(run(rate: 0.5, minutes: 10, ledger: &ledger).hot.isEmpty)
        var other = OrphanLedger()
        #expect(run(rate: 0.2, minutes: 10, ledger: &other).hot.isEmpty)
    }

    @Test("Not before the window has been watched")
    func tooSoon() {
        var ledger = OrphanLedger()
        #expect(run(rate: 0.9, minutes: 8, ledger: &ledger).hot.isEmpty)
    }

    @Test("The threshold and the window are the rules'")
    func rulesApply() {
        var low = OrphanLedger()
        let gentle = OrphanRules(spinningPercent: 30, spinningMinutes: 5)
        #expect(run(rate: 0.4, minutes: 5, rules: gentle, ledger: &low).hot.count == 1)
        var high = OrphanLedger()
        let strict = OrphanRules(spinningPercent: 80, spinningMinutes: 30)
        #expect(run(rate: 0.9, minutes: 20, rules: strict, ledger: &high).hot.isEmpty)
        #expect(run(rate: 0.9, minutes: 10, rules: strict, ledger: &high).hot.isEmpty)
    }

    @Test("Never while a session of the agent was working inside the window")
    func workingExempts() {
        var ledger = OrphanLedger()
        let found = run(rate: 0.9, minutes: 10, working: { $0 == 6 ? [.claude] : [] }, ledger: &ledger)
        #expect(found.hot.isEmpty)
    }

    @Test("Work before the window does not excuse it")
    func oldWorkDoesNot() {
        var ledger = OrphanLedger()
        let found = run(
            rate: 0.9, minutes: 15, working: { $0 <= 3 ? [.claude] : [] }, ledger: &ledger)
        #expect(found.hot.count == 1)
    }

    @Test("Another agent working changes nothing")
    func otherAgentWorking() {
        var ledger = OrphanLedger()
        #expect(run(rate: 0.9, minutes: 10, working: { _ in [.codex] }, ledger: &ledger).hot.count == 1)
    }

    @Test("The agent itself can be hot")
    func rootHot() {
        var ledger = OrphanLedger()
        var found = OrphanFindings()
        for minute in 0...10 {
            let table = [
                ProcessSnapshot(
                    pid: 100, parent: 1, name: "claude", startedAt: base,
                    cpuSeconds: 0.95 * Double(minute) * 60)
            ]
            found = ledger.observe(
                table: table, candidates: [100: .claude], workingAgents: [],
                rules: OrphanRules(), now: base.addingTimeInterval(Double(minute) * 60))
        }
        #expect(found.hot.map(\.name) == ["claude"])
    }

    @Test("The rule can be switched off, and an ignored name is skipped")
    func offAndIgnored() {
        var ledger = OrphanLedger()
        #expect(
            run(rate: 0.9, minutes: 10, rules: OrphanRules(watchesSpinning: false), ledger: &ledger).hot
                .isEmpty)
        var other = OrphanLedger()
        #expect(
            run(rate: 0.9, minutes: 10, rules: OrphanRules(ignored: ["node"]), ledger: &other).hot.isEmpty)
    }

    @Test("A process that cannot be read is never hot")
    func unreadable() {
        var ledger = OrphanLedger()
        #expect(run(rate: 0.9, minutes: 10, readable: false, ledger: &ledger).hot.isEmpty)
    }

    @Test("A process that is already left behind is listed once, there")
    func orphanIsNotAlsoHot() {
        var ledger = OrphanLedger()
        _ = run(rate: 0.9, minutes: 10, ledger: &ledger)
        let table = [
            ProcessSnapshot(
                pid: 101, parent: 1, name: "node", startedAt: base, cpuSeconds: 0.9 * 11 * 60)
        ]
        let found = ledger.observe(
            table: table, candidates: [:], workingAgents: [], rules: OrphanRules(),
            now: base.addingTimeInterval(11 * 60))
        #expect(found.leftBehind.map(\.pid) == [101])
        #expect(found.hot.isEmpty)
    }

    @Test("A new process on a pid starts its count again")
    func pidReuse() {
        var ledger = OrphanLedger()
        _ = run(rate: 0.9, minutes: 9, ledger: &ledger)
        let table = [
            ProcessSnapshot(pid: 100, parent: 1, name: "claude", startedAt: base),
            ProcessSnapshot(
                pid: 101, parent: 100, name: "node", startedAt: base.addingTimeInterval(5_000),
                cpuSeconds: 10_000)
        ]
        let found = ledger.observe(
            table: table, candidates: [100: .claude], workingAgents: [], rules: OrphanRules(),
            now: base.addingTimeInterval(10 * 60))
        #expect(found.hot.isEmpty)
    }
}
