import AppKit
import SwiftUI

/// An hour-and-minute field with its digits actually centred.
///
/// The system control cannot do this: `NSDatePicker`'s cell ignores
/// `alignment` and pins its digits to the top-left of however wide a bezel it
/// is given — verified by rendering it headless at three widths. So the
/// composite comes apart: the digits are a bare, bezel-less `NSDatePicker`
/// (keyboard editing, per-segment selection and arrow keys all intact), the
/// bezel is ours and centres them both ways, and the stepper beside it walks
/// the whole time in quarter-hour steps, which is the grain a night window is
/// actually set in.
struct ClockField: View {
    @Binding var minutes: Int

    private static let bezel = CGSize(width: 56, height: 22)

    var body: some View {
        HStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                    )
                BareClock(minutes: $minutes)
                    .fixedSize()
            }
            .frame(width: Self.bezel.width, height: Self.bezel.height)
            Stepper {
                EmptyView()
            } onIncrement: {
                minutes = (minutes + 15) % (24 * 60)
            } onDecrement: {
                minutes = (minutes + 24 * 60 - 15) % (24 * 60)
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }
}

/// The digits alone: no bezel, no background, no stepper.
private struct BareClock: NSViewRepresentable {
    @Binding var minutes: Int

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.font = .systemFont(ofSize: NSFont.systemFontSize)
        picker.isBezeled = false
        picker.isBordered = false
        picker.drawsBackground = false
        picker.focusRingType = .none
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }

    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.minutes = $minutes
        let shown = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        let held = (shown.hour ?? 0) * 60 + (shown.minute ?? 0)
        guard held != minutes else { return }
        picker.dateValue =
            Calendar.current.date(
                bySettingHour: minutes / 60, minute: minutes % 60, second: 0,
                of: Date()) ?? Date()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(minutes: $minutes)
    }

    final class Coordinator: NSObject {
        var minutes: Binding<Int>

        init(minutes: Binding<Int>) {
            self.minutes = minutes
        }

        @objc func changed(_ picker: NSDatePicker) {
            let parts = Calendar.current.dateComponents(
                [.hour, .minute], from: picker.dateValue)
            minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
    }
}
