import AppKit

/// The folder picker the modules share.
///
/// A sheet on the Settings window, never `runModal()`, for the reasons
/// `GenericTargetsSection` found the hard way: a modal session freezes the
/// panel behind it, and in the sandboxed build the call is a synchronous round
/// trip to the open-and-save service.
@MainActor
enum ModuleFolderPanel {
    static func pick(message: String, startingAt folder: URL, then adopt: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.message = message
        panel.prompt = String(localized: "Choose")

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            adopt(url)
        }
        NSApp.activate(ignoringOtherApps: true)
        // Visible, not merely first: a closed settings window lingers in
        // `NSApp.windows` wearing the same identifier.
        let host = NSApp.windows.first {
            $0.identifier == SettingsWindow.windowIdentifier && $0.isVisible
        }
        guard let host else {
            panel.begin(completionHandler: finish)
            return
        }
        panel.beginSheetModal(for: host, completionHandler: finish)
    }
}
