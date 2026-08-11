import SwiftUI
import VigilCore
import VigilSettings

struct BehaviourSettingsPane: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Group {
            SettingsGroup {
                SettingRow(
                    title: "Wait before letting the Mac sleep",
                    explanation: """
                        How long Vigil keeps holding after your agent goes quiet. \
                        Longer is safer: sleeping mid-task costs far more than staying \
                        awake a minute too long.
                        """
                ) {
                    // An empty label, not a label that happens to be an
                    // empty string: the latter asks the catalogue for "".
                    Picker(selection: $settings.gracePeriod) {
                        ForEach(SettingsPresets.gracePeriods, id: \.self) { seconds in
                            Text(ElapsedTime.compact(seconds)).tag(seconds)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsMetrics.controlWidth, alignment: .leading)
                    .accessibilityLabel("Wait before letting the Mac sleep")
                }
            }

            Divider()

            SettingsGroup {
                SettingRow(
                    title: "Maximum time awake",
                    explanation: "A backstop. Vigil stops holding after this and tells you why."
                ) {
                    Picker(selection: $settings.maxContinuousAwake) {
                        ForEach(SettingsPresets.maxContinuousAwake, id: \.self) { limit in
                            Text(limit.map(ElapsedTime.compact) ?? String(localized: "Until turned off")).tag(
                                limit)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .frame(maxWidth: SettingsMetrics.controlWidth, alignment: .leading)
                    .accessibilityLabel("Maximum time awake")
                }

                SettingCheckbox(
                    title: "Stop on low battery",
                    explanation: batteryExplanation,
                    spokenLabel: "Stop keeping the Mac awake on low battery",
                    isOn: batteryGuard
                )

                SettingCheckbox(
                    title: "Shorten the wait in Low Power Mode",
                    explanation: "Your agent still finishes; Vigil just lets go sooner afterwards.",
                    isOn: $settings.shortenGraceInLowPower
                )
            }
        }
    }

    private var batteryExplanation: LocalizedStringKey {
        guard let floor = settings.batteryFloor else {
            return "Vigil will keep holding no matter how low the battery gets."
        }
        return "Below \(Int((floor * 100).rounded()))% on battery, Vigil stops holding."
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
