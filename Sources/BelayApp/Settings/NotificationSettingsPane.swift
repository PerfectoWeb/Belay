import BelaySettings
import SwiftUI

struct NotificationSettingsPane: View {
    @Bindable var settings: SettingsStore

    private var longRunExplanation: LocalizedStringKey {
        // Spelled units ("5 minutes"), localized by the formatter itself.
        let spelled = Duration.seconds(settings.taskFinishedThreshold)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2))
        return "For runs longer than \(spelled)."
    }

    var body: some View {
        Group {
            SettingCheckboxGroup(title: "Notifications") {
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
                        title: "Agent needs you",
                        explanation: """
                            An agent is waiting for permission or an answer. Requires \
                            Precise Detection.
                            """,
                        spokenLabel: "Notify when an agent needs you",
                        isOn: $settings.notifyOnAgentNeedsInput
                    )
                }

                GroupedCheckbox(
                    title: "Task finished",
                    explanation: longRunExplanation,
                    spokenLabel: "Notify when a long task finishes",
                    isOn: $settings.notifyOnTaskFinished
                )

                GroupedCheckbox(
                    title: "While you were away",
                    explanation: """
                        One summary when you come back: how long Belay held, and \
                        how many runs finished.
                        """,
                    spokenLabel: "Summarize what happened while you were away",
                    isOn: $settings.notifyOnAwaySummary
                )

                GroupedCheckbox(
                    title: "Agent went quiet",
                    explanation: """
                        A session stopped responding without finishing, usually because \
                        the CLI needs input or was closed.
                        """,
                    spokenLabel: "Notify when an agent goes quiet",
                    isOn: $settings.notifyOnAgentWentQuiet
                )

                GroupedCheckbox(
                    title: "New version",
                    explanation: """
                        Sent once per version. The menu bar icon still shows the update \
                        badge when this is off.
                        """,
                    spokenLabel: "Notify when a new version is out",
                    isOn: $settings.notifyOnUpdateAvailable
                )

                GroupedCheckbox(
                    title: "Safety stop",
                    explanation: "Low battery, overheating, or awake limit reached.",
                    spokenLabel: "Notify when Belay stops for safety",
                    isOn: $settings.notifyOnSafetyRelease
                )
            }

            Divider()

            SettingNote(
                text: "Belay asks for permission the first time it needs to send a notification."
            )
        }
    }
}
