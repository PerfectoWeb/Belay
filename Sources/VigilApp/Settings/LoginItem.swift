import Observation
import ServiceManagement
import SwiftUI
import VigilSupport

/// "Open at login", as state we own rather than a question we re-ask.
///
/// The checkbox used to bind straight to `SMAppService.mainApp.status`. Turning
/// it off did nothing visible: `unregister()` returns immediately but the status
/// is served by `backgroundtaskmanagementd` and still reads `.enabled` for a
/// moment afterwards, so the very next redraw put the tick back. The user is
/// left clicking a control that keeps undoing itself, with no error to explain
/// why.
///
/// So: the call is the source of truth for what *we* just did, and the service
/// is re-read only when something outside the app could have changed it — the
/// user can always revoke this in System Settings, and the checkbox has to
/// follow when they do.
@MainActor
@Observable
final class LoginItem {
    enum Problem: Equatable {
        /// macOS accepted the request but a human has to approve it.
        case needsApproval
        case refused(String)
    }

    private(set) var isEnabled: Bool
    private(set) var problem: Problem?

    private let service: any LoginItemService
    private let clock: () -> Date
    /// When this app last changed the setting. `backgroundtaskmanagementd` needs
    /// a moment to agree, and until it does its answer must not overwrite ours.
    private var changedAt: Date?
    /// How long the daemon is allowed to disagree before we believe it.
    static let settlingPeriod: TimeInterval = 5

    init(service: any LoginItemService = SystemLoginItem(), clock: @escaping () -> Date = Date.init) {
        self.service = service
        self.clock = clock
        isEnabled = service.isRegistered
        problem = service.needsApproval ? .needsApproval : nil
    }

    /// Re-reads the service, so the checkbox follows a change the user made in
    /// System Settings.
    ///
    /// This runs on `windowDidBecomeKey`, which fires far more often than
    /// "returned from System Settings" — reopening Settings, dismissing a sheet,
    /// closing the folder picker. Trusting it unconditionally would put the tick
    /// straight back on within seconds of switching it off, which is the bug
    /// this whole type exists to fix, reintroduced through the back door. So a
    /// disagreement inside the settling period is treated as the daemon lagging,
    /// not as news.
    func refresh() {
        let settling = changedAt.map { clock().timeIntervalSince($0) < Self.settlingPeriod } ?? false
        if !(settling && service.isRegistered != isEnabled) {
            isEnabled = service.isRegistered
            changedAt = nil
        }
        if service.needsApproval {
            problem = .needsApproval
        } else if problem == .needsApproval {
            problem = nil
        }
    }

    func set(_ wanted: Bool) {
        do {
            if wanted {
                try service.register()
            } else {
                try service.unregister()
            }
            isEnabled = wanted
            changedAt = clock()
            problem = service.needsApproval ? .needsApproval : nil
        } catch {
            Log.app.error("login item change failed: \(error.localizedDescription, privacy: .public)")
            // Show what macOS actually thinks, not what was asked for: a control
            // that lies about having worked is worse than one that refuses.
            isEnabled = service.isRegistered
            changedAt = nil
            problem = .refused(error.localizedDescription)
        }
    }

    var binding: Binding<Bool> {
        Binding(get: { self.isEnabled }, set: { self.set($0) })
    }

    /// macOS 13 moved login items into their own System Settings pane, and this
    /// is the only supported way in. There is no admin prompt and nothing to
    /// elevate — `SMAppService` is per-user — so "ask for the root password"
    /// never enters into it; when macOS says no, all an app can do is explain
    /// and open the right page.
    static func openSystemSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The half of `SMAppService` this app uses, so the behaviour above can be
/// tested without registering a real login item on whoever runs the suite.
protocol LoginItemService: Sendable {
    var isRegistered: Bool { get }
    var needsApproval: Bool { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginItem: LoginItemService {
    var isRegistered: Bool { SMAppService.mainApp.status == .enabled }
    var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
