import BelaySupport
import Observation
import ServiceManagement
import SwiftUI

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

    /// One `setNow` result, carried back from the detached XPC call. A struct,
    /// not a tuple, so it stays inside the linter's tuple-size rule.
    private struct SetOutcome: Sendable {
        var registered: Bool
        var approval: Bool
        var error: String?
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
        // Not read here: the status lives in `backgroundtaskmanagementd`, and
        // asking it is an XPC round trip that has been clocked at one to
        // three seconds on a cold daemon. Construction happens on the main
        // thread while the Settings window is opening, so the first answer
        // arrives through `refresh()` a beat later instead.
        isEnabled = false
        problem = nil
        refresh()
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
    ///
    /// The reads happen off the main thread. They are XPC round trips to
    /// `backgroundtaskmanagementd`, and doing them synchronously froze the
    /// whole Settings window for one to three seconds every time it became
    /// key — the built-in agents' switches hung mid-animation as solid pills,
    /// which is how the stall was finally noticed.
    func refresh() {
        Task { await refreshNow() }
    }

    /// The same read, awaitable — for tests, which otherwise race the task.
    func refreshNow() async {
        let service = self.service
        let (registered, approval) = await Task.detached(priority: .userInitiated) {
            (service.isRegistered, service.needsApproval)
        }.value
        apply(registered: registered, approval: approval)
    }

    private func apply(registered: Bool, approval: Bool) {
        let settling = changedAt.map { clock().timeIntervalSince($0) < Self.settlingPeriod } ?? false
        if !(settling && registered != isEnabled) {
            isEnabled = registered
            changedAt = nil
        }
        if approval {
            problem = .needsApproval
        } else if problem == .needsApproval {
            problem = nil
        }
    }

    func set(_ wanted: Bool) {
        Task { await setNow(wanted) }
    }

    /// The same change, awaitable — for tests, which otherwise race the task.
    func setNow(_ wanted: Bool) async {
        // Optimistic: reflect the intent now so the checkbox does not lag the
        // click; `changedAt` opens the settling window so a racing `refresh()`
        // will not flip it back before the daemon agrees.
        isEnabled = wanted
        changedAt = clock()
        problem = nil
        // The register/unregister call and the follow-up status reads are XPC
        // round trips to backgroundtaskmanagementd, clocked at one to three
        // seconds on a cold daemon — off the main thread, or the whole Settings
        // window freezes mid-switch-animation (the bug the read path already
        // fixed; the write path had kept it).
        let service = self.service
        let result = await Task.detached(priority: .userInitiated) { () -> SetOutcome in
            do {
                if wanted { try service.register() } else { try service.unregister() }
                return SetOutcome(registered: service.isRegistered, approval: service.needsApproval)
            } catch {
                return SetOutcome(
                    registered: service.isRegistered, approval: service.needsApproval,
                    error: error.localizedDescription)
            }
        }.value
        if let error = result.error {
            Log.app.error("login item change failed: \(error, privacy: .public)")
            // Show what macOS actually thinks, not what was asked for: a control
            // that lies about having worked is worse than one that refuses.
            isEnabled = result.registered
            changedAt = nil
            problem = .refused(error)
        } else {
            problem = result.approval ? .needsApproval : nil
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
