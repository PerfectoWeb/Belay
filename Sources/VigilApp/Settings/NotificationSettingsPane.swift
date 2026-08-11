import SwiftUI
import VigilSettings

struct NotificationSettingsPane: View {
    @Bindable var settings: SettingsStore

    private var longRunExplanation: LocalizedStringKey {
        "Only for runs longer than \(ElapsedTime.compact(settings.taskFinishedThreshold))."
    }

    var body: some View {
        Group {
            SettingCheckboxGroup(title: "Notify me") {
                GroupedCheckbox(
                    title: "When an agent needs you",
                    explanation: """
                        Your agent is blocked on a permission prompt or a question. \
                        This one needs precise detection turned on to be reliable.
                        """,
                    spokenLabel: "Notify when an agent needs you",
                    isOn: $settings.notifyOnAgentNeedsInput
                )

                GroupedCheckbox(
                    title: "When a long task finishes",
                    explanation: longRunExplanation,
                    spokenLabel: "Notify when a long task finishes",
                    isOn: $settings.notifyOnTaskFinished
                )

                GroupedCheckbox(
                    title: "When Vigil stops for safety",
                    explanation: "Low battery, or the maximum awake time was reached.",
                    spokenLabel: "Notify when Vigil stops for safety",
                    isOn: $settings.notifyOnSafetyRelease
                )
            }

            Divider()

            SettingNote(
                text: "Vigil asks macOS for permission the first time it actually needs to notify you."
            )
        }
    }
}
