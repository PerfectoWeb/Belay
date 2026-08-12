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
    private typealias ChunkHandler =
        @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void

    public let signals: AsyncStream<ActivitySignal>

    private static let readChunk = 64 * 1024
    /// A client that connects and then says nothing does not get to sit there.
    private static let requestTimeout: TimeInterval = 10

    private let store: BridgeEndpointStore
    private let clock: any Clock
    private let continuation: AsyncStream<ActivitySignal>.Continuation
    private let queue = DispatchQueue(label: "com.perfecto-web.belay.bridge", qos: .utility)

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
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

    // MARK: - Requests

    private func accept(_ connection: NWConnection) {
        guard let token = endpoint?.token else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                Task { await self?.forget(id) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.requestTimeout * 1_000_000_000))
            await self?.expire(id)
        }
        receive(on: connection, id: id, token: token, buffer: Data())
    }

    /// The buffer travels through the closure chain rather than living in a
    /// property. That is what keeps request bytes — prompts, tool output — off
    /// this actor entirely.
    private func receive(
        on connection: NWConnection,
        id: ObjectIdentifier,
        token: String,
        buffer: Data
    ) {
        let onChunk: ChunkHandler = { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var next = buffer
            if let chunk, !chunk.isEmpty { next.append(chunk) }
            let finished = isComplete || error != nil
            Task {
                await self.consume(next, on: connection, id: id, token: token, finished: finished)
            }
        }
        connection.receive(
            minimumIncompleteLength: 1, maximumLength: Self.readChunk, completion: onChunk)
    }

    private func consume(
        _ buffer: Data,
        on connection: NWConnection,
        id: ObjectIdentifier,
        token: String,
        finished: Bool
    ) {
        guard connections[id] != nil else { return }
        guard buffer.count <= HookRequestParser.maximumBytes else {
            respond(.tooLarge, on: connection)
            return
        }
        switch HookRequestParser.parse(buffer) {
        case .incomplete:
            guard !finished else {
                respond(.badRequest, on: connection)
                return
            }
            receive(on: connection, id: id, token: token, buffer: buffer)
        case .malformed:
            respond(.badRequest, on: connection)
        case .request(let request):
            handle(request, token: token, on: connection)
        }
    }

    private func handle(_ request: HookRequest, token: String, on connection: NWConnection) {
        // Checked before anything looks at the body: an unauthenticated caller
        // never gets its payload parsed, never mind turned into a signal.
        guard request.authorization == "Bearer \(token)" else {
            respond(.unauthorized, on: connection)
            return
        }
        guard request.method == "POST", request.path.hasPrefix(HookConfiguration.path) else {
            respond(.notFound, on: connection)
            return
        }
        // A generic webhook says everything it has to say in the query, so it
        // is answered before the body is even looked at — the caller may be a
        // one-line curl with no payload at all.
        if let signal = GenericWebhook.signal(path: request.path, now: clock.now) {
            continuation.yield(signal)
            respond(.accepted, on: connection)
            return
        }
        let envelope = try? JSONDecoder().decode(HookEnvelope.self, from: request.body)
        if let signal = envelope?.signal(at: clock.now) { continuation.yield(signal) }
        // Accepted even when the body was unusable. A hook that reports failure
        // is a hook that can put an error in front of the user's agent, and
        // Belay does not get to do that (docs/00-INVARIANTS.md invariant 5).
        respond(.accepted, on: connection)
    }

    private func respond(_ response: HookResponse, on connection: NWConnection) {
        connection.send(
            content: Data(response.head.utf8),
            completion: .contentProcessed { _ in connection.cancel() })
    }

    private func forget(_ id: ObjectIdentifier) {
        connections.removeValue(forKey: id)
    }

    private func expire(_ id: ObjectIdentifier) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.cancel()
    }
}
