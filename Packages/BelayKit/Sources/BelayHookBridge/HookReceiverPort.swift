import BelayCore
import BelaySupport
import Foundation
import Network

/// The port half of the receiver: which port to ask for, and what to do when
/// the listener reports in. Beside `HookReceiver` for the file-length rule,
/// like `HookReceiverRequests`.
extension HookReceiver {
    // MARK: - The port, and keeping it

    /// How many times to ask for the remembered port before looking elsewhere.
    /// An outgoing instance releases its socket in well under a second; four
    /// tries a quarter-second apart covers that without making a launch wait on
    /// a port somebody else has taken for good.
    static let portAttempts = 4

    /// Where a first-run port comes from.
    ///
    /// Not the ephemeral range. That is the range macOS hands out to outgoing
    /// connections, so a port recorded there is one any browser or build tool
    /// can take while Belay is closed — which is the whole problem this record
    /// exists to avoid. This band sits below it, above the well-known services,
    /// and clear of the ports development tools reach for: nothing common lives
    /// between 41000 and 43000.
    static let quietRange: ClosedRange<UInt16> = 41_000...42_999

    /// The port to try on this attempt.
    ///
    /// The recorded one first, several times, because the instance being
    /// replaced is usually still holding it. Then fresh candidates from the
    /// quiet band. Then `nil`, meaning any free port at all: a bridge on an
    /// awkward port beats no bridge.
    func candidate() -> UInt16? {
        if attempts < Self.portAttempts, let remembered { return remembered }
        if attempts < Self.portAttempts + 4 { return UInt16.random(in: Self.quietRange) }
        return nil
    }

    func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else {
                abandonStart(BridgeError.listenerFailed("the listener reported no port"))
                return
            }
            do {
                let resolved = try store.endpoint(port: port)
                endpoint = resolved
                attempts = 0
                // A later runtime failure retries this port, not the one from
                // launch: it is the one the installed hooks now point at.
                remembered = port
                // The one subsystem whose failure a person sees in their own
                // terminal, and the log said nothing about it until 28 Aug.
                EventLog.note("bridge up port=\(port)")
                if starting.isEmpty {
                    // Nobody was waiting, so this bind is a self-heal; the app
                    // layer hears about it and repoints hooks if the port moved.
                    rebindContinuation.yield(resolved)
                } else {
                    let waiters = starting
                    starting.removeAll()
                    for waiter in waiters { waiter.resume(returning: resolved) }
                }
            } catch {
                dropListener()
                abandonStart(error)
            }
        case .failed(let error):
            // Dropped, not kept: a failed listener must not be what a retry
            // finds and reuses. And the endpoint goes with it: a receiver
            // whose socket died must never claim to be up, or a caller gets
            // the stale address back from `start()`.
            dropListener()
            endpoint = nil
            // The remembered port is usually taken by the instance this one is
            // replacing, which lets go in a moment. Ask again, then settle for
            // any free port rather than leaving the bridge down.
            if attempts < Self.portAttempts + 4 {
                attempts += 1
                EventLog.note("bridge port busy, retrying (\(attempts))")
                retryLater(after: 250_000_000)
                return
            }
            EventLog.note("bridge failed: \(error.localizedDescription)")
            if starting.isEmpty {
                // A runtime failure with nobody waiting — the wake-from-sleep
                // case. Giving up here would leave the bridge silently dead
                // for the rest of the app's life, so it keeps trying, slowly.
                attempts = 0
                retryLater(after: 30_000_000_000)
            } else {
                abandonStart(BridgeError.listenerFailed(error.localizedDescription))
            }
        default:
            break
        }
    }

    func retryLater(after nanoseconds: UInt64) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            await self?.retryStart()
        }
    }

    /// Another go at the remembered port, from the retry timer. Guarded by
    /// `running`, not by waiters: a listener that dies after `.ready` has no
    /// waiters left, and that is exactly when a retry matters most.
    func retryStart() async {
        guard listener == nil, running else { return }
        do {
            let made = try LoopbackListener.make(port: candidate())
            listener = made
            made.stateUpdateHandler = { [weak self] state in
                Task { await self?.listenerChanged(state) }
            }
            made.newConnectionHandler = { [weak self] connection in
                Task { await self?.accept(connection) }
            }
            made.start(queue: queue)
        } catch {
            dropListener()
            abandonStart(error)
        }
    }

    func dropListener() {
        listener?.cancel()
        listener = nil
    }

    func abandonStart(_ error: Error) {
        // A clean slate for whoever starts next: the ladder begins again at
        // the recorded port instead of resuming a spent count.
        attempts = 0
        let waiters = starting
        starting.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
    }
}
