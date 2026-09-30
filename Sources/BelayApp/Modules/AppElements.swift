import ApplicationServices
import BelayModules
import os

#if !BELAY_MAS
/// Reading an app's window: what an element of it says and holds.
extension AXUIElement {
    func value(_ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    func string(_ attribute: String) -> String {
        value(attribute) as? String ?? ""
    }

    func elements(_ attribute: String) -> [AXUIElement] {
        value(attribute) as? [AXUIElement] ?? []
    }

    /// An app's windows, the one on another desktop included. The window
    /// list leaves that one out, while the app still answers for its main and
    /// focused window: without them every request waited for as long as the
    /// person worked on another desktop (found 2026-09-30).
    var reachableWindows: [AXUIElement] {
        var windows = elements(kAXWindowsAttribute)
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            guard let window = element(attribute) else { continue }
            if !windows.contains(where: { CFEqual($0, window) }) { windows.append(window) }
        }
        return windows
    }

    /// The element an attribute names, when it names one.
    func element(_ attribute: String) -> AXUIElement? {
        guard let found = value(attribute), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(found, to: AXUIElement.self)
    }

    /// A card that was answered leaves the page, and its button with it.
    var isStillThere: Bool {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, kAXRoleAttribute as CFString, &value)
        return result == .success
    }

    /// What the element is called, wherever it keeps that.
    var label: String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .lazy.map { self.string($0) }.first { !$0.isEmpty } ?? ""
    }

    /// The names the page gives the element.
    var classes: [String] {
        value("AXDOMClassList") as? [String] ?? []
    }

    /// The first element below this one that fits, the element itself left
    /// out. A card or a row is a few dozen elements; the limit is for a page
    /// that is not what it was taken for.
    func firstBelow(depth: Int = 8, where fits: (AXUIElement) -> Bool) -> AXUIElement? {
        guard depth > 0 else { return nil }
        for child in elements(kAXChildrenAttribute) {
            if fits(child) { return child }
            if let found = child.firstBelow(depth: depth - 1, where: fits) { return found }
        }
        return nil
    }
}

/// What the last look could see of an app, written to the log when it
/// changes. "No requests came" and "Belay could not see the window" look the
/// same from the outside, and only this line tells them apart in a report.
enum AppSight {
    private static let last = OSAllocatedUnfairLock(initialState: [AutoAllowRules.App: String]())

    static func say(_ seen: String, of app: AutoAllowRules.App) {
        let isNews = last.withLock { last in
            defer { last[app] = seen }
            return last[app] != seen
        }
        if isNews { Diagnostics.appendFromAnywhere("autoallow sees \(seen)") }
    }
}
#endif
