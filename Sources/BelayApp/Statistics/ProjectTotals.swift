import Foundation

/// The sums a headline shows over a set of session records.
///
/// Kept as a value built on demand from the records, not a stored accumulator
/// beside them: two counts of the same thing drift apart, and a headline that
/// disagrees with the table under it is worse than one that only covers the
/// recent list. So this is always "these sessions", the caption says so, and
/// it can never contradict the rows. Same privacy line as the records it adds
/// up: a folder name, counts and durations, nothing else.
struct ProjectTotals: Equatable {
    var sessions = 0
    var seconds: TimeInterval = 0
    var tokens = 0
    /// How many of `sessions` reported a token count at all. Agents that
    /// never say must not read as zero-token runs.
    var tokenSessions = 0

    private mutating func add(_ record: SessionRecord) {
        sessions += 1
        seconds += record.duration
        if let count = record.tokens {
            tokens += count
            tokenSessions += 1
        }
    }

    /// Built straight from the records on screen, never stored: the one number
    /// the headline shows must be the sum of the rows under it, or it reads as
    /// a contradiction. The recent list is capped, so this is "these sessions",
    /// which is what the caption under the table says it is.
    static func over(_ records: [SessionRecord]) -> ProjectTotals {
        var totals = ProjectTotals()
        for record in records { totals.add(record) }
        return totals
    }

    /// "22 sessions · 14h 46m agent time · 779.7k tokens", or without the time
    /// where the time is the headline itself. Parallel sessions add up, so
    /// this is the agents' time, not the person's, and it says so. The token
    /// sum covers only the sessions that reported one; a second session
    /// count here read as a contradiction, so the rows that never said carry
    /// the disclosure instead, with their dash in the Tokens column.
    func caption(withTime: Bool) -> String {
        var pieces = [String(localized: "\(sessions) sessions")]
        if withTime {
            pieces.append(String(localized: "\(ElapsedTime.compact(seconds)) agent time"))
        }
        pieces.append(
            tokenSessions == 0
                ? String(localized: "no token reports")
                : String(localized: "\(tokensLabel) tokens"))
        return pieces.joined(separator: " \u{00B7} ")
    }

    /// "1.2M", "45.2k", or an em-width dash when nobody reported.
    var tokensLabel: String {
        guard tokenSessions > 0 else { return "\u{2014}" }
        switch tokens {
        case ..<1000: return "\(tokens)"
        case ..<1_000_000: return String(format: "%.1fk", Double(tokens) / 1000)
        default: return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
    }
}
