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

    /// Binds an ephemeral loopback port and records it, with the bearer token,
    /// in `bridge.json`. Returns once the listener is actually accepting.
    @discardableResult
    public func start() async throws -> BridgeEndpoint {
        if let endpoint { return endpoint }
        // A second caller arriving while the first is still binding waits on the
        // same listener rather than opening a competing one.
        if listener == nil {
            let made = try LoopbackListener.make()
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
            abandonStart(BridgeError.listenerFailed(error.localizedDescription))
        default:
            break
        }
    }

    private func abandonStart(_ error: Error) {
        let waiters = starting
        starting.removeAll()
        for waiter in waiters { waiter.resume(throwing: error) }
    }
}
