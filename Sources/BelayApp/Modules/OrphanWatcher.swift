import BelayModules
import Foundation
import Observation

/// The orphan watch, running: once a minute it reads the process table,
/// remembers what each agent started, and points at whatever outlived it.
///
/// A minute is the right beat for a forgotten dev server: nothing about one
/// gets worse in sixty seconds, and the look costs a few milliseconds.
@MainActor
@Observable
final class OrphanWatcher {
    static let interval: TimeInterval = 60

    var rules: OrphanRules {
        didSet {
            guard rules != oldValue else { return }
            rules.save(to: defaults)
            guard isRunning else { return }
            note("orphans rules \(settings)")
            sweep()
        }
    }
    /// What the last look found, for the list.
    private(set) var findings = OrphanFindings()
    private(set) var isRunning = false
    /// How many the last End could not stop.
    private(set) var notEnded = 0

    /// Whether an agent is switched on in Agents: a module does nothing for
    /// an agent Belay was told to leave alone.
    @ObservationIgnored var agentIsOn: (OrphanAgent) -> Bool = { _ in true }
    /// The agents with a session working in Belay's own snapshot.
    @ObservationIgnored var workingAgents: () -> Set<OrphanAgent> = { [] }
    /// Something new was left behind: how many, in one look.
    @ObservationIgnored var notify: (Int) -> Void = { _ in }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let source: ProcessSource
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let settle: Duration
    @ObservationIgnored private let note: (String) -> Void
    @ObservationIgnored private var ledger = OrphanLedger()
    @ObservationIgnored private var timer: Timer?
    /// Already announced, so a process is news once.
    @ObservationIgnored private var announced: Set<pid_t> = []
    @ObservationIgnored private var lastCounts: [Int]?

    init(
        defaults: UserDefaults = .standard,
        source: ProcessSource? = nil,
        settle: Duration = .seconds(2),
        now: @escaping @Sendable () -> Date = { Date() },
        note: @escaping (String) -> Void = { Diagnostics.note($0) }
    ) {
        self.defaults = defaults
        self.source = source ?? SystemProcesses.real
        self.settle = settle
        self.note = note
        self.now = now
        rules = OrphanRules.load(from: defaults)
    }

    /// Agents switched off in Agents, which are not watched.
    var agentsLeftAlone: [OrphanAgent] { OrphanAgent.allCases.filter { !agentIsOn($0) } }

    /// Switched on by the user.
    func activate() {
        start()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweep() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        note("orphans start \(settings)")
        sweep()
    }

    /// The rules as the log states them. How many names, never which.
    private var settings: String {
        """
        spinning=\(rules.watchesSpinning ? 1 : 0) percent=\(rules.spinningPercent) \
        minutes=\(rules.spinningMinutes) notifies=\(rules.notifies ? 1 : 0) \
        ignored=\(rules.ignored.count)
        """
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        ledger = OrphanLedger()
        findings = OrphanFindings()
        announced = []
        lastCounts = nil
        notEnded = 0
    }

    /// One look at the process table. A table that cannot be read leaves
    /// everything as it was: a failed read is never "nothing is running".
    func sweep() {
        guard isRunning, var table = source.table() else { return }
        let cpu = source.cpuSeconds(of: ledger.watched)
        for index in table.indices { table[index].cpuSeconds = cpu[table[index].pid] }
        let candidates = OrphanRoots.resolve(table: table, registry: source.sessionRegistry())
            .filter { agentIsOn($0.value) }
        var found = ledger.observe(
            table: table, candidates: candidates, workingAgents: workingAgents(), rules: rules,
            now: now())
        found.leftBehind.removeAll { !agentIsOn($0.agent) }
        found.hot.removeAll { !agentIsOn($0.agent) }
        record(found)
    }

    private func record(_ found: OrphanFindings) {
        if found != findings { findings = found }
        let counts = [found.roots, found.tracked, found.leftBehind.count, found.hot.count]
        if counts != lastCounts {
            lastCounts = counts
            note(
                """
                orphans sweep roots=\(counts[0]) tracked=\(counts[1]) orphans=\(counts[2]) \
                hot=\(counts[3])
                """)
        }
        let present = Set(found.leftBehind.map(\.pid))
        let fresh = present.subtracting(announced)
        announced = present
        if !fresh.isEmpty, rules.notifies { notify(fresh.count) }
    }

    /// Leaves the name out of the list and the counts from now on.
    func ignore(_ name: String) {
        rules.ignore(name)
    }

    func unignore(_ name: String) {
        rules.unignore(name)
    }

    #if !BELAY_MAS
    struct Target: Equatable {
        var pid: pid_t
        var startedAt: Date
    }

    /// Asks one process to quit, after the person confirmed it.
    func end(_ target: Target) async {
        await end([target])
    }

    /// Every process left behind. Not the ones running hot: one of those may
    /// be an agent that is doing something, and that is a choice per process.
    func endAll() async {
        await end(findings.leftBehind.map { Target(pid: $0.pid, startedAt: $0.startedAt) })
    }

    /// SIGTERM, then a look two seconds later. Nothing stronger: a process
    /// that ignores it is reported and left to the person.
    private func end(_ targets: [Target]) async {
        // The same process as was listed, or not at all: a pid is handed
        // out again the moment its owner exits.
        let current = Dictionary(
            (source.table() ?? []).map { ($0.pid, $0.startedAt) }, uniquingKeysWith: { $1 })
        let sent = targets.filter { target in
            current[target.pid].map { abs($0.timeIntervalSince(target.startedAt)) < 1 } ?? false
        }
        for target in sent { _ = source.terminate(target.pid) }
        try? await Task.sleep(for: settle)
        let after = Dictionary(
            (source.table() ?? []).map { ($0.pid, $0.startedAt) }, uniquingKeysWith: { $1 })
        let stuck = sent.filter { target in
            after[target.pid].map { abs($0.timeIntervalSince(target.startedAt)) < 1 } ?? false
        }.count
        notEnded = stuck
        note("orphans ended=\(sent.count - stuck) failed=\(stuck)")
        sweep()
    }
    #endif

    /// Removing the module: the rules and the list go.
    func forgetEverything() {
        stop()
        rules = OrphanRules()
        defaults.removeObject(forKey: OrphanRules.defaultsKey)
    }
}
