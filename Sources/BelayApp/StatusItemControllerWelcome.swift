import AppKit

/// The workbench item in the status menu, and nothing else.
///
/// The welcome screen plays its greeting only on a fresh window, so watching it
/// twice means clearing a preference and relaunching the app. That is a slow
/// loop to iterate an animation in. These add two items to the menu that
/// re-present each window from its first frame.
///
/// The release notes have the same problem for a worse reason: they are shown
/// once per version ever, so the only other way to look at one is to edit a
/// preference and relaunch.
///
/// Debug builds only, and `StatusMenuTests` asserts that: the build other
/// people get should not offer to replay an introduction they have already been
/// through. It lives in its own file so that the menu itself stays the four
/// items it is supposed to be, in a file that is at its length limit.
#if DEBUG
extension StatusItemController {
    /// One row per workbench destination. Kept beside the actions rather than in
    /// the menu builder, which is in a file at its length limit.
    struct Workbench {
        let title: String
        let action: Selector
        let symbol: String
    }

    var workbenchItems: [Workbench] {
        [
            Workbench(title: "Welcome", action: #selector(showWelcome), symbol: "sparkles"),
            Workbench(title: "What's New", action: #selector(showWhatsNew), symbol: "gift")
        ]
    }

    @objc func showWelcome() {
        onShowWelcome()
    }

    @objc func showWhatsNew() {
        onShowWhatsNew()
    }
}
#endif
