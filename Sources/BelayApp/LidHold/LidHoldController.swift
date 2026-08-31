#if !BELAY_MAS
import BelayPower
import BelaySettings
import BelaySupport
import Foundation
import ServiceManagement

/// The app's half of "hold through a closed lid": registers the helper,
/// heartbeats it while the rules say the flag should be up, and stands it
/// down the moment they say otherwise. The rules themselves — the cap, the
/// thermal release, the no-re-arm trap — live in `LidHold`, where tests run.
@MainActor
final class LidHoldController {
    /// Also the heartbeat cadence. Each beat asks for three leashes of slack,
    /// so one missed tick changes nothing and a dead app costs under a minute.
    private static let tickInterval: TimeInterval = 15
    private static let leash: TimeInterval = 45

    private let settings: SettingsStore
    private let state: AppState
    private let notifier: Notifier
    private var machine = LidHold()
    private var ticker: Timer?
    private var connection: NSXPCConnection?
    /// Consecutive XPC failures, for the log's sake only. The heartbeat must
    /// keep retrying — it is what the helper's own leash is counting on — but
    /// 828 identical lines in four days said nothing 21 would not.
    private var xpcFailures = 0

    /// What the settings row shows. Published through `AppState.onChange`-free
    /// observation: the row reads it directly each render.
    private(set) var serviceStatus: SMAppService.Status = .notRegistered

    init(settings: SettingsStore, state: AppState, notifier: Notifier) {
        self.settings = settings
        self.state = state
        self.notifier = notifier
    }

    func start() {
        // The status lives in `backgroundtaskmanagementd`, and asking for it
        // is an XPC round trip clocked at one to three seconds on a cold
        // daemon (see `LoginItem`). `start()` runs inside
        // applicationDidFinishLaunching, so the read — and any register — go
        // off the main thread and the first answer lands a beat later.
        Task { await self.registerAtStartIfNeeded() }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Reads the helper's status off the main thread and, if the opt-in stands
    /// while the helper is unregistered, registers it. The flip in the settings
    /// row is not the only way the setting arrives: restored preferences, a
    /// rebuilt app, a helper unregistered behind our back — the opt-in standing
    /// while nothing is registered is a promise nobody is keeping.
    private func registerAtStartIfNeeded() async {
        var status = await Self.readStatus()
        if settings.lidHold, status == .notRegistered {
            await Task.detached(priority: .userInitiated) {
                try? SMAppService.daemon(plistName: LidDaemon.plistName).register()
            }.value
            status = await Self.readStatus()
            Diagnostics.note("lid helper register-at-start status=\(status.rawValue)")
        }
        serviceStatus = status
    }

    /// The XPC status read, hopped off the main thread. `SMAppService.Status`
    /// is a plain enum, so it crosses back cleanly.
    private static func readStatus() async -> SMAppService.Status {
        await Task.detached(priority: .userInitiated) {
            SMAppService.daemon(plistName: LidDaemon.plistName).status
        }.value
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        if machine.isEngaged { standDown(cause: "shutdown") }
    }

    private func tick() {
        guard settings.lidHold || machine.isEngaged else { return }
        // Refresh the cached status off the main thread for the next beat;
        // this beat uses the last known value. One stale tick changes nothing
        // — each heartbeat asks for three leashes of slack — and it keeps the
        // 15 s cadence from ever hitching the main thread on a slow daemon.
        Task { await self.refreshStatus() }

        let thermal = ProcessInfo.processInfo.thermalState
        let sample = LidHold.Sample(
            enabled: settings.lidHold && serviceStatus == .enabled,
            holding: state.isHolding,
            lidClosed: Clamshell.isClosed() ?? false,
            thermalSerious: thermal == .serious || thermal == .critical,
            now: Date(),
            monotonic: ProcessInfo.processInfo.systemUptime)

        switch machine.evaluate(sample) {
        case .engage:
            Diagnostics.note(
                "lid engage cap=\(Int(machine.cap)) lidClosed=\(sample.lidClosed ? 1 : 0)")
            heartbeat()
        case .release(let reason):
            standDown(cause: "\(reason)")
            // The guards say so out loud, the way the battery guard does: a
            // Mac that slept with the lid shut and no explanation reads as
            // Belay failing, not as Belay protecting the machine.
            switch reason {
            case .thermal:
                Task { [notifier] in await notifier.lidReleased(dueToHeat: true) }
            case .capReached:
                Task { [notifier] in await notifier.lidReleased(dueToHeat: false) }
            case .done:
                break
            }
        case nil:
            if machine.isEngaged { heartbeat() }
        }
    }

    private func refreshStatus() async {
        let status = await Self.readStatus()
        guard status != serviceStatus else { return }
        Diagnostics.note("lid helper status=\(serviceStatus.rawValue)->\(status.rawValue)")
        serviceStatus = status
    }

    private func heartbeat() {
        proxy()?.keepSleepDisabled(until: Date().addingTimeInterval(Self.leash)) { [weak self] up in
            Task { @MainActor in self?.xpcFailures = 0 }
            if !up { Diagnostics.appendFromAnywhere("lid heartbeat refused up=0") }
        }
    }

    /// First failure loudly, then one line in forty (about ten minutes at the
    /// sweep's pace): the fact is preserved, the flood is not.
    private func noteXPCFailure(_ description: String) {
        xpcFailures += 1
        guard xpcFailures == 1 || xpcFailures.isMultiple(of: 40) else { return }
        Diagnostics.appendFromAnywhere(
            "lid xpc error=\"\(description)\" (\(xpcFailures) in a row)")
    }

    private func standDown(cause: String) {
        Diagnostics.note("lid release cause=\(cause)")
        proxy()?.standDown { down in
            if !down { Diagnostics.appendFromAnywhere("lid standDown failed down=0") }
        }
    }

    private func proxy() -> LidHelperProtocol? {
        if connection == nil {
            let fresh = NSXPCConnection(
                machServiceName: LidDaemon.machService, options: .privileged)
            fresh.remoteObjectInterface = NSXPCInterface(with: LidHelperProtocol.self)
            fresh.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            fresh.resume()
            connection = fresh
        }
        // `@Sendable`, deliberately: the handler runs on the connection's own
        // queue, and a closure born in a main-actor method otherwise inherits
        // that isolation and traps the moment XPC calls it off-main.
        return connection?.remoteObjectProxyWithErrorHandler { @Sendable [weak self] error in
            let description = error.localizedDescription
            Task { @MainActor in self?.noteXPCFailure(description) }
        } as? LidHelperProtocol
    }
}
#endif
