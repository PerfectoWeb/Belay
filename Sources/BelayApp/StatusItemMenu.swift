import AppKit
import BelaySupport

/// The right-click menu: what is in it, and how each row is built.
///
/// Split from `StatusItemController` on the seam between the two jobs that type
/// does. It owns the item, the click and the drawing; this owns the menu.
///
/// The action methods are internal rather than private because a `#selector`
/// has to see them from here. That costs nothing real: `@objc` already publishes
/// them to the Objective-C runtime, where `private` was never a boundary.
extension StatusItemController {

    /// The modes live in the panel a left-click away; duplicating them here made
    /// the menu look like a control surface when it is really just a way out.
    ///
    /// An ellipsis promises a dialog that will ask you for something before
    /// anything happens (HIG, "Menu Anatomy"). Statistics and About just show a
    /// pane, so they do not get one; Settings keeps it, because every macOS app
    /// spells it that way and matching the platform beats being right alone.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(
            item(
                String(localized: "Statistics"), #selector(openStatistics),
                symbol: SettingsPane.statistics.symbol))
        menu.addItem(
            item(
                String(localized: "Settings…"), #selector(openSettings), key: ",",
                symbol: SettingsPane.general.symbol))
        menu.addItem(
            item(
                String(localized: "About \(Branding.appName)"), #selector(openAbout),
                symbol: SettingsPane.about.symbol))
        // Fenced off above. The three rows before it go somewhere to look at
        // something; this one changes the app on disk, and in the shipping menu
        // the only other row that does anything irreversible is Quit, which has
        // a rule of its own below. The separator after it is the one already
        // there: the workbench block's in a debug build, Quit's in a release.
        if let status = updateStatus() {
            menu.addItem(.separator())
            menu.addItem(
                item(
                    status.title, #selector(runUpdate),
                    symbol: status.waiting ? "arrow.down.circle.fill" : "arrow.down.circle"))
            // Only when there is something to skip, and only ever next to the
            // row that installs it. A "skip" with nothing waiting is a control
            // that does nothing, and this menu has none of those.
            if status.waiting {
                menu.addItem(
                    item(
                        String(localized: "Skip This Version"), #selector(skipUpdate),
                        symbol: "xmark.circle"))
            }
        }
        #if DEBUG
        addWorkbench(to: menu)
        #endif

        menu.addItem(.separator())
        menu.addItem(
            item(
                // "Quit", not "Quit Belay": every other item in this menu is
                // already about Belay, and the app name is on the item above it.
                String(localized: "Quit"), #selector(confirmQuit), key: "q",
                symbol: "power"))
        return menu
    }

    @objc func runUpdate() { onUpdate() }

    /// Records the skip and redraws at once, because the dot going away is the
    /// only confirmation this row gives.
    @objc func skipUpdate() {
        onSkipUpdate()
        render()
    }

    func item(
        _ title: String, _ action: Selector, key: String = "", symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        // Menu-bar extras are the one place AppKit expects images on plain items,
        // and with four items of different weight the icons are what makes the
        // menu scannable rather than a list of words.
        item.image = symbol.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        }
        return item
    }
}
