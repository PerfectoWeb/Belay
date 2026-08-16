import AppKit
import BelaySettings
import SwiftUI

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
                                    ? "Belay has to reopen to change language."
                                    : "Quit Belay and open it again to change language."
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
                    explanation: "Belay is only useful when it is already running.",
                    spokenLabel: "Open Belay at login",
                    isOn: loginItem.binding
                )
                if let problem = loginItem.problem {
                    LoginItemProblemRow(problem: problem)
                }
            }

            Divider()
            if ReleaseChecker.isSupported {
                UpdatesRow(checker: updates)
            } else {
                AppStoreUpdatesRow()
            }

            Divider()

            SettingCheckboxGroup(title: "Sound") {
                GroupedCheckbox(
                    title: "Play sounds",
                    explanation: """
                        A short note when you change mode by hand. Turning off \
                        interface sounds in System Settings silences these too.
                        """,
                    spokenLabel: "Play interface sounds",
                    isOn: $settings.soundEffects
                )
                // Switching it on plays one, so the setting can be judged where
                // it is set rather than by going and changing a mode.
                .onChange(of: settings.soundEffects) { _, on in
                    if on { Feedback.play(.tick) }
                }
            }

            Divider()

            SettingCheckboxGroup(title: "While holding") {
                GroupedCheckbox(
                    title: "Also keep the display awake",
                    explanation: """
                        Off by default. Belay keeps the Mac running while your agent works; \
                        letting the screen sleep saves real power and changes nothing else.
                        """,
                    isOn: $settings.keepDisplayAwake
                )
            }
        }
    }
}

/// What the App Store build shows where the update check would be.
///
/// It cannot check for itself: that build ships without an outbound network
/// entitlement, which is also the evidence handed to App Review about the
/// loopback listener, and buying a version check with it would be a poor
/// trade. What it can do is say where updates come from and open the place
/// they arrive, which is a hand-off to another app rather than a request.
///
/// The alternative was leaving a hole where the row is on the other channel.
/// A user who cannot find out whether they are current assumes they are not.
private struct AppStoreUpdatesRow: View {
    var body: some View {
        SettingCheckboxGroup(title: "Software updates") {
            Text(
                """
                The App Store keeps Belay up to date and tells you when a new \
                version is ready. Belay itself never connects out to the internet.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let store = Branding.appStoreURL {
                Button("Open the App Store") {
                    Feedback.play(.tick)
                    NSWorkspace.shared.open(store)
                }
                .controlSize(.small)
            }
        }
    }
}

/// The updates block.
///
/// On by default, and the caption says what it costs in one line rather than
/// burying it:
/// this is the only network access in the app.
private struct UpdatesRow: View {
    @Bindable var checker: ReleaseChecker

    var body: some View {
        SettingCheckboxGroup(title: "Software updates") {
            GroupedCheckbox(
                title: "Check for updates automatically",
                explanation: """
                    Once a day, Belay checks whether a newer version exists. \
                    That is the only time Belay uses the network, it sends nothing \
                    about you, and it never installs anything on its own.
                    """,
                spokenLabel: "Check for updates automatically",
                isOn: $checker.isAutomatic
            )

            HStack(spacing: 8) {
                // One button, two jobs. With nothing to install it checks;
                // with something, it becomes the way to get it. A separate
                // "Download…" beside an unchanged "Check Now" read as two
                // controls with no relationship, and put the thing you want
                // second.
                if case .available(_, let url) = checker.status {
                    Button {
                        Feedback.play(.tick)
                        // Sparkle where there is one: progress, a signature
                        // check over the bytes, the swap, the relaunch. Opening
                        // the URL is what a build without Sparkle can do.
                        if SoftwareUpdate.isSupported {
                            SoftwareUpdate.install()
                        } else {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        // The welcome screen's wand, and only here. "Check
                        // Now" is a question; this is the answer arriving.
                        Label("Update Now", systemImage: "wand.and.stars")
                    }
                    .controlSize(.small)
                    .tint(.green)
                    .buttonStyle(.borderedProminent)
                    // Fully rounded, like the Donate button in About. Only the
                    // shape: the tint, the size and the label stay as they are.
                    .buttonBorderShape(.capsule)
                } else {
                    Button("Check Now") {
                        Feedback.play(.tick)
                        checker.check()
                    }
                    .controlSize(.small)
                    .disabled(checker.status == .checking)
                }
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
            Label("Belay is up to date.", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)
        case .available(let version, _):
            // No link here any more: the button beside this is the link.
            Text("Version \(version) is available.").font(.caption)
        case .noneYet:
            // Deliberately as quiet as "up to date": nothing is wrong.
            Text("No releases have been published yet.")
                .font(.caption).foregroundStyle(.secondary)
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
