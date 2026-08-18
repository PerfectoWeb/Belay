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
    private var machine = LidHold()
    private var ticker: Timer?
    private var connection: NSXPCConnection?

    /// What the settings row shows. Published through `AppState.onChange`-free
    /// observation: the row reads it directly each render.
    private(set) var serviceStatus: SMAppService.Status = .notRegistered

    init(settings: SettingsStore, state: AppState) {
        self.settings = settings
        self.state = state
    }

    private var service: SMAppService {
        SMAppService.daemon(plistName: LidDaemon.plistName)
    }

    func start() {
        serviceStatus = service.status
        // The settings row registers on the flip, but a flip is not the only
        // way the setting arrives: restored preferences, a rebuilt app, a
        // helper unregistered behind our back. The opt-in standing while the
        // helper is not registered is a promise nobody is keeping, so keep it.
        if settings.lidHold, serviceStatus == .notRegistered {
            try? service.register()
            serviceStatus = service.status
            Diagnostics.note("lid helper register-at-start status=\(serviceStatus.rawValue)")
        }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        if machine.isEngaged { standDown(cause: "shutdown") }
    }

    private func tick() {
        guard settings.lidHold || machine.isEngaged else { return }
        let previous = serviceStatus
        serviceStatus = service.status
        if serviceStatus != previous {
            Diagnostics.note(
                "lid helper status=\(previous.rawValue)->\(serviceStatus.rawValue)")
        }

        let thermal = ProcessInfo.processInfo.thermalState
        let sample = LidHold.Sample(
            enabled: settings.lidHold && serviceStatus == .enabled,
            holding: state.isHolding,
            lidClosed: Clamshell.isClosed() ?? false,
            thermalSerious: thermal == .serious || thermal == .critical,
            now: Date())

        switch machine.evaluate(sample) {
        case .engage:
            Diagnostics.note(
                "lid engage cap=\(Int(machine.cap)) lidClosed=\(sample.lidClosed ? 1 : 0)")
            heartbeat()
        case .release(let reason):
            standDown(cause: "\(reason)")
        case nil:
            if machine.isEngaged { heartbeat() }
        }
    }

    private func heartbeat() {
        proxy()?.keepSleepDisabled(until: Date().addingTimeInterval(Self.leash)) { up in
            if !up { Diagnostics.appendFromAnywhere("lid heartbeat refused up=0") }
        }
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
        return connection?.remoteObjectProxyWithErrorHandler { error in
            Diagnostics.appendFromAnywhere(
                "lid xpc error=\"\(error.localizedDescription)\"")
        } as? LidHelperProtocol
    }
}
#endif
