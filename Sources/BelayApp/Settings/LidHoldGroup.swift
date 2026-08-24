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

    private var service: SMAppService {
        SMAppService.daemon(plistName: LidDaemon.plistName)
    }

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
            if on {
                try? service.register()
                Diagnostics.note("lid helper register status=\(service.status.rawValue)")
            } else {
                service.unregister { _ in }
                Diagnostics.note("lid helper unregistered")
            }
            status = service.status
        }
        .onAppear { status = service.status }
        // The approval happens in System Settings, which means leaving Belay
        // and coming back — and the row used to keep saying "Open Login
        // Items" until a tab switch re-made it. Becoming active again is
        // exactly the moment the answer may have changed, so ask again then.
        // A read of `SMAppService.status`, nothing heavier, and only when
        // this row is on screen.
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            status = service.status
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
}
#else
/// The App Store build has no helper to offer, so it has no rows to show.
struct LidHoldGroup: View {
    @Bindable var settings: SettingsStore

    var body: some View { EmptyView() }
}
#endif
