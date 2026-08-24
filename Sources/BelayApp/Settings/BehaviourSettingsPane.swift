import BelayCore
import BelaySettings
import SwiftUI

struct BehaviourSettingsPane: View {
    /// A binding that reads as the nearest offered choice.
    ///
    /// Belt to the migration's braces. A pop-up has a row per value and none for
    /// anything else, so a stored number outside the list draws an empty box —
    /// which is what a `defaults write`, a downgrade, or a list widened without
    /// a migration all produce. Writes pass straight through: what the user
    /// picks is always in the list by definition.
    private func offered(
        _ binding: Binding<TimeInterval>, _ choices: [TimeInterval]
    ) -> Binding<TimeInterval> {
        Binding(
            get: { SettingsPresets.nearest(binding.wrappedValue, in: choices) },
            set: { binding.wrappedValue = $0 })
    }

    private func offered(
        _ binding: Binding<TimeInterval?>, _ choices: [TimeInterval?]
    ) -> Binding<TimeInterval?> {
        Binding(
            get: {
                guard let value = binding.wrappedValue else { return nil }
                return SettingsPresets.nearest(value, in: choices.compactMap { $0 })
            },
            set: { binding.wrappedValue = $0 })
    }

    @Bindable var settings: SettingsStore

    var body: some View {
        Group {
            SettingsGroup {
                SettingRow(
                    title: "Sleep delay",
                    explanation: """
                        How long Belay waits after an agent goes quiet before letting \
                        your Mac sleep.
                        """
                ) {
                    // An empty label, not a label that happens to be an
                    // empty string: the latter asks the catalogue for "".
                    Picker(selection: offered($settings.gracePeriod, SettingsPresets.gracePeriods)) {
                        ForEach(SettingsPresets.gracePeriods, id: \.self) { seconds in
                            Text(verbatim: DurationChoice.label(seconds)).tag(seconds)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsMetrics.controlWidth, alignment: .leading)
                    .accessibilityLabel("Sleep delay")
                }
            }

            Divider()

            SettingsGroup {
                SettingRow(
                    title: "Awake limit",
                    explanation: """
                        The longest Belay will keep your Mac awake before letting go. \
                        You'll be notified when the limit is reached.
                        """
                ) {
                    Picker(
                        selection: offered(
                            $settings.maxContinuousAwake, SettingsPresets.maxContinuousAwake)
                    ) {
                        ForEach(SettingsPresets.maxContinuousAwake, id: \.self) { limit in
                            Text(verbatim: DurationChoice.label(limit)).tag(limit)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsMetrics.controlWidth, alignment: .leading)
                    .accessibilityLabel("Awake limit")
                }

                SettingCheckbox(
                    title: "Battery Guard",
                    explanation: batteryExplanation,
                    spokenLabel: "Stop keeping the Mac awake on low battery",
                    isOn: batteryGuard
                )

                SettingCheckbox(
                    title: "Low Power Mode",
                    explanation: "Shortens the sleep delay after your agent finishes.",
                    isOn: $settings.shortenGraceInLowPower
                )
            }

            Divider()

            // What a hold does to the machine while it runs — the display,
            // the night, the lid. Moved here from General because these are
            // holding behaviour, and General was becoming everything's drawer.
            SettingCheckboxGroup(title: "While holding") {
                GroupedCheckbox(
                    title: "Keep display awake",
                    explanation: """
                        Keeping the display off saves power and won't interrupt your agent.
                        """,
                    isOn: $settings.keepDisplayAwake
                )
                NightDimmingGroup(settings: settings)
                LidHoldGroup(settings: settings)
            }
        }
    }

    private var batteryExplanation: LocalizedStringKey {
        guard let floor = settings.batteryFloor else {
            return "Belay will keep holding no matter how low the battery gets."
        }
        return "On battery, Belay lets your Mac sleep at \(Int((floor * 100).rounded()))%."
    }

    /// Modelled as on/off rather than exposing the raw optional: `nil` means the
    /// guard is disabled, and the store keeps the last value so turning it back
    /// on restores the user's threshold instead of a default.
    private var batteryGuard: Binding<Bool> {
        Binding(
            get: { settings.batteryFloor != nil },
            set: { settings.batteryFloor = $0 ? (settings.batteryFloor ?? 0.20) : nil }
        )
    }
}
