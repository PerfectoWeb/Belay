import AppKit
import SwiftUI

/// The dialog behind "Custom…": a length, asked for either way round.
///
/// "For" takes hours and minutes; "Until" takes a wall-clock time and the
/// length is worked out from now. One footnote under the fields always shows
/// the other reading — set a duration and it names the end time, set an end
/// time and it names the duration — so both tabs answer both questions.
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

    /// Seconds from `now` to the next wall-clock `minutesOfDay`. A time
    /// already past means tomorrow, so "until 8:00" set at night does what
    /// it says; under a minute away falls below the timer's floor and is nil.
    static func untilSeconds(
        minutesOfDay: Int, now: Date = Date(), calendar: Calendar = .current
    ) -> TimeInterval? {
        guard (0..<24 * 60).contains(minutesOfDay) else { return nil }
        let start = calendar.startOfDay(for: now)
        guard var target = calendar.date(byAdding: .minute, value: minutesOfDay, to: start)
        else { return nil }
        if target <= now {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: target)
            else { return nil }
            target = tomorrow
        }
        let seconds = target.timeIntervalSince(now)
        guard seconds >= 60 else { return nil }
        return seconds
    }

    /// Puts the dialog up and hands the length to `completion`, or nil on
    /// cancel. Start stays disabled while the fields do not make a length.
    ///
    /// Given the panel's window it rides it as a sheet: the popover stays
    /// put underneath and the dialog reads as part of it, not as a stray
    /// window over whatever was behind. The panel is told first, because a
    /// transient popover would otherwise close the moment the sheet takes
    /// key and take the sheet down with it.
    @MainActor
    static func ask(
        current: TimeInterval?,
        over window: NSWindow?,
        completion: @escaping (TimeInterval?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Keep your Mac awake")
        alert.addButton(withTitle: String(localized: "Start"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let model = CustomDurationModel(current: current)
        let host = NSHostingView(rootView: CustomDurationView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 230, height: 92)
        alert.accessoryView = host
        let start = alert.buttons[0]
        model.onValidity = { start.isEnabled = $0 }
        start.isEnabled = model.result() != nil
        guard let window else {
            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            completion(response == .alertFirstButtonReturn ? model.result() : nil)
            return
        }
        NotificationCenter.default.post(name: .panelSheetWillOpen, object: nil)
        alert.beginSheetModal(for: window) { response in
            NotificationCenter.default.post(name: .panelSheetDidClose, object: nil)
            completion(response == .alertFirstButtonReturn ? model.result() : nil)
        }
    }
}

extension Notification.Name {
    /// A dialog is about to ride the panel as a sheet: hold the popover open.
    static let panelSheetWillOpen = Notification.Name("belay.panelSheetWillOpen")
    /// The sheet is gone; the popover may go back to closing itself.
    static let panelSheetDidClose = Notification.Name("belay.panelSheetDidClose")
}

/// The dialog's state, shared between the SwiftUI accessory and the AppKit
/// alert around it: every edit re-answers "do the fields make a length" so
/// the alert can keep Start honest.
@MainActor
final class CustomDurationModel: ObservableObject {
    enum Mode { case duration, until }

    @Published var mode: Mode = .duration { didSet { revalidate() } }
    @Published var hours: String { didSet { revalidate() } }
    @Published var minutes: String { didSet { revalidate() } }
    @Published var untilMinutes: Int { didSet { revalidate() } }

    var onValidity: (Bool) -> Void = { _ in }

    init(current: TimeInterval?, now: Date = Date(), calendar: Calendar = .current) {
        // Both tabs open ready to start: the running length if there is one,
        // an hour otherwise. A dialog of empty fields makes the user do the
        // typing before it does anything; a filled one is one Return away.
        let total = Int((current ?? 3600) / 60)
        hours = String(total / 60)
        minutes = String(format: "%02d", total % 60)
        // The clock opens on "now plus the length" rounded up to a quarter
        // hour: the number a person would have picked, one nudge from most
        // others they might want.
        let offset = Int((current ?? 3600) / 60)
        let nowMinutes =
            calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        untilMinutes = (nowMinutes + offset + 14) / 15 * 15 % (24 * 60)
    }

    func result(now: Date = Date()) -> TimeInterval? {
        switch mode {
        case .duration: return CustomDuration.seconds(hours: hours, minutes: minutes)
        case .until: return CustomDuration.untilSeconds(minutesOfDay: untilMinutes, now: now)
        }
    }

    private func revalidate() { onValidity(result() != nil) }
}
