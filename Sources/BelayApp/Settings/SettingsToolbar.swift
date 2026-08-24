import AppKit

/// The Settings window's pane switcher.
///
/// A real `NSToolbar` in `.preference` style rather than a SwiftUI `TabView`:
/// unlike the SwiftUI control it cannot collapse into an overflow chevron or
/// resize the window behind our back. Split out of `SettingsWindow` only because
/// the window itself had grown past what one file should hold.
extension SettingsWindow: NSToolbarDelegate {
    private var paneIdentifiers: [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.itemIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        paneIdentifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane(itemIdentifier: itemIdentifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.title
        item.paletteLabel = pane.title
        item.toolTip = pane.title
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
        item.target = self
        item.action = #selector(toolbarItemSelected(_:))
        return item
    }
}

extension SettingsWindow {
    @objc private func toolbarItemSelected(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(itemIdentifier: sender.itemIdentifier) else { return }
        select(pane)
        bounceIcon(for: pane)
    }

    /// One bounce from the icon that was just chosen.
    ///
    /// AppKit offers no handle on the image view inside a standard toolbar
    /// item, so it is found: every item's image carries the pane's title as
    /// its accessibility description — set above, so this is a marker we own,
    /// not a guess about private classes. A hierarchy that hides the view
    /// from the walk simply means no bounce, which is the right failure.
    private func bounceIcon(for pane: SettingsPane) {
        guard let titlebar = window?.standardWindowButton(.closeButton)?.superview else { return }
        for view in Self.imageViews(under: titlebar)
        where view.image?.accessibilityDescription == pane.title {
            view.addSymbolEffect(.bounce, options: .nonRepeating)
        }
    }

    private static func imageViews(under view: NSView) -> [NSImageView] {
        view.subviews.flatMap { child -> [NSImageView] in
            var found = imageViews(under: child)
            if let image = child as? NSImageView { found.append(image) }
            return found
        }
    }
}
