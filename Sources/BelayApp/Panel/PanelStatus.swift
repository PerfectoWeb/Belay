import BelayCore
import SwiftUI

/// The panel's headline, derived from the coordinator state and nothing else.
///
/// Modelled as a value rather than computed inline in the view so the wording
/// rules docs/05 cares about — plain language, no jargon, and a real sentence
/// whenever Belay has stopped holding — are testable without a view hierarchy.
enum PanelStatus: Equatable {
    case off
    case armed
    case alwaysOn
    case working
    case awaitingUser
    case coolingDown
    case batteryLow(percent: Int)
    case maxDurationReached
    /// Always on with a countdown running, so the sentence can stop promising
    /// "until you switch it off" the moment that stops being true.
    case alwaysOnTimed
    case timerEnded

    static func derive(from state: BelayState, timer: AlwaysOnTimer? = nil) -> PanelStatus {
        switch state {
        case .off: return .off
        case .armed: return .armed
        case .alwaysOn: return timer == nil ? .alwaysOn : .alwaysOnTimed
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
        case .timerEnded:
            return .timerEnded
        }
    }

    /// True while the Mac is actually being held awake, which is the one thing
    /// a user should be able to read off the panel in under a second.
    var isHolding: Bool {
        switch self {
        case .alwaysOn, .alwaysOnTimed, .working, .awaitingUser, .coolingDown: return true
        case .off, .armed, .batteryLow, .maxDurationReached, .timerEnded: return false
        }
    }

    /// True when Belay gave up a hold it would otherwise be keeping, which the
    /// panel calls out rather than quietly letting the Mac drop off (docs/01).
    var isInterrupted: Bool {
        switch self {
        case .batteryLow, .maxDurationReached, .timerEnded: return true
        default: return false
        }
    }
}

@MainActor
extension PanelStatus {
    /// The panel header shows the same mark as the menu bar, so the two can
    /// never tell different stories about the same state.
    var look: BelayGlyph.Look {
        switch self {
        // Always on is its own look. Collapsing it into `.working` meant
        // switching between Auto and Always on changed nothing on screen, which
        // reads as the click not having registered.
        case .alwaysOn, .alwaysOnTimed: return .alwaysOn
        case .working, .coolingDown: return .working
        case .armed: return .resting
        case .awaitingUser: return .calling
        case .off: return .off
        case .batteryLow, .maxDurationReached, .timerEnded: return .blocked
        }
    }
}
