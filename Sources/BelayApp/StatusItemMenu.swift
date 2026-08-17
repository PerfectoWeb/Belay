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
        if let status = updateStatus() {
            menu.addItem(
                item(
                    status.title, #selector(runUpdate),
                    symbol: status.waiting ? "arrow.down.circle.fill" : "arrow.down.circle"))
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
