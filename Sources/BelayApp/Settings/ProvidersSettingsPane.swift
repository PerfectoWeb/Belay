import BelayCore
import BelayProviders
import SwiftUI

struct ProvidersSettingsPane: View {
    var state: AppState
    var precise: PreciseDetection
    var onTargetsChanged: ([GenericTarget]) -> Void
    @State private var showingPreview = false
    @State private var refreshToken = 0
    @State private var targets: [GenericTarget]

    init(
        state: AppState,
        precise: PreciseDetection,
        targets: [GenericTarget],
        onTargetsChanged: @escaping ([GenericTarget]) -> Void
    ) {
        self.state = state
        self.precise = precise
        self.onTargetsChanged = onTargetsChanged
        _targets = State(initialValue: targets)
    }

    var body: some View {
        Group {
            ForEach(state.providers) { provider in
                providerGroup(provider)
                Divider()
            }

            if state.providers.isEmpty {
                SettingNote(text: "No providers available.")
                Divider()
            }

            GenericTargetsSection(targets: $targets)
        }
        .onChange(of: targets) { _, new in onTargetsChanged(new) }
        .sheet(isPresented: $showingPreview) {
            HookPreviewSheet(precise: precise) { refreshToken += 1 }
        }
        .id(refreshToken)
    }

    @ViewBuilder
    private func providerGroup(_ provider: ProviderStatus) -> some View {
        SettingsGroup {
            SettingRow(
                title: LocalizedStringKey(provider.descriptor.displayName),
                explanation: LocalizedStringKey(provider.descriptor.summary)
            ) {
                AvailabilityBadge(availability: provider.availability)
            }

            if let last = provider.lastSignal {
                // Risk R1: a silent detection regression is the failure users
                // cannot report. Make health visible.
                SettingRow(title: "Detection health") {
                    Text("last signal \(ElapsedTime.compact(-last.timeIntervalSinceNow)) ago")
                        .foregroundStyle(.secondary)
                }
            }

            if provider.descriptor.supportsPreciseDetection {
                preciseDetectionRow
            }
        }
    }

    @ViewBuilder
    private var preciseDetectionRow: some View {
        SettingRow(
            title: "Precise detection",
            explanation: """
                Lets Claude Code tell Belay exactly when it starts and stops, \
                instead of Belay inferring it from files. This is also what makes \
                "an agent is waiting for you" reliable.
                """
        ) {
            if precise.isInstalled {
                Button("Remove") {
                    precise.uninstall()
                    refreshToken += 1
                }
                .accessibilityHint("Removes Belay's entries from your Claude Code settings")
            } else {
                Button("Enable…") { showingPreview = true }
                    .accessibilityHint("Shows exactly what will be added before anything is written")
            }
        }

        if let problem = precise.lastError {
            SettingNote(text: LocalizedStringKey(stringLiteral: problem), isProblem: true)
        }
    }
}

private struct AvailabilityBadge: View {
    let availability: ProviderAvailability

    var body: some View {
        switch availability {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .needsSetup(let what):
            Label(what, systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        case .unavailable(let why):
            Label(why, systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }
}
