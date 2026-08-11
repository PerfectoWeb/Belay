import SwiftUI
import VigilSettings

struct GeneralSettingsPane: View {
    @Bindable var settings: SettingsStore
    var loginItem: LoginItem
    var updates: ReleaseChecker
    @State private var language = AppLanguage.selected()

    var body: some View {
        Group {
            SettingRow(title: "Language") {
                VStack(alignment: .leading, spacing: 7) {
                    Picker("Language", selection: $language) {
                        ForEach(AppLanguage.offered) { option in
                            Text(verbatim: option.endonym).tag(option)
                            if option == .system { Divider() }
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsMetrics.controlWidth, alignment: .leading)
                    .onChange(of: language) { _, chosen in AppLanguage.select(chosen) }

                    if AppLanguage.needsRelaunch(for: language) {
                        HStack(spacing: 8) {
                            if Relaunch.isAvailable {
                                Button("Quit and Reopen") { Relaunch.now() }
                                    .controlSize(.small)
                                    .buttonStyle(.borderedProminent)
                            }
                            Text(
                                Relaunch.isAvailable
                                    ? "Vigil has to reopen to change language."
                                    : "Quit Vigil and open it again to change language."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            SettingCheckboxGroup(title: "Startup") {
                GroupedCheckbox(
                    title: "Open at login",
                    explanation: "Vigil is only useful when it is already running.",
                    spokenLabel: "Open Vigil at login",
                    isOn: loginItem.binding
                )
                if let problem = loginItem.problem {
                    LoginItemProblemRow(problem: problem)
                }
            }

            if ReleaseChecker.isSupported {
                Divider()
                UpdatesRow(checker: updates)
            }

            Divider()

            SettingCheckboxGroup(title: "While holding") {
                GroupedCheckbox(
                    title: "Also keep the display awake",
                    explanation: """
                        Off by default. Vigil keeps the Mac running while your agent works; \
                        letting the screen sleep saves real power and changes nothing else.
                        """,
                    isOn: $settings.keepDisplayAwake
                )
            }
        }
    }
}

/// The updates block.
///
/// Off by default, and the caption says why in one line rather than burying it:
/// this is the only network access in the app, and the About pane promises
/// there is none.
private struct UpdatesRow: View {
    @Bindable var checker: ReleaseChecker

    var body: some View {
        SettingCheckboxGroup(title: "Software updates") {
            GroupedCheckbox(
                title: "Check for updates automatically",
                explanation: """
                    Once a day, Vigil asks GitHub whether a newer version exists. \
                    That is the only time Vigil uses the network, it sends nothing \
                    about you, and it never installs anything on its own.
                    """,
                spokenLabel: "Check for updates automatically",
                isOn: $checker.isAutomatic
            )

            HStack(spacing: 8) {
                Button("Check Now") { checker.check() }
                    .controlSize(.small)
                    .disabled(checker.status == .checking)
                status
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch checker.status {
        case .never:
            Text("Never checked.").font(.caption).foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            }
        case .upToDate:
            Label("Vigil is up to date.", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .available(let version, let url):
            HStack(spacing: 6) {
                Text("Version \(version) is available.").font(.caption)
                Link("Download…", destination: url).font(.caption)
            }
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange).lineLimit(2)
        }
    }
}

/// What to say when macOS will not take the change.
///
/// Both cases end in the same place, so both offer the same way there rather
/// than telling the user to go and find it: an instruction the app could have
/// followed itself is a bad instruction.
private struct LoginItemProblemRow: View {
    let problem: LoginItem.Problem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message)
                .font(.caption)
                .foregroundStyle(problem == .needsApproval ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Login Items…") { LoginItem.openSystemSettings() }
                .controlSize(.small)
        }
    }

    private var message: LocalizedStringKey {
        switch problem {
        case .needsApproval:
            return "macOS is waiting for you to allow this in System Settings."
        case .refused(let reason):
            return "macOS refused the change: \(reason)"
        }
    }
}
