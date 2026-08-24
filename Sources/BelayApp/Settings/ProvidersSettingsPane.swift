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
                        Belay reads these agents' own session files. Switch on the ones you use; \
                        a switched-off agent is never watched and never asked about.
                        """
                ) {
                    builtIn
                }
                if showsPreciseNote {
                    preciseRow
                        .transition(TargetTileMetrics.transition)
                }
            }
            // The same arrival and departure the tiles below use, so the row
            // appears the way everything else on this pane does — and the
            // window's own refit is already easing to the same clock.
            .animation(
                reduceMotion
                    ? nil
                    : (showsPreciseNote ? TargetTileMetrics.arrival : TargetTileMetrics.departure),
                value: showsPreciseNote)
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

    /// The agents whose hooks could actually be installed right now: precise
    /// is per-agent, and a control for an agent that is off or missing is a
    /// control about nothing.
    private var preciseAgents: [ProviderStatus] {
        guard PreciseDetection.isSupported else { return [] }
        return state.providers.filter { provider in
            guard provider.descriptor.supportsPreciseDetection, provider.isEnabled else {
                return false
            }
            if case .ready = provider.availability { return true }
            return false
        }
    }

    private var showsPreciseNote: Bool { !preciseAgents.isEmpty }

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
    /// all. The row is only there when it could do something, and it names
    /// each agent it could do it for.
    @ViewBuilder
    private var preciseRow: some View {
        SettingRow(
            title: "Precise detection",
            explanation: """
                Lets an agent tell Belay exactly when it starts and stops, \
                instead of Belay inferring it from files. This is also what makes \
                "an agent is waiting for you" reliable.
                """
        ) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(preciseAgents) { provider in
                    preciseLine(for: provider)
                }
            }
        }
        if let problem = precise.lastError {
            SettingNote(text: LocalizedStringKey(stringLiteral: problem), isProblem: true)
        }
        if let problem = precise.codexLastError {
            SettingNote(text: LocalizedStringKey(stringLiteral: problem), isProblem: true)
        }
    }

    private func preciseLine(for provider: ProviderStatus) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: provider.descriptor.displayName)
                .font(.callout)
                .frame(width: 110, alignment: .leading)
            if installed(provider.id) {
                Button("Remove") {
                    Task {
                        if provider.id == .codex {
                            await precise.uninstallCodex()
                        } else {
                            precise.uninstall()
                        }
                        refreshToken += 1
                    }
                }
                .accessibilityHint("Removes Belay's entries from this agent's settings")
            } else {
                Button("Enable…") { previewing = PreviewTarget(id: provider.id) }
                    .accessibilityHint("Shows exactly what will be added before anything is written")
            }
        }
    }

    private func installed(_ id: ProviderID) -> Bool {
        id == .codex ? precise.isCodexInstalled : precise.isInstalled
    }

}
