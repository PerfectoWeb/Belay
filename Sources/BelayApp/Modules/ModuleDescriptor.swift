import BelayChannel
import BelayModules
import SwiftUI

/// What Settings ▸ Modules shows about one module before it is installed.
///
/// The text lives in the string catalogue like every other string, so a module
/// is translated, reviewed and checked by the gate the same way the rest of the
/// interface is.
struct ModuleDescriptor: Identifiable {
    let id: ModuleID
    let symbol: String
    /// The icon tile's colour, one per module so the list reads at a glance.
    let tint: Color
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    /// Where the module can run at all. A module the sandbox forbids is not
    /// offered in the App Store build, rather than shown and greyed out.
    let channels: Set<DistributionChannel>

    static let screenshotCleaner = ModuleDescriptor(
        id: .screenshotCleaner,
        symbol: "camera.viewfinder",
        tint: Color(red: 0.36, green: 0.68, blue: 0.80),
        title: "Screenshot Cleaner",
        summary: "Moves old screenshots to the Trash, so the desktop stays clear.",
        channels: [.direct, .appStore]
    )

    static let micKeepWarm = ModuleDescriptor(
        id: .micKeepWarm,
        symbol: "mic",
        tint: Color(red: 0.90, green: 0.55, blue: 0.50),
        title: "Warm Microphone",
        summary: "Holds the microphone open, so dictation hears your first word.",
        channels: [.direct, .appStore]
    )

    /// Direct build only: pressing a button in another app is what the
    /// sandbox exists to forbid.
    static let autoAllow = ModuleDescriptor(
        id: .autoAllow,
        symbol: "checkmark.shield",
        tint: Color(red: 0.42, green: 0.72, blue: 0.56),
        title: "Auto Allow",
        summary: "Presses Allow once in Claude and Codex for requests about your local sites.",
        channels: [.direct]
    )

    static let nudge = ModuleDescriptor(
        id: .nudge,
        symbol: "bell.badge",
        tint: Color(red: 0.91, green: 0.69, blue: 0.40),
        title: "Nudge",
        summary: "A sound and a reminder when an agent finishes or waits for you.",
        channels: [.direct, .appStore]
    )

    /// Both builds list what was left behind; ending a process is for the
    /// direct build, since the sandbox lets no signal out.
    static let orphanWatch = ModuleDescriptor(
        id: .orphanWatch,
        symbol: "point.3.connected.trianglepath.dotted",
        tint: Color(red: 0.62, green: 0.58, blue: 0.86),
        title: "Orphan Watch",
        summary: "Finds what an agent left running after its session ended.",
        channels: [.direct, .appStore]
    )

    static let all: [ModuleDescriptor] = [
        .screenshotCleaner, .micKeepWarm, .autoAllow, .nudge, .orphanWatch
    ]

    static func offered(in channel: DistributionChannel = .current) -> [ModuleDescriptor] {
        all.filter { $0.channels.contains(channel) }
    }

    /// What the search field reads: the text as the user sees it, in the
    /// language the app is running in.
    var searchable: [String] {
        [String(localized: title), String(localized: summary)]
    }
}
