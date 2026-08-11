import Foundation
import VigilSupport

/// Owns at most one live assertion per `PowerAssertionKind`, process-wide.
///
/// The controller is deliberately dumb about *why* the Mac should stay awake —
/// it takes `hold`/`release` from the coordinator and makes IOKit agree with
/// them. Everything it holds carries a short timeout that a refresh task
/// re-arms; see docs/04 for why the timeout is the safety design.
public actor PowerAssertionController {
    /// Seconds. Short enough that a wedged Vigil cannot pin the Mac awake for
    /// more than a couple of minutes, long enough that refreshing is free.
    public static let defaultTimeout: TimeInterval = 120

    private let backend: PowerAssertionBackend
    private let refreshFraction: Double

    private var live: [PowerAssertionKind: PowerAssertionID] = [:]
    private var isActive = false
    private var wantsDisplay = false
    private var reason = ""
    private var timeout = PowerAssertionController.defaultTimeout
    private var refreshTask: Task<Void, Never>?
    private var reconciliation: Task<Void, Never>?
    private var hasLoggedFailure = false

    /// The most recent IOKit failure, or `nil` once a call succeeds again.
    /// The UI shows this as a non-blocking warning; it never blocks a hold.
    public private(set) var lastError: PowerError?

    /// `refreshFraction` is the fraction of the timeout at which a live
    /// assertion is re-armed; it is clamped to a sane band.
    public init(
        backend: PowerAssertionBackend = IOKitPowerAssertionBackend(),
        refreshFraction: Double = 0.75
    ) {
        self.backend = backend
        self.refreshFraction = min(max(refreshFraction, 0.1), 0.95)
    }

    public var isHeld: Bool { live[.system] != nil }
    public var isDisplayHeld: Bool { live[.display] != nil }

    /// The reason string currently advertised to macOS, or `nil` when released.
    public var heldReason: String? { isActive ? reason : nil }

    /// Holds the Mac awake. Idempotent: calling it again while held updates the
    /// reason and re-arms the timeout instead of taking a second assertion.
    public func hold(
        reason: String,
        includeDisplay: Bool = false,
        timeout: TimeInterval = PowerAssertionController.defaultTimeout
    ) async {
        self.reason = reason
        self.wantsDisplay = includeDisplay
        self.timeout = max(timeout, 0.01)
        isActive = true
        // Started before the reconcile, not after: reconciling suspends, and a
        // release landing in that gap stops a refresh loop that the resuming
        // `hold` would then start again with nothing held. Intent and its timer
        // move together, synchronously, or they can be reordered by a suspension.
        startRefreshing()
        await reconcile()
    }

    /// Drops every assertion. A no-op, silent and error-free, when nothing is held.
    public func release() async {
        guard isActive || !live.isEmpty else { return }
        isActive = false
        wantsDisplay = false
        stopRefreshing()
        await reconcile()
    }

    /// Re-arms now instead of waiting for the next tick. Also retries anything
    /// that failed earlier, which is how the controller recovers from a
    /// transient IOKit refusal.
    func refreshNow() async {
        await reconcile()
    }

    /// Reconciles, but never concurrently with another reconcile.
    ///
    /// Every branch below suspends inside the backend, and `backend` is not this
    /// actor, so the await hands the controller to whoever is waiting. Two
    /// reconciles overlapping there lose assertions in both directions: a `hold`
    /// parked in `create` while a `release` reads an empty table, no-ops, and
    /// stops refreshing — the resumed `hold` then records an ID nobody will ever
    /// release, and it expires silently while the coordinator still believes it
    /// is holding; or a `hold` arriving while a `release` is parked, which finds
    /// nothing recorded and takes a second assertion next to the live one.
    /// Invariants 1 and 4 both, from a sleep notification, a SIGTERM or a quit.
    ///
    /// Chaining is enough, and is why there is no generation counter: the intent
    /// (`isActive`, `reason`, `timeout`) is always written synchronously before
    /// the call, so whichever reconcile runs last reconciles against the latest.
    private func reconcile() async {
        let previous = reconciliation
        let task = Task { [weak self] in
            await previous?.value
            await self?.reconcileNow()
        }
        reconciliation = task
        await task.value
    }

    /// Makes IOKit match the requested state, one kind at a time, so a failure
    /// on the display assertion cannot take the system assertion down with it.
    private func reconcileNow() async {
        var failure: PowerError?
        for kind in PowerAssertionKind.allCases {
            do {
                try await reconcile(kind)
            } catch {
                failure = error
            }
        }
        record(failure)
    }

    private func reconcile(_ kind: PowerAssertionKind) async throws(PowerError) {
        let wanted = isActive && (kind == .system || wantsDisplay)
        switch (wanted, live[kind]) {
        case (true, nil):
            let id = try await backend.create(kind: kind, reason: reason, timeout: timeout)
            live[kind] = id
            Log.signposter.emitEvent("power.assertion.create")
            Log.power.info("Holding \(kind.rawValue, privacy: .public) assertion")
        case (true, let id?):
            try await backend.rearm(id, reason: reason, timeout: timeout)
        case (false, let id?):
            // Forget the handle first: if the release throws, the assertion's
            // own timeout reaps it, and we must not retry a stale ID forever.
            live[kind] = nil
            try await backend.release(id)
            Log.signposter.emitEvent("power.assertion.release")
            Log.power.info("Released \(kind.rawValue, privacy: .public) assertion")
        case (false, nil):
            break
        }
    }

    private func record(_ failure: PowerError?) {
        lastError = failure
        guard let failure else {
            hasLoggedFailure = false
            return
        }
        // One line per outage, not one per refresh tick.
        guard !hasLoggedFailure else { return }
        hasLoggedFailure = true
        Log.power.error("Power assertion call failed: \(failure.localizedDescription, privacy: .public)")
    }

    private var refreshInterval: TimeInterval { timeout * refreshFraction }

    private func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            // Weak throughout: the loop must never be the reason the controller
            // outlives the app, and it must not hold it across the sleep.
            while !Task.isCancelled {
                guard let interval = await self?.refreshInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.refreshNow()
            }
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
