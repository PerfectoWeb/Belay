import SwiftUI
import VigilCore

/// The panel's headline, derived from the coordinator state and nothing else.
///
/// Modelled as a value rather than computed inline in the view so the wording
/// rules docs/05 cares about — plain language, no jargon, and a real sentence
/// whenever Vigil has stopped holding — are testable without a view hierarchy.
enum PanelStatus: Equatable {
    case off
    case armed
    case alwaysOn
    case working
    case awaitingUser
    case coolingDown
    case batteryLow(percent: Int)
    case maxDurationReached

    static func derive(from state: VigilState) -> PanelStatus {
        switch state {
        case .off: return .off
        case .armed: return .armed
        case .alwaysOn: return .alwaysOn
        case .working: return .working
        case .awaitingUser: return .awaitingUser
        case .coolingDown: return .coolingDown
        case .suspended(let reason): return derive(from: reason)
        }
    }

    private static func derive(from reason: SuspensionReason) -> PanelStatus {
        switch reason {
        case .batteryLow(let charge):
            // The coordinator carries a 0…1 fraction; the panel talks percent.
            return .batteryLow(percent: Int((charge * 100).rounded()))
        case .maxDurationReached:
            return .maxDurationReached
        }
    }

    /// True while the Mac is actually being held awake, which is the one thing
    /// a user should be able to read off the panel in under a second.
    var isHolding: Bool {
        switch self {
        case .alwaysOn, .working, .awaitingUser, .coolingDown: return true
        case .off, .armed, .batteryLow, .maxDurationReached: return false
        }
    }

    /// True when Vigil gave up a hold it would otherwise be keeping, which the
    /// panel calls out rather than quietly letting the Mac drop off (docs/01).
    var isInterrupted: Bool {
        switch self {
        case .batteryLow, .maxDurationReached: return true
        default: return false
        }
    }
}

@MainActor
extension PanelStatus {
    /// The panel header shows the same mark as the menu bar, so the two can
    /// never tell different stories about the same state.
    var look: VigilGlyph.Look {
        switch self {
        // Always on is its own look. Collapsing it into `.working` meant
        // switching between Auto and Always on changed nothing on screen, which
        // reads as the click not having registered.
        case .alwaysOn: return .alwaysOn
        case .working, .coolingDown: return .working
        case .armed: return .resting
        case .awaitingUser: return .calling
        case .off: return .off
        case .batteryLow, .maxDurationReached: return .blocked
        }
    }
}
