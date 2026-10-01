import Foundation

/// The agents Orphan Watch knows how to follow, by the command name their
/// process carries. Nothing else about a process is ever read.
public enum OrphanAgent: String, Sendable, CaseIterable, Hashable {
    case claude
    case codex

    /// `p_comm`, exactly and in lower case: the desktop apps call themselves
    /// "Claude" and "Codex", and their helpers are not an agent's children.
    public static func forCommand(_ name: String) -> OrphanAgent? {
        OrphanAgent(rawValue: name)
    }
}

/// How the orphan watch is set up.
public struct OrphanRules: Codable, Equatable, Sendable {
    public static let defaultsKey = "BelayOrphanWatch"

    /// The averages offered in Settings, in percent of one core.
    public static let percents = [30, 50, 80]
    public static let defaultPercent = 50
    /// The stretches offered in Settings, in minutes.
    public static let minutes = [5, 10, 30]
    public static let defaultMinutes = 10

    /// Say so once when something new is left behind.
    public var notifies: Bool
    /// List a process that burns CPU while its agent does nothing.
    public var watchesSpinning: Bool
    public var spinningPercent: Int
    public var spinningMinutes: Int
    /// Command names left out of the list and out of the counts.
    public var ignored: [String]

    public init(
        notifies: Bool = true,
        watchesSpinning: Bool = true,
        spinningPercent: Int = OrphanRules.defaultPercent,
        spinningMinutes: Int = OrphanRules.defaultMinutes,
        ignored: [String] = []
    ) {
        self.notifies = notifies
        self.watchesSpinning = watchesSpinning
        self.spinningPercent = Self.nearest(spinningPercent, in: Self.percents)
        self.spinningMinutes = Self.nearest(spinningMinutes, in: Self.minutes)
        self.ignored = ignored
    }

    /// Field by field, so a record written before a rule existed still loads
    /// and takes that rule's default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            notifies: try values.decodeIfPresent(Bool.self, forKey: .notifies) ?? true,
            watchesSpinning: try values.decodeIfPresent(Bool.self, forKey: .watchesSpinning) ?? true,
            spinningPercent: try values.decodeIfPresent(Int.self, forKey: .spinningPercent)
                ?? Self.defaultPercent,
            spinningMinutes: try values.decodeIfPresent(Int.self, forKey: .spinningMinutes)
                ?? Self.defaultMinutes,
            ignored: try values.decodeIfPresent([String].self, forKey: .ignored) ?? []
        )
    }

    /// A hand-edited value lands on the closest choice the picker can show.
    private static func nearest(_ value: Int, in choices: [Int]) -> Int {
        choices.min { abs($0 - value) < abs($1 - value) } ?? value
    }

    public func ignores(_ name: String) -> Bool {
        let wanted = Self.normalized(name)
        return ignored.contains { Self.normalized($0) == wanted }
    }

    public mutating func ignore(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !ignores(clean) else { return }
        ignored.append(clean)
    }

    public mutating func unignore(_ name: String) {
        let wanted = Self.normalized(name)
        ignored.removeAll { Self.normalized($0) == wanted }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    public static func load(from defaults: UserDefaults) -> OrphanRules {
        guard let data = defaults.data(forKey: defaultsKey),
            let rules = try? JSONDecoder().decode(OrphanRules.self, from: data)
        else { return OrphanRules() }
        return rules
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}

/// One row of the process table: what `sysctl` and `proc_pidinfo` give, and
/// nothing about what the process was asked to do.
public struct ProcessSnapshot: Equatable, Sendable {
    public var pid: pid_t
    public var parent: pid_t
    /// `p_comm`, at most sixteen characters.
    public var name: String
    public var startedAt: Date
    /// User plus system CPU time so far, when it could be read.
    public var cpuSeconds: Double?

    public init(
        pid: pid_t, parent: pid_t, name: String, startedAt: Date, cpuSeconds: Double? = nil
    ) {
        self.pid = pid
        self.parent = parent
        self.name = name
        self.startedAt = startedAt
        self.cpuSeconds = cpuSeconds
    }

    /// Two readings of one pid are the same process only when it started at
    /// the same moment: a pid is handed out again once its owner has gone.
    func isSameProcess(as other: ProcessSnapshot) -> Bool {
        pid == other.pid && abs(startedAt.timeIntervalSince(other.startedAt)) < 1
    }
}

/// A process still running after the session that started it has gone.
public struct LeftBehind: Equatable, Sendable, Identifiable {
    public var pid: pid_t
    public var name: String
    public var startedAt: Date
    public var agent: OrphanAgent
    public var id: pid_t { pid }

    public init(pid: pid_t, name: String, startedAt: Date, agent: OrphanAgent) {
        self.pid = pid
        self.name = name
        self.startedAt = startedAt
        self.agent = agent
    }
}

/// A process that has been burning CPU while its agent did nothing.
public struct RunningHot: Equatable, Sendable, Identifiable {
    public var pid: pid_t
    public var name: String
    public var startedAt: Date
    public var agent: OrphanAgent
    /// Average over the window, in percent of one core.
    public var percent: Int
    public var id: pid_t { pid }

    public init(pid: pid_t, name: String, startedAt: Date, agent: OrphanAgent, percent: Int) {
        self.pid = pid
        self.name = name
        self.startedAt = startedAt
        self.agent = agent
        self.percent = percent
    }
}

/// What one look at the process table found.
public struct OrphanFindings: Equatable, Sendable {
    public var leftBehind: [LeftBehind]
    public var hot: [RunningHot]
    /// Agent processes alive in this look.
    public var roots: Int
    /// Processes remembered as an agent's descendants.
    public var tracked: Int

    public init(
        leftBehind: [LeftBehind] = [], hot: [RunningHot] = [], roots: Int = 0, tracked: Int = 0
    ) {
        self.leftBehind = leftBehind
        self.hot = hot
        self.roots = roots
        self.tracked = tracked
    }

    public var isEmpty: Bool { leftBehind.isEmpty && hot.isEmpty }
}

/// Which processes are agents to follow.
public enum OrphanRoots {
    /// Every process whose command name is an agent's, plus every pid in
    /// Claude Code's session registry that is still the process it was.
    ///
    /// The registry file says when it was last written. A process that started
    /// after that is a stranger that was handed a dead session's pid, and
    /// following it would call its children orphans when it quits.
    public static func resolve(
        table: [ProcessSnapshot], registry: [pid_t: Date]
    ) -> [pid_t: OrphanAgent] {
        var roots: [pid_t: OrphanAgent] = [:]
        for process in table {
            if let agent = OrphanAgent.forCommand(process.name) {
                roots[process.pid] = agent
                continue
            }
            guard let written = registry[process.pid] else { continue }
            if process.startedAt <= written.addingTimeInterval(5) { roots[process.pid] = .claude }
        }
        return roots
    }
}
