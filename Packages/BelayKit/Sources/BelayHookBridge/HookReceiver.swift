import BelayCore
import BelaySupport
import Foundation
import Network

/// The loopback listener Claude Code's HTTP hooks post to.
///
/// This is Tier B: every signal it emits is `.exact`, because the agent itself
/// said what happened rather than a file watcher inferring it (docs/03).
///
/// Two properties are worth stating outright, because the rest of the file is
/// arranged to hold them up. Request bytes are never stored in a property —
/// buffers live in the receive closure chain and die with it — so a prompt or a
/// tool response cannot end up retained on this actor. And every request gets an
/// answer, immediately, whatever its state: hooks are registered `async`, but a
/// receiver that stalls a connection is still a receiver that is in the user's
/// agent's way.
public actor HookReceiver {
    // Internal, not private: the request-handling half lives in
    // `HookReceiverRequests.swift` for the file-length rule.
    typealias ChunkHandler =
        @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void

    public let signals: AsyncStream<ActivitySignal>

    static let readChunk = 64 * 1024
    /// A client that connects and then says nothing does not get to sit there.
    static let requestTimeout: TimeInterval = 10
    /// A ceiling on live connections, so a runaway or hostile local process
    /// cannot open thousands each buffering up to the 4 MB request cap.
    static let maxConnections = 32

    private let store: BridgeEndpointStore
    let clock: any Clock
    let continuation: AsyncStream<ActivitySignal>.Continuation
    let queue = DispatchQueue(label: "com.perfectoweb.belay.bridge", qos: .utility)

    private var listener: NWListener?
    /// Keyed by a monotonic id, not `ObjectIdentifier(connection)`: a reused
    /// address could let one connection's expiry cancel another. A counter never
    /// reuses.
    var connections: [UInt64: NWConnection] = [:]
    var nextConnectionID: UInt64 = 0
    private var starting: [CheckedContinuation<BridgeEndpoint, Error>] = []
    /// The port this start is asking for, and how many times it has asked.
    /// `nil` means it has given up on a particular one and will take any.
    private var wanted: UInt16?
    private var attempts = 0

    public private(set) var endpoint: BridgeEndpoint?

    public init(store: BridgeEndpointStore = BridgeEndpointStore(), clock: any Clock = SystemClock()) {
        self.store = store
        self.clock = clock
        let made = AsyncStream.makeStream(of: ActivitySignal.self, bufferingPolicy: .bufferingNewest(256))
        signals = made.stream
        continuation = made.continuation
    }

    deinit {
        continuation.finish()
    }

    /// How many times to ask for the remembered port before taking any free
    /// one. An outgoing instance releases its socket in well under a second;
    /// four tries a quarter-second apart covers that without making a launch
    /// wait on a port somebody else has taken for good.
    static let portAttempts = 4

    /// Binds the port from `bridge.json` if it can, records it with the bearer
    /// token, and returns once the listener is actually accepting.
    ///
    /// The remembered port matters more than it looks: the agent posts to
    /// whatever address its settings file names, so a new port on every launch
    /// means a window where every tool call fails, and during an update that
    /// window is guaranteed.
    @discardableResult
    public func start() async throws -> BridgeEndpoint {
        if let endpoint { return endpoint }
        // A second caller arriving while the first is still binding waits on the
        // same listener rather than opening a competing one.
        if listener == nil {
            if attempts == 0 { wanted = store.load()?.port }
            let made = try LoopbackListener.make(port: wanted)
            listener = made
            made.stateUpdateHandler = { [weak self] state in
                Task { await self?.listenerChanged(state) }
            }
            made.newConnectionHandler = { [weak self] connection in
                Task { await self?.accept(connection) }
            }
            made.start(queue: queue)
        }
        // Nothing awaits between starting the listener and registering here, so
        // a `.ready` callback cannot arrive before there is someone to wake.
        return try await withCheckedThrowingContinuation { waiter in
            starting.append(waiter)
        }
    }

    /// Returns once the socket is actually gone, not once cancellation has been
    /// asked for. Restarting a receiver, or a test asserting the port came back,
    /// would otherwise be racing an asynchronous close.
    public func stop() async {
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        endpoint = nil
        abandonStart(BridgeError.listenerFailed("the receiver was stopped"))

        guard let listener else { return }
        self.listener = nil
        listener.newConnectionHandler = nil
        await withCheckedContinuation { resumption in
            // `cancel` delivers `.cancelled` exactly once, and this handler
            // replaces the one that would otherwise route it back into `start`.
            listener.stateUpdateHandler = { state in
                guard case .cancelled = state else { return }
                resumption.resume()
            }
            listener.cancel()
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
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
                // The one subsystem whose failure a person sees in their own
                // terminal, and the log said nothing about it until 28 Aug.
                EventLog.note("bridge up port=\(port)")
                let waiters = starting
                starting.removeAll()
                for waiter in waiters { waiter.resume(returning: resolved) }
            } catch {
                abandonStart(error)
            }
        case .failed(let error):
            // Dropped, not kept: a failed listener must not be what a retry
            // finds and reuses.
            listener?.cancel()
            listener = nil
            // The remembered port is usually taken by the instance this one is
            // replacing, which lets go in a moment. Ask again, then settle for
            // any free port rather than leaving the bridge down.
            if wanted != nil, attempts < Self.portAttempts {
                attempts += 1
                if attempts == Self.portAttempts { wanted = nil }
                EventLog.note("bridge port busy, retrying (\(attempts))")
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    await self?.retryStart()
                }
                return
            }
            EventLog.note("bridge failed: \(error.localizedDescription)")
            abandonStart(BridgeError.listenerFailed(error.localizedDescription))
        default:
            break
        }
    }

    /// Another go at the remembered port, from the retry timer.
    private func retryStart() async {
        guard listener == nil, !starting.isEmpty else { return }
        do {
            let made = try LoopbackListener.make(port: wanted)
            listener = made
            made.stateUpdateHandler = { [weak self] state in
                Task { await self?.listenerChanged(state) }
            }
            made.newConnectionHandler = { [weak self] connection in
                Task { await self?.accept(connection) }
            }
            made.start(queue: queue)
        } catch {
            abandonStart(error)
        }
    }

    private func abandonStart(_ error: Error) {
        let waiters = starting
        starting.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
    }
}
