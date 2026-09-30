import ApplicationServices
import BelayModules
import os

#if !BELAY_MAS
/// Reading the Claude window: what an element of it says and holds.
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
            guard let found = value(attribute), CFGetTypeID(found) == AXUIElementGetTypeID()
            else { continue }
            let window = unsafeDowncast(found, to: AXUIElement.self)
            if !windows.contains(where: { CFEqual($0, window) }) { windows.append(window) }
        }
        return windows
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

    /// A row of the session list: a button that holds a badge and then a
    /// title, and says both. The badge is drawn; a button in a conversation
    /// that reads the same way holds plain text, and is no session.
    var sessionRow: ListedSession? {
        let label = label
        guard label.contains(" "), let badge = elements(kAXChildrenAttribute).first,
            badge.string(kAXRoleAttribute) != kAXStaticTextRole
        else { return nil }
        return ListedSession(label: label, mark: badge.label)
    }

    var isCard: Bool {
        let classes = value("AXDOMClassList") as? [String] ?? []
        return classes.contains(ClaudeDesktopScreen.cardClass)
    }
}
/// What the last look could see of Claude, written to the log when it
/// changes. "No requests came" and "Belay could not see the window" look the
/// same from the outside, and only this line tells them apart in a report.
enum ClaudeSight {
    private static let last = OSAllocatedUnfairLock(initialState: "")

    static func say(_ seen: String) {
        let isNews = last.withLock { last in
            defer { last = seen }
            return last != seen
        }
        if isNews { Diagnostics.appendFromAnywhere("autoallow sees \(seen)") }
    }
}
#endif
