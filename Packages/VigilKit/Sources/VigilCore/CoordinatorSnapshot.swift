import Foundation

/// Why Vigil is holding the Mac awake, as structured data.
///
/// The UI localises from these cases; `assertionDetail` is the plain-English
/// string that ends up in `pmset -g assertions`, where a localised string would
/// be worse than useless to whoever is debugging.
public enum HoldReason: Sendable, Equatable {
    case alwaysOn
    case working(sessions: Int, workspace: String?)
    case awaitingUser(workspace: String?)
    case coolingDown

    public var assertionDetail: String {
        switch self {
        case .alwaysOn:
            return "Always on"
        case .working(let sessions, let workspace):
            guard sessions == 1 else { return "\(sessions) agent sessions are working" }
            guard let workspace else { return "An agent is working" }
            return "An agent is working in \(workspace)"
        case .awaitingUser(let workspace):
            guard let workspace else { return "An agent is waiting for you" }
            return "An agent is waiting for you in \(workspace)"
        case .coolingDown:
            return "Waiting to see whether more work arrives"
        }
    }
}

/// Why Vigil has stopped holding despite work being present. Both cases are
/// user-visible: silently letting the Mac sleep mid-task is the failure mode
/// docs/01 says we must never produce without saying so.
public enum SuspensionReason: Sendable, Equatable {
    case batteryLow(charge: Double)
    case maxDurationReached(TimeInterval)
}

public enum VigilState: Sendable, Equatable {
    case off
    case alwaysOn
    /// Auto mode, nothing running.
    case armed
    case working
    case awaitingUser
    /// Grace period: still holding, waiting to see if more work arrives.
    case coolingDown
    case suspended(SuspensionReason)

    public var holdsAssertion: Bool {
        switch self {
        case .alwaysOn, .working, .awaitingUser, .coolingDown: return true
        case .off, .armed, .suspended: return false
        }
    }
}

/// Immutable view of the coordinator for the UI. The UI never reaches back into
/// the actor; it renders this and nothing else (docs/02).
public struct CoordinatorSnapshot: Sendable, Equatable {
    public var state: VigilState
    public var sessions: [SessionState]
    /// Effective activity per session, already fused, so the UI does no policy work.
    public var activities: [SessionID: SessionActivity]
    public var holdReason: HoldReason?
    /// When the current continuous hold began, for the footer's total.
    public var holdingSince: Date?

    public static let idle = CoordinatorSnapshot(
        state: .armed,
        sessions: [],
        activities: [:],
        holdReason: nil,
        holdingSince: nil
    )

    public init(
        state: VigilState,
        sessions: [SessionState],
        activities: [SessionID: SessionActivity],
        holdReason: HoldReason?,
        holdingSince: Date?
    ) {
        self.state = state
        self.sessions = sessions
        self.activities = activities
        self.holdReason = holdReason
        self.holdingSince = holdingSince
    }
}
