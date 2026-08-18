import BelaySettings
import SwiftUI

/// The night-dimming rows inside the "While holding" group: the switch, the
/// window and how far down to go. Sits directly under "Also keep the display
/// awake" because it only ever acts while that hold is the reason the screen
/// is lit — with the display allowed to sleep there is nothing to dim.
struct NightDimmingGroup: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        GroupedCheckbox(
            title: "Dim the display at night",
            explanation: """
                When you step away at night, Belay dims the display to this \
                level. It brightens again when you return.
                """,
            isOn: $settings.nightDimming
        )
        .disabled(!settings.keepDisplayAwake)

        if settings.nightDimming && settings.keepDisplayAwake {
            HStack(spacing: 8) {
                // The dash says "from here to here" without a word of chrome;
                // verbatim, so the catalogue never sees it and the no-dash
                // import rule stays about translations. `fixedSize` keeps each
                // field at the size of its own digits — a widened frame drew
                // the steppers adrift of their numbers.
                DatePicker(
                    selection: minutes($settings.nightDimmingStart),
                    displayedComponents: .hourAndMinute
                ) {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Dim from")
                Text(verbatim: "–").foregroundStyle(.secondary)
                DatePicker(
                    selection: minutes($settings.nightDimmingEnd),
                    displayedComponents: .hourAndMinute
                ) {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Dim until")

                Slider(value: $settings.nightDimmingLevel, in: 0.10...0.60, step: 0.05)
                    .controlSize(.small)
                    .frame(width: 110)
                    .accessibilityLabel("Dimmed brightness")
                Text(verbatim: settings.nightDimmingLevel.formatted(.percent))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
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

}
