import AppKit
import BelayCore
import BelayPower
import BelayProviders
import BelaySettings
import BelaySupport

/// Owns the object graph and the wiring between the layers.
///
/// Every arrow in the docs/02 data-flow diagram is a `Task` started here. The
/// layers themselves know nothing about each other: the coordinator has never
/// heard of IOKit, and the power controller has never heard of a session.
@MainActor
final class BelayController {
    let state: AppState
    // Internal, not private: the provider-toggling half of this controller
    // lives in `BelayControllerProviders.swift` for the file-length rule.
    let settings: SettingsStore
    // Internal, like the four below, so the power and sleep observers can live
    // in their own file (this one is at the linter's limit).
    let coordinator: ActivityCoordinator
    let driver: CoordinatorDriver
    let assertions: PowerAssertionController
    let powerSource: PowerSourceMonitor
    let providers: ProviderHost
    let sleepObserver = SystemSleepObserver()
    private let signals = TerminationSignalWatch()

    /// Long-lived stream pumps only. One-shot work uses a detached task that
    /// finishes on its own; keeping those here would grow without bound.
    var tasks: [Task<Void, Never>] = []
    private var refresh: Task<Void, Never>?
    var sleepObservers: [NSObjectProtocol] = []
    /// Registered on the distributed centre, so it cannot ride in the list above.
    var unlockObserver: NSObjectProtocol?
    private var awakeTally = AwakeTally()
    let usage = UsageRecorder()
    private var trigger = AnnouncementTrigger()
    let notifier: Notifier
    let nightDimming: NightDimmingController
    #if !BELAY_MAS
    private let lidHold: LidHoldController
    #endif

    init(
        settings: SettingsStore = SettingsStore(),
        state: AppState = AppState(),
        precise: PreciseDetection = PreciseDetection()
    ) {
        self.settings = settings
        self.state = state
        // The one composition point where the two channels differ: the direct
        // build reads folders outright, the sandboxed one reads them through
        // security-scoped bookmarks (docs/06, BLOCKERS B8). Two grants, because
        // `~/.claude` and a folder the user picked are not the same permission.
        // Which built-ins start switched on. Once, from what is installed:
        // a Mac without Codex must never be asked to grant ~/.codex, and the
        // first tester without it was. The sandboxed build cannot look, so
        // it keeps the stored default and the user switches Codex on by hand.
        Self.detectBuiltIns(settings: settings)
        providers = ProviderHost(
            precise: precise,
            enabled: settings.enabledProviders,
            access: ClaudeAccess.provider,
            codexAccess: CodexAccess.provider,
            clineAccess: ClineAccess.provider,
            folders: WatchedFolderAccess.provider,
            home: ClaudeAccess.home)
        coordinator = ActivityCoordinator(policy: settings.policy)
        driver = CoordinatorDriver(coordinator: coordinator)
        assertions = PowerAssertionController()
        powerSource = PowerSourceMonitor()
        notifier = Notifier(settings: settings)
        nightDimming = NightDimmingController(settings: settings, state: state)
        #if !BELAY_MAS
        lidHold = LidHoldController(settings: settings, state: state, notifier: notifier)
        #endif
        state.mode = settings.mode
    }

    func start() {
        state.onModeChange = { [weak self] mode in self?.setMode(mode) }
        state.onTimerChange = { [weak self] duration in self?.setAlwaysOnTimer(duration) }
        state.onHoldAgain = { [weak self] in self?.holdAgain() }
        state.onToggleProvider = { [weak self] provider, on in self?.setProviderEnabled(provider, on) }
        observeDecisions()
        observeHumanReturn()
        observePowerSource()
        observeSleepWake()
        startProviders()
        tasks.append(Task { [driver] in await driver.start() })
        tasks.append(Task { [powerSource] in await powerSource.start() })
        tasks.append(Task { [signals, assertions] in await signals.install(releasing: assertions) })
        nightDimming.start()
        #if !BELAY_MAS
        lidHold.start()
        #endif

        // Seed the power conditions and force one evaluation. Without this a
        // persisted Always-on mode does nothing until the driver's first idle
        // tick, up to a minute after launch.
        tasks.append(
            Task { [powerSource, coordinator, weak self] in
                let snapshot = await powerSource.poll()
                await coordinator.setPowerConditions(
                    PowerConditions(
                        isOnAC: snapshot.isOnAC,
                        charge: snapshot.charge,
                        isLowPowerMode: snapshot.isLowPowerMode
                    )
                )
                self?.nightDimming.isOnAC = snapshot.isOnAC
                self?.restoreAlwaysOnTimer()
                self?.refreshSnapshot()
            }
        )
        refreshSnapshot()
    }

