import BelayCore
import Foundation

/// One finished session, kept for the statistics pane's recent list.
///
/// Structural fields only, the same privacy line the detectors hold: the
/// workspace's folder name (already shown in the panel while the session
/// ran), which agent, and when. Never a prompt, never a path beyond the last
/// component, never a transcript.
struct SessionRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var provider: ProviderID
    var workspace: String?
    var startedAt: Date
    var endedAt: Date
    /// Cumulative tokens the session's own transcript reported, when its
    /// agent reports any. Optional so records written before this field — and
    /// agents that never say — read back cleanly.
    var tokens: Int?

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    /// Sort keys for the table. Computed, so the stored shape and old records
    /// stay untouched.
    var agentName: String {
        switch provider {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cline: return "Cline"
        case .copilot: return "Copilot"
        case .generic: return String(localized: "Agent")
        }
    }

    var folder: String { workspace ?? "\u{2014}" }

    /// Sortable form: "no report" sits below any reported number.
    var tokensSort: Int { tokens ?? -1 }

    /// "1.2M", "45.2k", "980" — or an em-width dash for agents that never say.
    var tokensLabel: String {
        guard let tokens else { return "\u{2014}" }
        switch tokens {
        case ..<1000: return "\(tokens)"
        case ..<1_000_000: return String(format: "%.1fk", Double(tokens) / 1000)
        default: return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
    }
}

/// Notices sessions leaving the snapshot and turns them into records.
///
/// Pure, like `AnnouncementTrigger`: the diff is the logic, the store is the
/// side effect, and only the first needs tests. Subagents are skipped — they
/// already counted as part of their parent while alive, and a list where one
/// Claude run appears four times is a worse answer, not a longer one.
struct SessionHistoryTracker: Equatable {
    /// Shorter than this is a blip — a mis-adopted file, an instant question —
    /// and would bury the runs the list exists to remember.
    static let minimumDuration: TimeInterval = 60

    private var live: [SessionID: SessionRecord] = [:]

    mutating func diff(_ snapshot: CoordinatorSnapshot, now: Date = Date()) -> [SessionRecord] {
        var ended: [SessionRecord] = []
        let present = Set(snapshot.sessions.map(\.id))

        for session in snapshot.sessions where session.parent == nil {
            if var known = live[session.id] {
                // The workspace can arrive a sweep late; keep the newest word,
                // and the token total only ever moves forward.
                if let workspace = session.workspace { known.workspace = workspace }
                if session.tokens > (known.tokens ?? 0) { known.tokens = session.tokens }
                live[session.id] = known
            } else {
                live[session.id] = SessionRecord(
                    id: UUID(),
                    provider: session.provider,
                    workspace: session.workspace,
                    startedAt: session.firstSeen,
                    endedAt: session.firstSeen,
                    tokens: session.tokens > 0 ? session.tokens : nil)
            }
        }

        for (id, record) in live where !present.contains(id) {
            live.removeValue(forKey: id)
            var finished = record
            finished.endedAt = now
            guard finished.duration >= Self.minimumDuration else { continue }
            ended.append(finished)
        }
        return ended
    }
}

/// Persists the recent list beside the rest of the statistics.
@MainActor
struct SessionHistoryStore {
    /// Enough depth for the sessions table to be worth sorting.
    static let capacity = 50

    private let key = "sessionHistory"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SessionRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SessionRecord].self, from: data)) ?? []
    }

    /// Newest first, capped; the tail simply falls off.
    func append(_ records: [SessionRecord]) {
        guard !records.isEmpty else { return }
        let kept = Array((records.sorted { $0.endedAt > $1.endedAt } + load()).prefix(Self.capacity))
        guard let data = try? JSONEncoder().encode(kept) else { return }
        defaults.set(data, forKey: key)
    }

    /// The statistics reset clears this too: "start again" means all of it.
    func reset() {
        defaults.removeObject(forKey: key)
    }
}
