import Foundation

/// What the orphan watch remembers between two looks at the process table, and
/// the decision it draws from each look. Pure: the table, the clock and the
/// rules are handed in, so a test can make a session end by leaving a pid out.
///
/// A process is remembered only while it is seen under a live agent. The
/// lineage is rebuilt live every launch: nothing about it is written to disk.
public struct OrphanLedger: Sendable {
    /// How deep the walk from an agent goes, as `AgentChildren` does.
    static let maxDepth = 8
    /// How far short of the window the oldest sample may fall: a look a little
    /// early is still a look at the whole window.
    static let slack: TimeInterval = 30
    /// A sample this close to the last one replaces it.
    static let resolution: TimeInterval = 20
    /// The longest window the picker offers, plus a minute and a half.
    static let horizon = Double(OrphanRules.minutes.max() ?? 30) * 60 + 90

    private struct Root {
        var startedAt: Date
        var agent: OrphanAgent
    }

    private struct Kin {
        var name: String
        var startedAt: Date
        var rootPid: pid_t
        var rootStart: Date
        var agent: OrphanAgent
    }

    private struct Sample {
        var at: Date
        var cpu: Double
    }

    private struct Usage {
        var startedAt: Date
        var samples: [Sample]
    }

    private var roots: [pid_t: Root] = [:]
    private var kin: [pid_t: Kin] = [:]
    private var usage: [pid_t: Usage] = [:]
    private var workedAt: [OrphanAgent: Date] = [:]

    public init() {}

    /// The pids whose CPU time the next look needs to read.
    public var watched: [pid_t] { Array(Set(roots.keys).union(kin.keys)) }

    /// One look. `candidates` are the agent processes found in `table`;
    /// `workingAgents` are the agents with a session working in Belay's own
    /// snapshot.
    public mutating func observe(
        table: [ProcessSnapshot],
        candidates: [pid_t: OrphanAgent],
        workingAgents: Set<OrphanAgent>,
        rules: OrphanRules,
        now: Date
    ) -> OrphanFindings {
        let alive = Dictionary(table.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        for agent in workingAgents { workedAt[agent] = now }
        follow(candidates, in: alive)
        remember(table, in: alive)
        record(alive, now: now)

        let left = leftBehind(rules: rules)
        let gone = Set(left.map(\.pid))
        return OrphanFindings(
            leftBehind: left,
            hot: rules.watchesSpinning ? hot(alive, excluding: gone, rules: rules, now: now) : [],
            roots: roots.count, tracked: kin.count)
    }

    /// An agent that is gone, or whose pid now belongs to another process, stops
    /// being one; a new one is noted with the start time it has now.
    private mutating func follow(_ candidates: [pid_t: OrphanAgent], in alive: [pid_t: ProcessSnapshot]) {
        roots = roots.filter { pid, root in
            alive[pid].map { Self.same($0.startedAt, root.startedAt) } ?? false
        }
        for (pid, agent) in candidates where roots[pid] == nil {
            guard let process = alive[pid] else { continue }
            roots[pid] = Root(startedAt: process.startedAt, agent: agent)
        }
    }

    /// Forgets what exited, then walks down from each live agent.
    private mutating func remember(_ table: [ProcessSnapshot], in alive: [pid_t: ProcessSnapshot]) {
        kin = kin.filter { pid, known in
            guard let process = alive[pid], roots[pid] == nil,
                Self.same(process.startedAt, known.startedAt)
            else { return false }
            return true
        }
        for (pid, process) in alive { kin[pid]?.name = process.name }

        let children = Dictionary(grouping: table.filter { $0.pid > 0 }, by: \.parent)
        for (rootPid, root) in roots {
            var frontier = [rootPid]
            var seen: Set<pid_t> = [rootPid]
            var depth = 0
            while !frontier.isEmpty, depth < Self.maxDepth {
                var next: [pid_t] = []
                for parent in frontier {
                    // Another agent's subtree is that agent's own.
                    for child in children[parent] ?? []
                    where roots[child.pid] == nil && seen.insert(child.pid).inserted {
                        kin[child.pid] = Kin(
                            name: child.name, startedAt: child.startedAt, rootPid: rootPid,
                            rootStart: root.startedAt, agent: root.agent)
                        next.append(child.pid)
                    }
                }
                frontier = next
                depth += 1
            }
        }
    }

    /// Remembered processes whose agent is no longer the process it was.
    private func leftBehind(rules: OrphanRules) -> [LeftBehind] {
        kin.compactMap { pid, known in
            let agentIsAlive = roots[known.rootPid].map { Self.same($0.startedAt, known.rootStart) }
            guard agentIsAlive != true, !known.name.isEmpty, !rules.ignores(known.name) else { return nil }
            return LeftBehind(pid: pid, name: known.name, startedAt: known.startedAt, agent: known.agent)
        }
        .sorted { ($0.startedAt, $0.pid) < ($1.startedAt, $1.pid) }
    }

    private mutating func record(_ alive: [pid_t: ProcessSnapshot], now: Date) {
        let wanted = Set(roots.keys).union(kin.keys)
        usage = usage.filter { pid, entry in
            guard wanted.contains(pid), let process = alive[pid] else { return false }
            return Self.same(process.startedAt, entry.startedAt)
        }
        for pid in wanted {
            guard let process = alive[pid], let cpu = process.cpuSeconds else { continue }
            var entry = usage[pid] ?? Usage(startedAt: process.startedAt, samples: [])
            if let last = entry.samples.last, now.timeIntervalSince(last.at) < Self.resolution {
                entry.samples.removeLast()
            }
            entry.samples.append(Sample(at: now, cpu: cpu))
            entry.samples.removeAll { now.timeIntervalSince($0.at) > Self.horizon }
            usage[pid] = entry
        }
    }

    /// Averaged over the window, with no session of the agent working at any
    /// look inside it. A process that cannot be read is never hot.
    private func hot(
        _ alive: [pid_t: ProcessSnapshot], excluding gone: Set<pid_t>, rules: OrphanRules, now: Date
    ) -> [RunningHot] {
        let window = Double(rules.spinningMinutes) * 60
        var found: [RunningHot] = []
        for (pid, entry) in usage where !gone.contains(pid) {
            guard let process = alive[pid], !rules.ignores(process.name),
                let agent = roots[pid]?.agent ?? kin[pid]?.agent,
                let first = entry.samples.first(where: { now.timeIntervalSince($0.at) <= window + 90 }),
                let last = entry.samples.last, now.timeIntervalSince(last.at) < 120,
                now.timeIntervalSince(first.at) >= window - Self.slack
            else { continue }
            if let worked = workedAt[agent], worked >= first.at { continue }
            let seconds = last.at.timeIntervalSince(first.at)
            guard seconds > 0 else { continue }
            let percent = (last.cpu - first.cpu) / seconds * 100
            guard percent > Double(rules.spinningPercent) else { continue }
            found.append(
                RunningHot(
                    pid: pid, name: process.name, startedAt: process.startedAt, agent: agent,
                    percent: Int(percent.rounded())))
        }
        return found.sorted { ($0.percent, $1.pid) > ($1.percent, $0.pid) }
    }

    private static func same(_ first: Date, _ second: Date) -> Bool {
        abs(first.timeIntervalSince(second)) < 1
    }
}