    /// Releases synchronously on the way out. The assertion's own timeout is the
    /// real guarantee (docs/04); this just avoids the two-minute tail in the
    /// normal case. Bounded so a wedged actor cannot stall quit.
    func shutdown() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
        refresh?.cancel()
        nightDimming.stop()
        #if !BELAY_MAS
        lidHold.stop()
        #endif
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        sleepObservers.removeAll()
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
        unlockObserver = nil

        // Bank the hold that is still running, or a long overnight run vanishes
        // from the statistics the moment the user quits.
        usage.flush()
        // Closes the sandboxed build's scopes. None in the direct build.
        ClaudeAccess.relinquish()
        WatchedFolderAccess.relinquish()

        let done = DispatchSemaphore(value: 0)
        // Nothing here may touch the main actor: the wait below blocks the main
        // thread, so the first `await` that hops back deadlocks. `Task.detached`
        // was added for that and did not fix it, because the body began with
        // `providers.stop()` and `ProviderHost` is `@MainActor`, so every quit
        // logged a timeout and left the assertion to reap itself: up to two
        // minutes awake. It is out; it holds nothing that outlives us.
        Task.detached { [assertions, coordinator, driver, powerSource] in
            await driver.stop()
            await powerSource.stop()
            await assertions.release()
            await coordinator.shutdown()
            done.signal()
        }
        if done.wait(timeout: .now() + 1) == .timedOut {
            Log.app.error("shutdown release timed out; the assertion timeout will reap it")
        }
    }

    /// The direct build reads `~/.claude` outright, so there is nothing to ask
    /// for; the sandboxed build puts the open panel up here and keeps the
    /// bookmark. The retry is not optional: the Claude Code provider refused to
    /// start for want of access, and without it the grant only takes effect
    /// after a relaunch the user has no reason to guess at.
    var genericTargets: [GenericTarget] { providers.targets }

    func setMode(_ mode: AwakeMode) {
        settings.mode = mode
        state.mode = mode
        // The coordinator drops the timer when the mode leaves Always on;
        // the persisted copy goes with it, or a relaunch would resurrect a
        // bound the user had already walked away from.
        if mode != .alwaysOn { settings.alwaysOnTimer = nil }
        let policy = settings.policy
        Task { [coordinator, driver, weak self] in
            await coordinator.setPolicy(policy)
            await driver.nudge()
            // Without this the picker moved but nothing else did: the snapshot
            // still described the old mode, so the panel's sentence and both
            // marks kept saying "you asked Belay to stay on" under a selected
            // Auto. The driver publishes on its own schedule; a mode change is
            // the user waiting for an answer now.
            self?.refreshSnapshot()
        }
    }

    private func startProviders() {
        tasks.append(
            Task { [providers, coordinator, driver, weak self] in
                // Awaited, then published: a parallel task caught the generic
                // provider before its targets arrived, so the panel offered to
                // set up folders it was already watching.
                let signals = await providers.start()
                await self?.publishProviderStatus()
                for await signal in signals {
                    await coordinator.ingest(signal)
                    // The driver may be napping on a deadline computed before
                    // this signal existed; without this a release lands up to a
                    // minute late.
                    await driver.nudge()
                    self?.refreshSnapshot()
                }
            }
        )
        watchForClaudeCodeAppearing()
    }

    private func observeDecisions() {
        tasks.append(
            Task { [coordinator, assertions, settings, weak self] in
                for await decision in await coordinator.decisions() {
                    switch decision {
                    case .hold(let reason, let until):
                        let timeout = max(30, until.timeIntervalSinceNow)
                        Diagnostics.note(
                            "hold on reason=\"\(reason)\" "
                                + "display=\(settings.keepDisplayAwake ? 1 : 0)")
                        await assertions.hold(
                            reason: reason,
                            includeDisplay: settings.keepDisplayAwake, timeout: timeout)
                    case .release:
                        Diagnostics.note("hold off")
                        await assertions.release()
                    }
                    self?.refreshSnapshot()
                }
            }
        )
    }

    func refreshSnapshot() {
        refresh?.cancel()
        refresh = Task { [coordinator, assertions, weak self] in
            let snapshot = await coordinator.snapshot
            let error = await assertions.lastError
            guard !Task.isCancelled, let self else { return }
            self.usage.update(holdingSince: snapshot.holdingSince)
            let awake = self.awakeTally.update(holdingSince: snapshot.holdingSince)
            self.state.apply(snapshot, totalAwake: awake)
            self.state.apply(warning: error?.errorDescription)
            await self.notifier.handle(self.trigger.diff(snapshot))
        }
    }

}
