import Foundation

/// What Belay has actually done for you, in numbers it can honestly claim.
///
/// One day per bucket, ninety days kept. That is enough for a "last two weeks"
/// chart and a lifetime total without storing anything that could identify a
/// project or a prompt — there are no names in here, only durations and counts.
struct UsageStatistics: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Sendable, Identifiable {
        var date: Date
        var heldSeconds: TimeInterval = 0
        var holds: Int = 0
        var longestHold: TimeInterval = 0
        /// Of `heldSeconds`, how much was held while the user was away from the
        /// keyboard. This is the part that would otherwise have ended in a dead
        /// run, and the only part worth calling value.
        var awaySeconds: TimeInterval = 0
        /// Holds that spent real time unattended.
        var rescued: Int = 0

        var id: Date { date }
    }

    var days: [Day] = []
    var firstRun: Date?

    static let keptDays = 90

    // MARK: - recording

    mutating func record(hold seconds: TimeInterval, away: TimeInterval, on date: Date) {
        guard seconds > 0 else { return }
        if firstRun == nil { firstRun = date }
        let day = Calendar.current.startOfDay(for: date)
        var bucket = days.first { $0.date == day } ?? Day(date: day)
        bucket.heldSeconds += seconds
        bucket.awaySeconds += away
        bucket.holds += 1
        bucket.longestHold = max(bucket.longestHold, seconds)
        // One unattended stretch worth a coffee break is what makes a run a
        // "rescue"; a few idle seconds while reading the screen is not.
        if away >= AwayTime.threshold { bucket.rescued += 1 }
        days.removeAll { $0.date == day }
        days.append(bucket)
        days.sort { $0.date < $1.date }
        trim(before: date)
    }

    private mutating func trim(before now: Date) {
        guard
            let cutoff = Calendar.current.date(
                byAdding: .day, value: -Self.keptDays, to: Calendar.current.startOfDay(for: now))
        else { return }
        days.removeAll { $0.date < cutoff }
    }

    // MARK: - reading

    var totalHeld: TimeInterval { days.reduce(0) { $0 + $1.heldSeconds } }
    var totalAway: TimeInterval { days.reduce(0) { $0 + $1.awaySeconds } }
    var totalHolds: Int { days.reduce(0) { $0 + $1.holds } }
    var totalRescued: Int { days.reduce(0) { $0 + $1.rescued } }
    var longestHold: TimeInterval { days.map(\.longestHold).max() ?? 0 }

    /// Buckets for the last `count` days, including empty ones, oldest first —
    /// a chart with gaps in it is a chart that lies about the shape.
    func recent(_ count: Int, now: Date = Date()) -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return days.first { $0.date == date } ?? Day(date: date)
        }
    }

    var isEmpty: Bool { totalHolds == 0 }
}

/// Persists the statistics beside the rest of Belay's preferences.
@MainActor
struct UsageStatisticsStore {
    private let key = "usageStatistics"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> UsageStatistics {
        guard let data = defaults.data(forKey: key) else { return UsageStatistics() }
        return (try? JSONDecoder().decode(UsageStatistics.self, from: data)) ?? UsageStatistics()
    }

    func save(_ statistics: UsageStatistics) {
        guard let data = try? JSONEncoder().encode(statistics) else { return }
        defaults.set(data, forKey: key)
    }
}
