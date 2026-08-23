import AppKit
import Foundation

/// The dialog behind "Custom…": one field, typed the way people say it.
///
/// Accepts `1:30`, `90`, `90m`, `1h 30m`, `2h`, `45 min` — a number alone is
/// minutes, because that is what somebody who just typed "20" meant. The
/// parse is a pure function so the tests can hold it to that; the sheet is
/// an `NSAlert`, the one standard dialog a menu bar app can put up without
/// building a window for it.
enum CustomDuration {
    /// Seconds, or nil when the text is not a length. Bounded to a minute
    /// through a day: below a minute the hold is not worth a timer, above a
    /// day "until turned off" is the honest choice.
    static func parse(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        var minutes: Double?
        if let colon = trimmed.firstIndex(of: ":") {
            guard let hours = Double(trimmed[..<colon].trimmingCharacters(in: .whitespaces)),
                let mins = Double(
                    trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            else { return nil }
            minutes = hours * 60 + mins
        } else {
            var total = 0.0
            var matched = false
            let scanner = Scanner(string: trimmed)
            scanner.charactersToBeSkipped = .whitespaces
            while !scanner.isAtEnd {
                guard let number = scanner.scanDouble() else { return nil }
                let unit = scanner.scanCharacters(from: .letters) ?? "m"
                switch unit {
                case "h", "hr", "hrs", "hour", "hours", "ч": total += number * 60
                case "m", "min", "mins", "minute", "minutes", "м", "мин": total += number
                default: return nil
                }
                matched = true
            }
            minutes = matched ? total : nil
        }
        guard let minutes, minutes >= 1, minutes <= 24 * 60 else { return nil }
        return (minutes * 60).rounded()
    }

    /// Puts the dialog up and hands back the length, or nil on cancel or on
    /// text that is not one.
    @MainActor
    static func ask(current: TimeInterval?) -> TimeInterval? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Keep your Mac awake for")
        alert.informativeText = String(localized: "Hours and minutes, like 1:30 or 90 min.")
        alert.addButton(withTitle: String(localized: "Start"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        field.placeholderString = "1:30"
        if let current {
            let minutes = Int(current / 60)
            field.stringValue = String(format: "%d:%02d", minutes / 60, minutes % 60)
        }
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return parse(field.stringValue)
    }
}
