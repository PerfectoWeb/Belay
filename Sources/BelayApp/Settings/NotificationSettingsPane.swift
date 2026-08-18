import BelaySettings
import SwiftUI

struct NotificationSettingsPane: View {
    @Bindable var settings: SettingsStore

    private var longRunExplanation: LocalizedStringKey {
        "Only for runs longer than \(ElapsedTime.compact(settings.taskFinishedThreshold))."
    }

    var body: some View {
        Group {
            SettingCheckboxGroup(title: "Notify me") {
                // Only where there is something that can raise it. "An agent is
                // waiting for you" is not something a transcript can say: the
                // classifier reads a file growing and a stop reason, which give
                // working or idle and nothing else. `awaitingUser` arrives from
                // the hook bridge alone, and the App Store build has none, so
                // this switch could be turned on there and never fire once.
                //
                // The other two are unaffected: a long task finishing is idle
                // after work, and a safety stop comes from the power layer.
                if PreciseDetection.isSupported {
                    GroupedCheckbox(
                        title: "When an agent needs you",
                        explanation: """
                            Your agent is blocked on a permission prompt or a question. \
                            This one needs precise detection turned on to be reliable.
                            """,
                        spokenLabel: "Notify when an agent needs you",
                        isOn: $settings.notifyOnAgentNeedsInput
                    )
                }

                GroupedCheckbox(
                    title: "When a long task finishes",
                    explanation: longRunExplanation,
                    spokenLabel: "Notify when a long task finishes",
                    isOn: $settings.notifyOnTaskFinished
                )

                GroupedCheckbox(
                    title: "When an agent goes quiet",
                    explanation: """
                        A session that stopped sending anything and never said it had finished. \
                        Usually a CLI that needs signing in again, or a closed terminal.
                        """,
                    spokenLabel: "Notify when an agent goes quiet",
                    isOn: $settings.notifyOnAgentWentQuiet
                )

                GroupedCheckbox(
                    title: "When a new version is out",
                    explanation: """
                        Once per version, never twice. The mark in the corner of the menu bar \
                        icon says the same thing quietly, whether this is on or off.
                        """,
                    spokenLabel: "Notify when a new version is out",
                    isOn: $settings.notifyOnUpdateAvailable
                )

                GroupedCheckbox(
                    title: "When Belay stops for safety",
                    explanation: "Low battery, or the maximum awake time was reached.",
                    spokenLabel: "Notify when Belay stops for safety",
                    isOn: $settings.notifyOnSafetyRelease
                )
            }

            Divider()

            SettingNote(
                text: "Belay asks macOS for permission the first time it actually needs to notify you."
            )
        }
    }
}
