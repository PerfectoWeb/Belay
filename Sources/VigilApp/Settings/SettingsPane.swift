import Foundation

/// One pane of the Settings window.
///
/// The window's switcher is built from these cases, so adding a pane is one case
/// here plus one branch in `SettingsView`.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case providers
    case behaviour
    case notifications
    case statistics
    case about

    /// Fixed, and deliberately generous: six icon-and-label items have to fit on
    /// one row with room to spare, in every language.
    static let width: CGFloat = 700

    var id: String { rawValue }

    /// Shown in the switcher and as the window title. The title takes a plain
    /// `String`, so this does not localise itself the way a SwiftUI `Text` would
    /// and has to say so.
    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .providers: return String(localized: "Providers")
        case .behaviour: return String(localized: "Behaviour")
        case .notifications: return String(localized: "Notifications")
        case .statistics: return String(localized: "Statistics")
        case .about: return String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "sparkles"
        case .behaviour: return "moon.zzz"
        case .notifications: return "bell"
        case .statistics: return "chart.bar"
        case .about: return "info.circle"
        }
    }

    /// Used only when the pane refuses to measure. Every pane is measured for
    /// real before the window resizes; this keeps a layout failure from
    /// collapsing the window to a sliver the way it did once before.
    var fallbackHeight: CGFloat {
        switch self {
        case .general: return 220
        case .providers: return 460
        case .behaviour: return 360
        case .notifications: return 300
        case .statistics: return 380
        case .about: return 360
        }
    }
}
