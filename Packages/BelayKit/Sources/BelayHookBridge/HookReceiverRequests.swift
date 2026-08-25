import BelayCore
import Foundation
import Network

/// The per-connection request lifecycle: accept, read, parse, answer. Beside
/// `HookReceiver` for the file-length rule. Every request gets an answer
/// immediately, whatever its state (docs/03).
extension HookReceiver {
    // MARK: - Requests

    func accept(_ connection: NWConnection) {
        guard let token = endpoint?.token else {
            connection.cancel()
            return
        }
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        let id = nextConnectionID
        nextConnectionID += 1
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
    func receive(
        on connection: NWConnection,
        id: UInt64,
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

    func consume(
        _ buffer: Data,
        on connection: NWConnection,
        id: UInt64,
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

    func handle(_ request: HookRequest, token: String, on connection: NWConnection) {
        // Checked before anything looks at the body: an unauthenticated caller
        // never gets its payload parsed. Constant-time, so a local process
        // cannot probe the token a byte at a time by timing the first mismatch.
        guard BearerToken.constantTimeEqual(request.authorization, "Bearer \(token)") else {
            respond(.unauthorized, on: connection)
            return
        }
        guard request.method == "POST", request.path.hasPrefix(HookConfiguration.path) else {
            respond(.notFound, on: connection)
            return
        }
        // A generic webhook says everything in the query, so it is answered
        // before the body is even looked at.
        if let signal = GenericWebhook.signal(path: request.path, now: clock.now) {
            continuation.yield(signal)
            respond(.accepted, on: connection)
            return
        }
        if let signal = Self.agentSignal(path: request.path, body: request.body, at: clock.now) {
            continuation.yield(signal)
        }
        // Accepted even when the body was unusable. A hook that reports failure
        // is a hook that can put an error in front of the user's agent, and
        // Belay does not get to do that (docs/00-INVARIANTS.md invariant 5).
        respond(.accepted, on: connection)
    }

    func respond(_ response: HookResponse, on connection: NWConnection) {
        connection.send(
            content: Data(response.head.utf8),
            completion: .contentProcessed { _ in connection.cancel() })
    }

    func forget(_ id: UInt64) {
        connections.removeValue(forKey: id)
    }

    func expire(_ id: UInt64) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.cancel()
    }
}
