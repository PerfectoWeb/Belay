import SwiftUI
import VigilCore

/// The drop-down panel. Reads `AppState` and renders it; it holds no state of
/// its own and never touches IOKit or a provider (docs/02).
struct PanelView: View {
    /// docs/05 said "~300 pt"; 330 is what the sentences actually need. Width
    /// alone cannot fix them — the longest state description is seventy
    /// characters and would wrap at any width a menu bar panel may honestly be —
    /// so the block also reserves two lines. See `PanelStatusLine`.
    static let width: CGFloat = 330
    /// Floor for the seeded size, in case the first layout pass reports nothing:
    /// an empty popover is the one outcome worse than a slightly wrong one.
    static let minimumHeight: CGFloat = 160

    let state: AppState
    /// Set by `PanelController` so an action that opens a window can close the
    /// popover first.
    var onDismiss: () -> Void = {}
    /// The content's natural height, reported so the controller can animate the
    /// popover to it. See `PanelController.grow(to:)`.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        // `AppState.sessions` maps the snapshot on every read, so it is taken
        // once per body rather than once per use.
        let sessions = state.sessions
        return VStack(alignment: .leading, spacing: 12) {
            PanelStatusLine(status: PanelStatus.derive(from: state.snapshot.state))

            PanelModePicker(state: state)

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
        // Measured at its natural height, then pinned to the top of whatever the
        // window currently is. The window is what animates; this never does, so
        // nothing above a disclosure can move when the disclosure opens.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelHeight.self, value: proxy.size.height)
            }
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(PanelHeight.self) { height in
            guard height > 0 else { return }
            onHeightChange(height)
        }
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

/// The panel's natural height, travelling from the content up to the controller.
struct PanelHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
