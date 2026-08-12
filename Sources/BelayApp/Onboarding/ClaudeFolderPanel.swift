import AppKit

/// The standard open panel that turns "Belay would like to watch your agent"
/// into a grant macOS will honour.
///
/// It is deliberately a plain `NSOpenPanel` with no custom accessory view: the
/// answer `docs/APP-STORE.md` gives App Review is that access arrives through
/// the system panel and by no other means, and the panel a reviewer recognises
/// is the one that makes that obvious.
@MainActor
enum ClaudeFolderPanel {
    static func run(startingAt folder: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        // `.claude` is a dotfile. Without this the panel opens on a folder the
        // user cannot see, and the grant looks broken before it is refused.
        panel.showsHiddenFiles = true
        panel.directoryURL = folder
        panel.message = String(
            localized: "Let Belay read your ~/.claude folder so it can tell when Claude Code is working."
        )
        panel.prompt = String(localized: "Grant access to ~/.claude")

        // LSUIElement: without this the panel can open behind whatever the user
        // was doing, and a modal they cannot see is a hang as far as they know.
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
