import BelayCore
import SwiftUI

/// The drop-down panel. Reads `AppState` and renders it; it holds no state of
/// its own and never touches IOKit or a provider (docs/02).
struct PanelView: View {
    /// docs/05 said "~300 pt"; 330 is what the sentences actually need. Width
    /// alone cannot fix them — the longest state description is seventy
    /// characters and would wrap at any width a menu bar panel may honestly be —
    /// so the block also reserves two lines. See `PanelStatusLine`.
    static let width: CGFloat = 330
    let state: AppState
    /// Set by `PanelController` so an action that opens a window can close the
    /// popover first.
    var onDismiss: () -> Void = {}

    var body: some View {
        // `AppState.sessions` maps the snapshot on every read, so it is taken
        // once per body rather than once per use.
        let sessions = state.sessions
        return VStack(alignment: .leading, spacing: 12) {
            PanelStatusLine(
                status: PanelStatus.derive(from: state.snapshot.state, timer: state.snapshot.timer))

            PanelModePicker(state: state)

            PanelTimerRow(state: state)

            if let warning = state.warning {
                PanelNoticeRow(symbolName: "exclamationmark.triangle", message: warning)
            }

            ForEach(setupNeeded, id: \.id) { provider in
                PanelNoticeRow(
                    symbolName: provider.descriptor.symbolName,
                    message: provider.setupPrompt ?? provider.descriptor.summary,
                    actionTitle: "Fix",
                    action: { state.onGrantAccess(provider.id) }
                )
            }

            // Stated without a button. A provider that is merely waiting for the
            // tool to be used has nothing for the user to fix, and offering
            // "Fix" is what sent people round the grant loop.
            ForEach(waiting, id: \.id) { provider in
                PanelNoticeRow(
                    symbolName: provider.descriptor.symbolName,
                    message: provider.waitingNote ?? "")
            }

            Divider()

            PanelSessionList(sessions: sessions)

            Divider()

            PanelFooter(totalAwake: state.totalAwake) {
                onDismiss()
                state.onOpenSettings()
            }
        }
        .padding(14)
        .frame(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(Branding.appName) panel")
    }

    private var setupNeeded: [ProviderStatus] {
        state.providers.filter { $0.isEnabled && $0.setupPrompt != nil }
    }

    private var waiting: [ProviderStatus] {
        state.providers.filter { $0.isEnabled && $0.waitingNote != nil }
    }

}

extension ProviderStatus {
    /// Non-nil exactly when the provider is one tap away from working.
    var setupPrompt: String? {
        guard case .needsSetup(let prompt) = availability else { return nil }
        return prompt
    }

    /// Non-nil when the provider cannot run and there is nothing to press.
    var waitingNote: String? {
        guard case .unavailable(let why) = availability else { return nil }
        return why
    }
}
