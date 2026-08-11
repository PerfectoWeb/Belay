import AppKit
import Foundation

/// One pane of the Settings window.
///
/// The window's toolbar is built from these cases, so adding a pane is one case
/// here plus one branch in `SettingsView`.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case providers
    case behaviour
    case notifications
    case statistics
    case about

    /// Fixed, and deliberately generous: six icon-and-label toolbar items have
    /// to fit without AppKit folding any of them into a "more toolbar items"
    /// chevron, which is what made the previous switcher unusable.
    static let width: CGFloat = 700

    var id: String { rawValue }

    /// Shown in the toolbar and as the window title, both of which take a plain
    /// `String`, so these do not localise themselves the way a SwiftUI `Text`
    /// would and have to say so.
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

    var itemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("vigil.settings.pane.\(rawValue)")
    }

    init?(itemIdentifier: NSToolbarItem.Identifier) {
        guard let match = Self.allCases.first(where: { $0.itemIdentifier == itemIdentifier }) else {
            return nil
        }
        self = match
    }
}
