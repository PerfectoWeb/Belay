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
                    Nothing is sent anywhere, ever. If something goes wrong, \
                    opening an issue and attaching this file is what turns it \
                    into a fix. Sharing it is your decision, every time.
                    """,
                spokenLabel: "Keep local crash reports",
                isOn: $settings.keepLocalReports
            )

            HStack(spacing: 8) {
                Button("Show Reports…") {
                    NSWorkspace.shared.activateFileViewerSelecting([Diagnostics.file])
                }
                .disabled(!settings.keepLocalReports)

                // Beside the file rather than only on the About page: the
                // moment somebody has a report in their hand is the moment
                // they might send it, and hunting for where to send it is
                // where that intention dies.
                if let issues = Branding.issuesURL {
                    Link("Report an Issue…", destination: issues)
                }
            }
            .controlSize(.small)
        }
        .onChange(of: settings.keepLocalReports) { _, on in
            Diagnostics.setEnabled(on)
        }
    }
}
