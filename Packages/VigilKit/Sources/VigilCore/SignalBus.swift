import Foundation
import VigilSupport

/// Fans every provider's signals into one stream for the coordinator.
///
/// Buffering is bounded and drops the oldest element: a provider that goes
/// haywire must not grow memory without limit, and a stale activity signal has
/// no value anyway — only the newest one per session matters.
public actor SignalBus {
    private var continuations: [UUID: AsyncStream<ActivitySignal>.Continuation] = [:]
    private var pumps: [UUID: Task<Void, Never>] = [:]

    public init() {}

    /// A new subscription. Each caller gets its own stream.
    public func subscribe() -> AsyncStream<ActivitySignal> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ActivitySignal>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        return stream
    }

    public func publish(_ signal: ActivitySignal) {
        for continuation in continuations.values {
            continuation.yield(signal)
        }
    }

    /// Drains a provider's stream into the bus until it ends or is cancelled.
    public func attach(_ source: AsyncStream<ActivitySignal>) {
        let id = UUID()
        pumps[id] = Task { [weak self] in
            for await signal in source {
                guard !Task.isCancelled else { break }
                await self?.publish(signal)
            }
            await self?.detach(id)
        }
    }

    public func shutdown() {
        for pump in pumps.values { pump.cancel() }
        pumps.removeAll()
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
    }

    private func unsubscribe(_ id: UUID) {
        continuations[id] = nil
    }

    private func detach(_ id: UUID) {
        pumps[id] = nil
    }

    deinit {
        for pump in pumps.values { pump.cancel() }
        for continuation in continuations.values { continuation.finish() }
    }
}
