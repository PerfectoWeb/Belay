import BelayCore
import BelayProviders
import SwiftUI

struct ProvidersSettingsPane: View {
    var state: AppState
    var precise: PreciseDetection
    var onTargetsChanged: ([GenericTarget]) -> Void
    var onReshaped: () -> Void = {}
    @State private var previewing: PreviewTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshToken = 0
    @State private var targets: [GenericTarget]

    /// `sheet(item:)` wants an identity; the provider is one.
    struct PreviewTarget: Identifiable {
        let id: ProviderID
    }

    init(
        state: AppState,
        precise: PreciseDetection,
        targets: [GenericTarget],
        onTargetsChanged: @escaping ([GenericTarget]) -> Void,
        onReshaped: @escaping () -> Void = {}
    ) {
        self.state = state
        self.precise = precise
        self.onTargetsChanged = onTargetsChanged
        self.onReshaped = onReshaped
        _targets = State(initialValue: targets)
    }

    var body: some View {
        Group {
            SettingsGroup {
                SettingRow(
                    title: "Built in",
                    explanation: """
                        Belay watches only the agents you turn on. Precise Detection \
                        gives Belay exact start, finish, and needs-you signals. \
                        Control-click an agent to remove it.
                        """
                ) {
                    builtIn
                }
                errorNotes
            }
            Divider()

            GenericTargetsSection(targets: $targets)
        }
        .onChange(of: targets) { _, new in onTargetsChanged(new) }
        // The built-in switches change what the pane holds — the status
        // lines, the precise-detection row — and the window has to follow,
        // the way it already follows the tiles below.
        .onChange(of: state.providers) { _, _ in onReshaped() }
        .sheet(item: $previewing) { target in
            HookPreviewSheet(precise: precise, provider: target.id) { refreshToken += 1 }
        }
        .id(refreshToken)
    }

    /// The agents Belay understands natively, two to a row, each with its
    /// switch. Rows of `HStack` rather than a grid because `SettingRow`
    /// aligns its label to the first text baseline, and a `LazyVGrid` answers
    /// that question with the wrong row. The "other agents" provider that
    /// backs the tools below is not a tile here.
    private var builtIn: some View {
        let tiles = state.providers.filter { $0.id != .generic }
        let rows: [[ProviderStatus]] = stride(from: 0, to: tiles.count, by: 2).map {
            Array(tiles[$0..<min($0 + 2, tiles.count)])
        }
        return VStack(alignment: .leading, spacing: TargetTileMetrics.spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: TargetTileMetrics.spacing) {
                    ForEach(rows[index]) { provider in
                        BuiltInProviderTile(
                            provider: provider,
                            precise: installed(provider.id)
                                && provider.descriptor.supportsPreciseDetection,
                            offersPrecise: offersPrecise(provider),
                            onToggle: { state.onToggleProvider(provider.id, $0) },
                            onFix: { state.onGrantAccess(provider.id) },
                            onEnablePrecise: { previewing = PreviewTarget(id: provider.id) },
                            onRemovePrecise: { removePrecise(provider.id) })
                    }
                    if rows[index].count == 1 {
                        // Holds the lone tile to column width instead of
                        // letting it sprawl across both.
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var errorNotes: some View {
        if let problem = precise.lastError {
            SettingNote(text: LocalizedStringKey(stringLiteral: problem), isProblem: true)
        }
        if let problem = precise.codexLastError {
            SettingNote(text: LocalizedStringKey(stringLiteral: problem), isProblem: true)
        }
        if let problem = precise.clineLastError {
            SettingNote(text: LocalizedStringKey(stringLiteral: problem), isProblem: true)
        }
    }

    /// The tile shows the Enable link exactly when clicking it could work:
    /// the build has a bridge, the agent is on and readable, and the hooks
    /// are not already in place.
    private func offersPrecise(_ provider: ProviderStatus) -> Bool {
        guard PreciseDetection.isSupported, provider.descriptor.supportsPreciseDetection,
            provider.isEnabled, !installed(provider.id)
        else { return false }
        if case .ready = provider.availability { return true }
        return false
    }

    private func removePrecise(_ id: ProviderID) {
        Task {
            switch id {
            case .codex: await precise.uninstallCodex()
            case .cline: precise.uninstallCline()
            default: precise.uninstall()
            }
            refreshToken += 1
        }
    }

    private func installed(_ id: ProviderID) -> Bool {
        switch id {
        case .claudeCode: return precise.isInstalled
        case .codex: return precise.isCodexInstalled
        case .cline: return precise.isClineInstalled
        default: return false
        }
    }

}
