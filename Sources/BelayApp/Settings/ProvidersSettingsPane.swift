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
                        Claude Code and Codex are understood natively: Belay reads their own \
                        session files and needs nothing configured.
                        """
                ) {
                    builtIn
                }
                if showsPreciseNote {
                    preciseNote
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
            let claude = state.providers.first(where: { $0.descriptor.supportsPreciseDetection })
        else { return false }
        if case .ready = claude.availability { return true }
        return false
    }

    /// Two tiles side by side, the grid the tools below use.
    private var builtIn: some View {
        HStack(alignment: .top, spacing: TargetTileMetrics.spacing) {
            ForEach(state.providers) { provider in
                BuiltInProviderTile(
                    provider: provider,
                    precise: provider.descriptor.supportsPreciseDetection ? precise : nil,
                    onEnablePrecise: { showingPreview = true },
                    onRemovePrecise: {
                        precise.uninstall()
                        refreshToken += 1
                    },
                    onFix: { state.onGrantAccess(provider.id) })
            }
            if state.providers.isEmpty {
                SettingNote(text: "No providers available.")
            }
        }
    }

    /// The sentence that used to sit on the precise-detection row, now under
    /// the tiles: the control moved into Claude Code's tile, the reason for
    /// it should not vanish with it.
    @ViewBuilder
    private var preciseNote: some View {
        SettingNote(
            text: """
                Precise detection lets Claude Code tell Belay exactly when it starts and stops, \
                instead of Belay inferring it from files. This is also what makes \
                "an agent is waiting for you" reliable.
                """)
        if let problem = precise.lastError {
            SettingNote(text: LocalizedStringKey(stringLiteral: problem), isProblem: true)
        }
    }

}
