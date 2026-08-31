import BelayCore
import Observation
import SwiftUI

/// The single object every view reads. Mirrors the coordinator outward; nothing
/// in the UI reaches back into an actor, and no view owns state of its own
/// beyond transient presentation flags (docs/02).
///
/// Frozen before the UI work began on purpose: the panel and the detection layer
/// are built against this shape in parallel, so changing it mid-flight is what
/// would produce a merge mess.
@MainActor
@Observable
final class AppState {
    /// Behavior setting mirrored in, so row building can honour the toggle
    /// without the panel views ever reaching for the settings store.
    var showToolBadges = true
    private(set) var snapshot: CoordinatorSnapshot = .idle
    /// Mirrors the settings store so the mode picker is instant; writes go back
    /// through `onModeChange`, never straight into the snapshot.
    var mode: AwakeMode = .auto
    private(set) var providers: [ProviderStatus] = []
    /// Non-fatal problem worth a single inline row, e.g. folder access lost or
    /// IOKit refusing the assertion. Never a modal.
    private(set) var warning: String?
    /// Total time this launch has held the Mac awake, for the panel footer.
    private(set) var totalAwake: TimeInterval = 0

    var onModeChange: (AwakeMode) -> Void = { _ in }
    /// The Always-on timer picked in the panel; nil means "until turned off".
    var onTimerChange: (TimeInterval?) -> Void = { _ in }
    /// The pause row's one-click exit.
    var onHoldAgain: () -> Void = {}
    /// SwiftUI views track this object automatically; the AppKit status item
    /// cannot, so it gets an explicit nudge.
    var onChange: () -> Void = {}
    var onGrantAccess: (ProviderID) -> Void = { _ in }
    /// A built-in agent's switch in Settings.
    var onToggleProvider: (ProviderID, Bool) -> Void = { _, _ in }
    /// The tile menu's folder management: add via the open panel, remove by
    /// path, or adopt a suggested sibling profile in one click.
    var onAddProviderRoot: (ProviderID) -> Void = { _ in }
    var onRemoveProviderRoot: (ProviderID, String) -> Void = { _, _ in }
    var onAddSuggestedRoot: (ProviderID, String) -> Void = { _, _ in }
    var onOpenSettings: () -> Void = {}

    var isHolding: Bool { snapshot.state.holdsAssertion }

    /// Sessions as a one-level tree: real sessions at the top, their subagents
    /// nested underneath.
    ///
    /// Flat, this list was unreadable — a workflow of fifty-four agents pushed
    /// the session that actually started it off the end of a five-row panel.
    var sessions: [SessionRow] {
        let rows = snapshot.sessions.map { session in
            let activity = snapshot.activities[session.id] ?? .idle
            // The elapsed column answers a different question per state.
            // Working and waiting measure from when that state began; idle
            // measures from the last signal — "quiet for four minutes" — and
            // never from `firstSeen`, which read as a 24-minute idle for a
            // session that had been working three minutes ago.
            let since: Date =
                switch activity {
                case .idle, .ended: session.lastSignal
                default: session.workingSince ?? session.awaitingSince ?? session.firstSeen
                }
            return SessionRow(
                id: session.id,
                provider: session.provider,
                workspace: session.workspace ?? String(localized: "Untitled project"),
                activity: activity,
                since: since,
                tool: showToolBadges && activity == .working ? session.activeTool : nil,
                parent: session.parent,
                kind: session.kind,
                name: session.name
            )
        }
        return SessionRow.disambiguate(SessionRow.nest(rows))
    }

    func apply(_ snapshot: CoordinatorSnapshot, totalAwake: TimeInterval) {
        self.snapshot = snapshot
        self.totalAwake = totalAwake
        onChange()
    }

    func apply(providers: [ProviderStatus]) {
        self.providers = providers
    }

    func apply(warning: String?) {
        self.warning = warning
    }

    /// Wires the two ways the panel reaches out of itself, without taking
    /// ownership of anything.
    ///
    /// Every capture here is weak on purpose. `AppState` holds these closures,
    /// and both the Settings window and the panel hold `AppState` — so a strong
    /// capture is a cycle, and `applicationWillTerminate` setting its references
    /// to nil deallocates nothing. `PanelController.deinit`, which is what
    /// finally drops the popover's SwiftUI view, then never runs at all.
    func connect(
        settings: SettingsWindow,
        panel: PanelController,
        grantAccess: @escaping (ProviderID) -> Void
    ) {
        onOpenSettings = { [weak settings] in settings?.show() }
        onGrantAccess = { [weak settings, weak panel] provider in
            grantAccess(provider)
            panel?.hide()
            settings?.show(pane: .providers)
        }
    }
}
