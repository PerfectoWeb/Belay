import AppKit
import BelayModules
import SwiftUI

/// The nudge's settings, shown inside its card.
struct NudgeSettings: View {
    @Bindable var nudger: Nudger
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            ModuleRow(title: "Play a sound when") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("A run finishes", isOn: $nudger.rules.finishedSound)
                    Toggle("A session waits for you", isOn: $nudger.rules.waitingSound)
                    Toggle("A session goes quiet", isOn: $nudger.rules.quietSound)
                }
                .toggleStyle(.checkbox)
            }

            ModuleRow(title: "Show a banner when") {
                Toggle("A run finishes, naming its workspace", isOn: $nudger.rules.namesFinished)
                    .toggleStyle(.checkbox)
            }

            ModuleRow(title: "Remind again after") {
                Picker(selection: $nudger.rules.repeatAfterMinutes) {
                    ForEach(NudgeRules.repeatMinutes, id: \.self) { minutes in
                        Self.label(seconds: minutes * 60, never: minutes == 0).tag(minutes)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
            }

            ModuleRow(title: "Reminders per wait") {
                Picker(selection: $nudger.rules.repeatAtMost) {
                    ForEach(NudgeRules.repeatCounts, id: \.self) { count in
                        Text(verbatim: "\(count)").tag(count)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
                .disabled(nudger.rules.repeatAfterMinutes == 0)
            }

            ModuleRow(title: "Ignore runs shorter than") {
                Picker(selection: $nudger.rules.minimumRunSeconds) {
                    ForEach(NudgeRules.minimumRuns, id: \.self) { seconds in
                        Self.label(seconds: seconds, never: false).tag(seconds)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
            }

            ModuleRow(title: nil) {
                Text(
                    """
                    Reminders follow the first "An agent is waiting for you" \
                    banner from Notifications and stop when the session \
                    resumes. The finished banner is per session, so with \
                    "Your agent finished" also on you may get both. Clicking \
                    a banner brings forward the app the session lives in.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if nudger.notificationsRefused {
                    Button("Open Notification Settings") { Self.openNotificationSettings() }
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Remove Module", role: .destructive) { onRemove() }
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    private static func label(seconds: Int, never: Bool) -> Text {
        guard !never else { return Text("Never") }
        let spelled = Duration.seconds(seconds).formatted(
            .units(allowed: [.seconds, .minutes], width: .wide, maximumUnitCount: 1))
        return Text(verbatim: spelled)
    }

    private static func openNotificationSettings() {
        let link = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}
