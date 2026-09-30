import BelayModules
import SwiftUI

/// The automatic approval's settings, shown inside its card.
struct AutoAllowSettings: View {
    @Bindable var allower: AutoAllower
    var onRemove: () -> Void

    /// How many of the latest approvals the card has room for.
    private static let shown = 5

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            ModuleRow(title: "Approve") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(selection: $allower.rules.scope) {
                        Text("Requests for local sites").tag(AutoAllowRules.Scope.localSites)
                        Text("Everything the agent asks").tag(AutoAllowRules.Scope.everything)
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .fixedSize()
                    if allower.rules.scope == .everything {
                        Text(
                            """
                            Every request in the Claude and Codex apps is approved \
                            without you seeing it, commands and file changes \
                            included. \
                            Switch this on only for work you would approve \
                            without reading.
                            """
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ModuleRow(title: "Switch off after") {
                Picker(selection: $allower.rules.duration) {
                    ForEach(AutoAllowRules.durations, id: \.self) { duration in
                        Self.label(for: duration).tag(duration)
                    }
                } label: {
                    EmptyView()
                }
                .labelsHidden()
                .fixedSize()
            }

            ModuleRow(title: nil) {
                GroupedCheckbox(
                    title: "Answer in sessions behind the window",
                    explanation: """
                        Belay opens the session that waits, answers, and \
                        brings back the one you had open. It waits for a pause \
                        while you are typing or clicking.
                        """,
                    isOn: $allower.rules.reachesBehind
                )
            }

            ModuleRow(title: "Recently approved") {
                recent
            }

            ModuleRow(title: nil) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        """
                        Works in the Claude and Codex desktop apps. Local sites \
                        are localhost, names ending in .local or .test, and \
                        addresses on your own network. Everything else waits \
                        for you.
                        """
                    )
                    if !allower.appsLeftAlone.isEmpty {
                        Self.leftAlone(allower.appsLeftAlone)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if allower.standing == .needsAccess {
                    Button("Open Accessibility Settings") { PromptScreens.openSettings() }
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Remove Module", role: .destructive) { onRemove() }
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
    }

    /// Which apps Belay leaves alone because their agent is off.
    static func leftAlone(_ apps: [AutoAllowRules.App]) -> Text {
        let names = apps.map(\.agentName)
        guard names.count > 1 else {
            return Text("\(names.first ?? "") is switched off in Agents.")
        }
        return Text("\(names[0]) and \(names[1]) are switched off in Agents.")
    }

    @ViewBuilder private var recent: some View {
        if allower.log.entries.isEmpty {
            Text("Nothing yet.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(allower.log.entries.prefix(Self.shown)) { entry in
                    HStack(spacing: 8) {
                        Text(entry.date, format: .dateTime.hour().minute())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(verbatim: entry.subject)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    static func label(for duration: TimeInterval) -> Text {
        guard duration > 0 else { return Text("Never") }
        let spelled = Duration.seconds(duration).formatted(
            .units(allowed: [.hours], width: .wide, maximumUnitCount: 1))
        return Text(verbatim: spelled)
    }
}

extension AutoAllowRules.App {
    /// The agent behind the app, as the Agents pane names it.
    var agentName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}
