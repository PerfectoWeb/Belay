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

    /// The non-optional twin of `offered`: a stored value from another build's
    /// list still has to land on a row this one draws.
    private func snapped(
        _ binding: Binding<TimeInterval>, to choices: [TimeInterval]
    ) -> Binding<TimeInterval> {
        Binding(
            get: { SettingsPresets.nearest(binding.wrappedValue, in: choices) },
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
                    // Shift reveals the long delays. See `RevealingPicker`
                    // for why they are not simply in the list.
                    RevealingPicker(
                        selection: snapped(
                            $settings.gracePeriod, to: SettingsPresets.allGracePeriods),
                        base: SettingsPresets.gracePeriods,
                        extended: SettingsPresets.longGracePeriods,
                        label: { DurationChoice.label($0) },
                        accessibilityLabel: String(localized: "Sleep delay"),
                        width: SettingsMetrics.controlWidth
                    )
                    .frame(maxWidth: SettingsMetrics.controlWidth, alignment: .leading)
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

            // Absent in the App Store build with the rest of Tier B: without
            // hooks no badge can ever appear, and a switch that does nothing
            // is worse than no switch.
            if PreciseDetection.isSupported {
                badgesGroup
            }
        }
    }

    private var badgesGroup: some View {
        SettingCheckboxGroup(title: "In the panel") {
            GroupedCheckbox(
                title: "Activity badges",
                explanation: """
                    Show what a working agent is doing – running a command, \
                    editing files – next to its state. Requires Precise \
                    Detection.
                    """,
                spokenLabel: "Show activity badges on sessions",
                isOn: $settings.showToolBadges
            )
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
