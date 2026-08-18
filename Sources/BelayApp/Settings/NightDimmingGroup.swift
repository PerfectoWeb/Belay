import BelaySettings
import SwiftUI

/// The night-dimming rows inside the "While holding" group: the switch, the
/// window and how far down to go. Sits directly under "Also keep the display
/// awake" because it only ever acts while that hold is the reason the screen
/// is lit — with the display allowed to sleep there is nothing to dim.
struct NightDimmingGroup: View {
    @Bindable var settings: SettingsStore

    /// The offered white points. Labelled as percentages by the formatter, so
    /// the list adds no strings to translate.
    private static let levels: [Double] = [0.4, 0.25, 0.1]

    var body: some View {
        GroupedCheckbox(
            title: "Dim the screen at night",
            explanation: """
                When you step away at night, the lit screen fades to a glow \
                instead of lighting an empty room. It comes back the moment \
                you do.
                """,
            isOn: $settings.nightDimming
        )
        .disabled(!settings.keepDisplayAwake)

        if settings.nightDimming && settings.keepDisplayAwake {
            HStack(spacing: 12) {
                DatePicker(
                    selection: minutes($settings.nightDimmingStart),
                    displayedComponents: .hourAndMinute
                ) {
                    Text("From")
                }
                .accessibilityLabel("Dim from")
                DatePicker(
                    selection: minutes($settings.nightDimmingEnd),
                    displayedComponents: .hourAndMinute
                ) {
                    Text("Until")
                }
                .accessibilityLabel("Dim until")

                Picker(selection: nearestLevel) {
                    ForEach(Self.levels, id: \.self) { level in
                        Text(verbatim: level.formatted(.percent)).tag(level)
                    }
                } label: {
                    Text("Brightness")
                }
                .accessibilityLabel("Dimmed brightness")
                .fixedSize()
            }
            .font(.callout)
        }
    }

    /// Stored minutes-from-midnight, shown as a clock time. The date part is
    /// today's and discarded on the way back in; only the wall time matters.
    private func minutes(_ binding: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: binding.wrappedValue / 60,
                    minute: binding.wrappedValue % 60,
                    second: 0,
                    of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                binding.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }

    /// Reads as the nearest offered choice, exactly like the duration pickers:
    /// a stored value outside the list must not draw an empty box.
    private var nearestLevel: Binding<Double> {
        Binding(
            get: {
                Self.levels.min {
                    abs($0 - settings.nightDimmingLevel) < abs($1 - settings.nightDimmingLevel)
                } ?? settings.nightDimmingLevel
            },
            set: { settings.nightDimmingLevel = $0 })
    }
}
