import BelayCore
import Foundation

/// One row of the panel's session list, already formatted so views do no policy
/// work of their own.
struct SessionRow: Identifiable, Equatable {
    let id: SessionID
    let provider: ProviderID
    let workspace: String
    let activity: SessionActivity
    let since: Date
    /// The category of the tool call the session is inside, when hooks said.
    var tool: ToolCategory?
    /// Whether a Stop left background tasks running — the turn is over but
    /// the session is not, and the row should say which kind of alive it is.
    var background = false

    /// What the capsules beside the name say: the session's own tool call,
    /// any distinct tools its subagents are inside, and the background flag.
    /// David's design, verbatim: badges by the title, the state line stays
    /// the state line — structure and activity are different facts and no
    /// longer fight over one slot. Two show; the rest are a count.
    enum Badge: Equatable {
        case tool(ToolCategory)
        case background
    }

    var badges: [Badge] {
        var seen: [ToolCategory] = []
        for candidate in [tool] + children.map(\.tool) {
            if let candidate, !seen.contains(candidate) { seen.append(candidate) }
        }
        var all = seen.map(Badge.tool)
        if background { all.append(.background) }
        return all
    }
    var parent: SessionID?
    /// The agent's configured type, for subagent rows.
    var kind: String?
    /// The agent's own name for the session, e.g. `belay-9a`. Held for every row
    /// but shown only when `disambiguate` decides the workspace is ambiguous.
    var name: String?
    /// The disambiguating fragment, once something has decided one is needed.
    var detail: String?
    var children: [SessionRow] = []

    /// What the row is called. Plain workspace in the common case; two sessions
    /// in one checkout each get their own name appended, because otherwise the
    /// panel shows two identical rows in different states and the user cannot
    /// tell which is which.
    var title: String {
        guard let detail else { return workspace }
        return String(localized: "\(workspace) · \(detail)")
    }

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

    /// Marks the rows whose workspace alone would not identify them.
    ///
    /// Two Claude Code sessions in the same checkout are genuinely separate
    /// sessions, not a parent and a child, so nesting them would be a lie about
    /// the structure. They are told apart instead — and only when they collide,
    /// so a lone session stays plain "Belay" and nothing extra appears in the
    /// case that is almost always the one on screen.
    ///
    /// Subagents are left alone: they are already grouped under the session that
    /// spawned them and are labelled by `kind`, not by workspace.
    static func disambiguate(_ rows: [SessionRow]) -> [SessionRow] {
        var counts: [String: Int] = [:]
        for row in rows { counts[row.workspace, default: 0] += 1 }
        return rows.map { row in
            guard counts[row.workspace, default: 0] > 1 else { return row }
            var row = row
            row.detail = row.name.flatMap(Self.fragment)
            return row
        }
    }

    /// The part of an agent's session name worth showing. Claude Code derives
    /// `belay-9a` from the folder, so repeating "belay" beside the workspace it
    /// came from would add width and no information.
    private static func fragment(_ name: String) -> String? {
        let tail = name.split(separator: "-").last.map(String.init) ?? name
        return tail.isEmpty ? nil : tail
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
    /// Extra watched folders beyond the default home, for the tile's menu.
    var customRoots: [String] = []
    /// Sibling profiles found next to the default home, offered in the menu.
    var suggestedRoots: [String] = []

    var id: ProviderID { descriptor.id }
}
