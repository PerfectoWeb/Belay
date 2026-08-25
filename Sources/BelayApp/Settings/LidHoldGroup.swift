import AppKit
import BelaySettings
import SwiftUI

#if !BELAY_MAS
import ServiceManagement

/// The lid-hold rows: the opt-in, and whatever standing between the user and
/// a working helper needs saying. Direct builds only — a sandboxed app cannot
/// install a privileged helper (guideline 2.4.5), so the App Store build
/// compiles this file to the empty view below.
struct LidHoldGroup: View {
    @Bindable var settings: SettingsStore
    @State private var status: SMAppService.Status = .notRegistered

    var body: some View {
        GroupedCheckbox(
            title: "Closed-lid hold",
            explanation: """
                Keeps your Mac awake with the lid closed. Ends at the awake \
                limit or if your Mac gets too warm.
                """,
            isOn: $settings.lidHold
        )
        .onChange(of: settings.lidHold) { _, on in
            // Registering here, on the flip, is what makes macOS show its
            // approval prompt while the user is still looking at the switch.
            // Off the main thread: register/unregister and the status read are
            // XPC round trips to backgroundtaskmanagementd, clocked at one to
            // three seconds on a cold daemon (see `LoginItem`), and this closure
            // runs on the main actor mid-switch-animation.
            Task {
                let newStatus = await Task.detached(priority: .userInitiated) {
                    () -> SMAppService.Status in
                    let service = SMAppService.daemon(plistName: LidDaemon.plistName)
                    if on { try? service.register() } else { service.unregister { _ in } }
                    return service.status
                }.value
                Diagnostics.note(
                    "lid helper \(on ? "register" : "unregistered") status=\(newStatus.rawValue)")
                status = newStatus
            }
        }
        .onAppear { refreshStatus() }
        // The approval happens in System Settings, which means leaving Belay
        // and coming back — and the row used to keep saying "Open Login
        // Items" until a tab switch re-made it. Becoming active again is
        // exactly the moment the answer may have changed, so ask again then —
        // off the main thread, only when this row is on screen.
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refreshStatus()
        }

        if settings.lidHold, status == .requiresApproval {
            HStack(spacing: 8) {
                Button("Open Login Items") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .controlSize(.small)
                Text("Approve the helper in Login Items so it can hold the lid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if settings.lidHold, status == .notFound {
            Text("macOS cannot find the helper in this build.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    /// Reads the helper status off the main thread and publishes it. See the
    /// XPC-latency note on `onChange` above.
    private func refreshStatus() {
        Task {
            status = await Task.detached(priority: .userInitiated) {
                SMAppService.daemon(plistName: LidDaemon.plistName).status
            }.value
        }
    }
}
#else
/// The App Store build has no helper to offer, so it has no rows to show.
struct LidHoldGroup: View {
    @Bindable var settings: SettingsStore

    var body: some View { EmptyView() }
}
#endif
