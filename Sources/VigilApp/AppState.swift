import Observation
import SwiftUI
import VigilCore

/// The single object every view reads. Mirrors the coordinator outward; nothing
/// in the UI reaches back into an actor, and no view owns state of its own
/// beyond transient presentation flags (docs/02).
///
/// Frozen before the UI work began on purpose: the panel and the detection layer
/// are built against this shape in parallel, so changing it mid-flight is what
/// would produce a merge mess.
@MainActor
@Observable
final class AppState {
    private(set) var snapshot: CoordinatorSnapshot = .idle
    /// Mirrors the settings store so the mode picker is instant; writes go back
    /// through `onModeChange`, never straight into the snapshot.
    var mode: AwakeMode = .auto
    private(set) var providers: [ProviderStatus] = []
    /// Non-fatal problem worth a single inline row, e.g. folder access lost or
    /// IOKit refusing the assertion. Never a modal.
    private(set) var warning: String?
    /// Total time this launch has held the Mac awake, for the panel footer.
    private(set) var totalAwake: TimeInterval = 0

    var onModeChange: (AwakeMode) -> Void = { _ in }
    /// SwiftUI views track this object automatically; the AppKit status item
    /// cannot, so it gets an explicit nudge.
    var onChange: () -> Void = {}
    var onGrantAccess: (ProviderID) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    var isHolding: Bool { snapshot.state.holdsAssertion }

    /// Sessions as a one-level tree: real sessions at the top, their subagents
    /// nested underneath.
    ///
    /// Flat, this list was unreadable — a workflow of fifty-four agents pushed
    /// the session that actually started it off the end of a five-row panel.
    var sessions: [SessionRow] {
        let rows = snapshot.sessions.map { session in
            SessionRow(
                id: session.id,
                provider: session.provider,
                workspace: session.workspace ?? String(localized: "Untitled project"),
                activity: snapshot.activities[session.id] ?? .idle,
                since: session.workingSince ?? session.awaitingSince ?? session.firstSeen,
                parent: session.parent,
                kind: session.kind
            )
        }
        return SessionRow.nest(rows)
    }

    func apply(_ snapshot: CoordinatorSnapshot, totalAwake: TimeInterval) {
        self.snapshot = snapshot
        self.totalAwake = totalAwake
        onChange()
    }

    func apply(providers: [ProviderStatus]) {
        self.providers = providers
    }

    func apply(warning: String?) {
        self.warning = warning
    }
}

/// One row of the panel's session list, already formatted so views do no policy
/// work of their own.
struct SessionRow: Identifiable, Equatable {
    let id: SessionID
    let provider: ProviderID
    let workspace: String
    let activity: SessionActivity
    let since: Date
    var parent: SessionID?
    /// The agent's configured type, for subagent rows.
    var kind: String?
    var children: [SessionRow] = []

    /// What the row reports, counting its subagents. A session whose fifty-four
    /// agents are mid-run is not "Idle" just because its own transcript is
    /// quiet — and it is their work that is holding the Mac awake, so saying so
    /// is the difference between the panel explaining the hold and contradicting it.
    var rollup: SessionActivity {
        children.map(\.activity).reduce(activity) { $0.strongerOf($1) }
    }
}

extension SessionRow {
    /// Attaches subagents to their parents, oldest first.
    ///
    /// A subagent whose parent is not in the list stays at the top level rather
    /// than disappearing: the parent can be evicted by TTL while its agents are
    /// still going, and a session that silently vanishes from the panel while it
    /// holds the Mac awake is the worst outcome available.
    ///
    /// Deliberately one level deep. An agent that spawns its own agents lands
    /// under the session the user actually started, because that is the thing
    /// they recognise — nobody is looking for a tree view in a menu bar popover.
    static func nest(_ rows: [SessionRow]) -> [SessionRow] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [SessionID: [SessionRow]] = [:]
        for row in rows {
            guard let ancestor = Self.ancestor(of: row, in: byID) else { continue }
            children[ancestor, default: []].append(row)
        }
        return rows.filter { Self.ancestor(of: $0, in: byID) == nil }
            .map { row in
                var row = row
                row.children = (children[row.id] ?? []).sorted { $0.since < $1.since }
                return row
            }
    }

    /// The top-most known session above `row`, or nil if it is one itself. The
    /// depth cap is a guard against a malformed cycle hanging the UI thread,
    /// not a real limit — observed nesting is one.
    private static func ancestor(of row: SessionRow, in byID: [SessionID: SessionRow]) -> SessionID? {
        var current = row
        for _ in 0..<8 {
            guard let parent = current.parent, parent != current.id, let next = byID[parent] else {
                break
            }
            current = next
        }
        return current.id == row.id ? nil : current.id
    }
}

extension SessionActivity {
    /// Ordered by how much attention the state deserves in a summary.
    fileprivate func strongerOf(_ other: SessionActivity) -> SessionActivity {
        rank >= other.rank ? self : other
    }

    private var rank: Int {
        switch self {
        case .working: return 3
        case .awaitingUser: return 2
        case .idle: return 1
        case .ended: return 0
        }
    }
}

struct ProviderStatus: Identifiable, Equatable {
    let descriptor: ProviderDescriptor
    let availability: ProviderAvailability
    let isEnabled: Bool
    /// When the provider last produced a signal, for the detection-health row
    /// that risk R1 asks for.
    let lastSignal: Date?

    var id: ProviderID { descriptor.id }
}
