import AppKit

/// The workbench item in the status menu, and nothing else.
///
/// The welcome screen plays its greeting only on a fresh window, so watching it
/// twice means clearing a preference and relaunching the app. That is a slow
/// loop to iterate an animation in. This adds one item to the menu that
/// re-presents the window from its first frame.
///
/// Debug builds only, and `StatusMenuTests` asserts that: the build other
/// people get should not offer to replay an introduction they have already been
/// through. It lives in its own file so that the menu itself stays the four
/// items it is supposed to be, in a file that is at its length limit.
#if DEBUG
extension StatusItemController {
    @objc func showWelcome() {
        onShowWelcome()
    }
}
#endif
