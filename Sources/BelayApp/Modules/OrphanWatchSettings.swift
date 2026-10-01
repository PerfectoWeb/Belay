import BelayModules
import SwiftUI

/// The orphan watch's settings and its list, shown inside its card.
struct OrphanWatchSettings: View {
    @Bindable var watcher: OrphanWatcher
    var onRemove: () -> Void
    #if !BELAY_MAS
    @State var asking: Ask?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
            ModuleRow(title: "Left behind") { leftBehindList }

            if !watcher.findings.hot.isEmpty {
                ModuleRow(title: "Running hot") { hotList }
            }

            ModuleRow(title: nil) {
                VStack(alignment: .leading, spacing: SettingsMetrics.rowSpacing) {
                    GroupedCheckbox(
                        title: "Tell me when something is left behind",
                        isOn: $watcher.rules.notifies
                    )
                    GroupedCheckbox(
                        title: "List processes running hot",
                        explanation: """
                            A process an agent started that keeps a core busy \
                            while none of the sessions of that agent is working.
                            """,
                        isOn: $watcher.rules.watchesSpinning
                    )
                }
            }

            if watcher.rules.watchesSpinning {
                ModuleRow(title: "Average use above") {
                    Picker(selection: $watcher.rules.spinningPercent) {
                        ForEach(OrphanRules.percents, id: \.self) { percent in
                            Text(verbatim: "\(percent)%").tag(percent)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                ModuleRow(title: "Measured over") {
                    Picker(selection: $watcher.rules.spinningMinutes) {
                        ForEach(OrphanRules.minutes, id: \.self) { minutes in
                            Text(verbatim: Self.spelled(minutes)).tag(minutes)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            ModuleRow(title: "Ignored") { ignoredList }

            ModuleRow(title: nil) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        """
                        Checked once a minute. Belay reads the names and numbers \
                        of processes that an agent started while its session was \
                        running, never what they were asked to do or which files \
                        they use. It remembers them only while Belay runs, and \
                        Belay never ends anything by itself.
                        """
                    )
                    if !watcher.agentsLeftAlone.isEmpty {
                        Self.leftAlone(watcher.agentsLeftAlone.map(\.displayName))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Remove Module", role: .destructive) { onRemove() }
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
        #if !BELAY_MAS
        .alert(alertTitle, isPresented: isAsking) {
            Button("End", role: .destructive) { confirm() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        #endif
    }

    /// The agents Belay leaves alone because they are switched off in Agents.
    static func leftAlone(_ names: [String]) -> Text {
        guard names.count > 1 else {
            return Text("\(names.first ?? "") is switched off in Agents.")
        }
        return Text("\(names[0]) and \(names[1]) are switched off in Agents.")
    }

    /// "10 minutes", in the app's language, by the system's formatter.
    static func spelled(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.minutes], width: .wide, maximumUnitCount: 1))
    }
}
