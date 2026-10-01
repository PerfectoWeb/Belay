import Foundation
import Testing

@testable import BelayModules

@Suite("Orphan watch rules")
struct OrphanRulesTests {
    private func suite() throws -> (UserDefaults, String) {
        let name = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test("The defaults")
    func defaults() {
        let rules = OrphanRules()
        #expect(rules.notifies)
        #expect(rules.watchesSpinning)
        #expect(rules.spinningPercent == 50)
        #expect(rules.spinningMinutes == 10)
        #expect(rules.ignored.isEmpty)
    }

    @Test("A record from before a rule existed takes that rule's default")
    func missingFields() throws {
        let rules = try JSONDecoder().decode(OrphanRules.self, from: Data(#"{"notifies":false}"#.utf8))
        #expect(rules == OrphanRules(notifies: false))
    }

    @Test("Rules survive a save and a load, and an empty store gives the defaults")
    func roundTrip() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(OrphanRules.load(from: defaults) == OrphanRules())
        let rules = OrphanRules(
            notifies: false, watchesSpinning: false, spinningPercent: 80, spinningMinutes: 30,
            ignored: ["node"])
        rules.save(to: defaults)
        #expect(OrphanRules.load(from: defaults) == rules)
    }

    @Test("A value the pickers do not offer lands on the closest one")
    func nearest() {
        let rules = OrphanRules(spinningPercent: 75, spinningMinutes: 12)
        #expect(rules.spinningPercent == 80)
        #expect(rules.spinningMinutes == 10)
    }

    @Test("Ignoring a name is case-blind, never doubled, and can be undone")
    func ignoring() {
        var rules = OrphanRules()
        rules.ignore("Node")
        rules.ignore(" node ")
        rules.ignore("  ")
        #expect(rules.ignored == ["Node"])
        #expect(rules.ignores("node"))
        #expect(!rules.ignores("python3"))
        rules.unignore("NODE")
        #expect(rules.ignored.isEmpty)
    }
}

@Suite("Orphan roots")
struct OrphanRootsTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func process(_ pid: pid_t, _ name: String, started: TimeInterval = 0) -> ProcessSnapshot {
        ProcessSnapshot(
            pid: pid, parent: 1, name: name, startedAt: base.addingTimeInterval(started))
    }

    @Test("Agents are found by their exact command name")
    func byName() {
        let roots = OrphanRoots.resolve(
            table: [
                process(10, "claude"), process(11, "codex"), process(12, "Claude"),
                process(13, "Claude Helper"), process(14, "node")
            ], registry: [:])
        #expect(roots == [10: .claude, 11: .codex])
    }

    @Test("A pid in the registry counts while it is still the process that wrote it")
    func registry() {
        let roots = OrphanRoots.resolve(
            table: [process(20, "2.1.284", started: 0), process(21, "node", started: 100)],
            registry: [20: base.addingTimeInterval(60), 21: base.addingTimeInterval(60), 22: base])
        #expect(roots == [20: .claude])
    }
}
