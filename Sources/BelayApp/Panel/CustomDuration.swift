import AppKit
import Foundation

/// The dialog behind "Custom…": two small fields around a colon, hours and
/// minutes, digits only. The caret hops to the minutes by itself once the
/// hours are two digits — the way a date field behaves anywhere on a Mac.
enum CustomDuration {
    /// Seconds from the two fields, or nil when they do not make a length.
    /// Bounded to a minute through a day: below a minute the hold is not
    /// worth a timer, above a day "until turned off" is the honest choice.
    static func seconds(hours: String, minutes: String) -> TimeInterval? {
        guard hours.count <= 2, minutes.count <= 2 else { return nil }
        let wholeHours = Int(hours) ?? 0
        let spareMinutes = minutes.isEmpty ? 0 : Int(minutes) ?? -1
        guard wholeHours >= 0, (0...59).contains(spareMinutes) else { return nil }
        let total = wholeHours * 3600 + spareMinutes * 60
        guard total >= 60, total <= 24 * 3600 else { return nil }
        return TimeInterval(total)
    }

    /// Puts the dialog up and hands back the length, or nil on cancel or on
    /// fields that do not make one.
    @MainActor
    static func ask(current: TimeInterval?) -> TimeInterval? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Keep your Mac awake for")
        alert.informativeText = String(localized: "Hours and minutes.")
        alert.addButton(withTitle: String(localized: "Start"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let fields = DurationFields(current: current)
        alert.accessoryView = fields
        alert.window.initialFirstResponder = fields.hours
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return seconds(hours: fields.hours.stringValue, minutes: fields.minutes.stringValue)
    }
}

/// `[HH] : [MM]`. Each field takes at most two digits and nothing else; two
/// digits in the hours hand focus to the minutes.
final class DurationFields: NSView, NSTextFieldDelegate {
    let hours = NSTextField(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
    let minutes = NSTextField(frame: NSRect(x: 64, y: 0, width: 44, height: 24))

    init(current: TimeInterval?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 108, height: 24))
        let colon = NSTextField(labelWithString: ":")
        colon.frame = NSRect(x: 47, y: 2, width: 14, height: 20)
        colon.alignment = .center
        for field in [hours, minutes] {
            field.alignment = .center
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.delegate = self
        }
        hours.placeholderString = "1"
        minutes.placeholderString = "30"
        if let current {
            let total = Int(current / 60)
            hours.stringValue = String(total / 60)
            minutes.stringValue = String(format: "%02d", total % 60)
        }
        addSubview(hours)
        addSubview(colon)
        addSubview(minutes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DurationFields is built in code, never decoded") }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        // Digits only, two at most. Anything else never lands in the field —
        // the first version took a plain string and cheerfully accepted
        // "1:30cac".
        let digits = String(field.stringValue.filter(\.isNumber).prefix(2))
        if digits != field.stringValue { field.stringValue = digits }
        if field === hours, digits.count == 2 {
            window?.makeFirstResponder(minutes)
        }
    }
}
