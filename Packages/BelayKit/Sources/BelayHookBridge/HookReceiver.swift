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
    /// Fires when the listener comes back up on its own after a runtime
    /// failure, so the app layer can repoint hooks if the port moved. Nothing
    /// is emitted for the launch-time bind; `start()` returns that endpoint.
    public let rebinds: AsyncStream<BridgeEndpoint>

    static let readChunk = 64 * 1024
    /// A client that connects and then says nothing does not get to sit there.
    static let requestTimeout: TimeInterval = 10
    /// A ceiling on live connections, so a runaway or hostile local process
    /// cannot open thousands each buffering up to the 4 MB request cap.
    static let maxConnections = 32

    let store: BridgeEndpointStore
    let clock: any Clock
    let continuation: AsyncStream<ActivitySignal>.Continuation
    let rebindContinuation: AsyncStream<BridgeEndpoint>.Continuation
    let queue = DispatchQueue(label: "com.perfectoweb.belay.bridge", qos: .utility)

    var listener: NWListener?
    /// True between `start()` and `stop()`. A retry that fires after `stop()`
    /// must not bring a listener back from the dead.
    var running = false
    /// Keyed by a monotonic id, not `ObjectIdentifier(connection)`: a reused
    /// address could let one connection's expiry cancel another. A counter never
    /// reuses.
    var connections: [UInt64: NWConnection] = [:]
    /// The request-timeout task per connection, cancelled the moment the
    /// request finishes instead of sleeping out its ten seconds.
    var expiries: [UInt64: Task<Void, Never>] = [:]
    var nextConnectionID: UInt64 = 0
    var starting: [CheckedContinuation<BridgeEndpoint, Error>] = []
    /// The port from `bridge.json`, and how many times this start has asked
    /// for a port at all.
    var remembered: UInt16?
    var attempts = 0

    // Setter internal, not private: the port half next door owns it.
    public internal(set) var endpoint: BridgeEndpoint?

    public init(store: BridgeEndpointStore = BridgeEndpointStore(), clock: any Clock = SystemClock()) {
        self.store = store
        self.clock = clock
        let made = AsyncStream.makeStream(of: ActivitySignal.self, bufferingPolicy: .bufferingNewest(256))
        signals = made.stream
        continuation = made.continuation
        let rebound = AsyncStream.makeStream(of: BridgeEndpoint.self, bufferingPolicy: .bufferingNewest(1))
        rebinds = rebound.stream
        rebindContinuation = rebound.continuation
    }

    deinit {
        // Network.framework retains a started listener and its connections
        // until they are cancelled; a receiver dropped without `stop()` must
        // not leave a bound socket behind for the life of the process.
        listener?.cancel()
        for connection in connections.values { connection.cancel() }
        for expiry in expiries.values { expiry.cancel() }
        continuation.finish()
        rebindContinuation.finish()
    }

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
        running = true
        // A second caller arriving while the first is still binding waits on the
        // same listener rather than opening a competing one.
        if listener == nil {
            if attempts == 0 { remembered = store.load()?.port }
            let made = try LoopbackListener.make(port: candidate())
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
        running = false
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        for expiry in expiries.values { expiry.cancel() }
        expiries.removeAll()
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

}
