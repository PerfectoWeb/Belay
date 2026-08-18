import AppKit
import BelaySettings
import SwiftUI

/// The switch that keeps a file of what went wrong, and the way to look at it.
///
/// Two controls, together: a log nobody can find is a log nobody sends, and the
/// button is the whole difference between "we collect diagnostics" and a person
/// being able to read what was collected before deciding to share it.
struct LocalReportsGroup: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        SettingCheckboxGroup(title: "Diagnostics") {
            GroupedCheckbox(
                title: "Keep local crash reports",
                explanation: """
                    Writes crashes, freezes and errors to a file on this Mac. \
                    Nothing is sent anywhere, and nothing is collected while \
                    this is off.
                    """,
                spokenLabel: "Keep local crash reports",
                isOn: $settings.keepLocalReports
            )

            Button("Show Reports…") {
                NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.file])
            }
            .controlSize(.small)
            .disabled(!settings.keepLocalReports)
        }
        .onChange(of: settings.keepLocalReports) { _, on in
            Diagnostics.setEnabled(on)
        }
    }
}
