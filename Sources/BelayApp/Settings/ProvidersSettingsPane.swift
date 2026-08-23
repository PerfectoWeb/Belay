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
            SettingsGroup {
                SettingRow(
                    title: "Built in",
                    explanation: """
                        Belay reads these agents' own session files. Switch on the ones you use; \
                        a switched-off agent is never watched and never asked about.
                        """
                ) {
                    builtIn
                }
                if showsPreciseNote {
                    preciseRow
                }
            }
            Divider()

            GenericTargetsSection(targets: $targets)
        }
        .onChange(of: targets) { _, new in onTargetsChanged(new) }
        .sheet(isPresented: $showingPreview) {
            HookPreviewSheet(precise: precise) { refreshToken += 1 }
        }
        .id(refreshToken)
    }

    /// Only when the hooks could actually be installed: a sentence about a
    /// control that is not there is a sentence about nothing.
    private var showsPreciseNote: Bool {
        guard PreciseDetection.isSupported,
            let claude = state.providers.first(where: { $0.descriptor.supportsPreciseDetection }),
            claude.isEnabled
        else { return false }
        if case .ready = claude.availability { return true }
        return false
    }

    /// The two agents Belay understands natively, side by side, each with
    /// its switch. Only those two: the "other agents" provider that backs
    /// the tools below is not a tile here.
    private var builtIn: some View {
        HStack(alignment: .top, spacing: TargetTileMetrics.spacing) {
            ForEach(state.providers.filter { $0.id == .claudeCode || $0.id == .codex }) { provider in
                BuiltInProviderTile(
                    provider: provider,
                    onToggle: { state.onToggleProvider(provider.id, $0) },
                    onFix: { state.onGrantAccess(provider.id) })
            }
        }
    }

    /// Precise detection as its own row again, under the tiles: a crosshair
    /// menu inside the Claude Code tile was tried and read as nothing at
    /// all. The row is only there when it could do something.
    @ViewBuilder
    private var preciseRow: some View {
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
