import BelayChannel
import BelayModules
import Foundation

/// What Settings ▸ Modules shows about one module before it is installed.
///
/// The text lives in the string catalogue like every other string, so a module
/// is translated, reviewed and checked by the gate the same way the rest of the
/// interface is.
struct ModuleDescriptor: Identifiable {
    let id: ModuleID
    let symbol: String
    let title: LocalizedStringResource
    let summary: LocalizedStringResource
    /// Where the module can run at all. A module the sandbox forbids is not
    /// offered in the App Store build, rather than shown and greyed out.
    let channels: Set<DistributionChannel>

    static let screenshotCleaner = ModuleDescriptor(
        id: .screenshotCleaner,
        symbol: "camera.viewfinder",
        title: "Screenshot Cleaner",
        summary: """
            Moves old screenshots to the Trash, so the desktop stays clear while \
            you work with agents.
            """,
        channels: [.direct, .appStore]
    )

    static let micKeepWarm = ModuleDescriptor(
        id: .micKeepWarm,
        symbol: "mic",
        title: "Warm Microphone",
        summary: """
            Holds the microphone open, so dictation hears your first word \
            instead of waiting for the microphone to start.
            """,
        channels: [.direct, .appStore]
    )

    /// Direct build only: pressing a button in another app is what the
    /// sandbox exists to forbid.
    static let autoAllow = ModuleDescriptor(
        id: .autoAllow,
        symbol: "checkmark.shield",
        title: "Auto Allow",
        summary: """
            Presses Allow once in the Claude and Codex apps for you, so an \
            agent working on your local sites does not stop to ask.
            """,
        channels: [.direct]
    )

    static let all: [ModuleDescriptor] = [.screenshotCleaner, .micKeepWarm, .autoAllow]

    static func offered(in channel: DistributionChannel = .current) -> [ModuleDescriptor] {
        all.filter { $0.channels.contains(channel) }
    }

    /// What the search field reads: the text as the user sees it, in the
    /// language the app is running in.
    var searchable: [String] {
        [String(localized: title), String(localized: summary)]
    }
}
