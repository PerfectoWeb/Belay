import Foundation

/// Fan-out for `AsyncStream` producers that may have more than one consumer.
///
/// Exists because docs/07 calls out held-forever continuations as the classic
/// leak in this codebase: every subscriber gets a token and `onTermination`
/// hands it straight back.
struct ContinuationRegistry<Element: Sendable> {
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    var isEmpty: Bool { continuations.isEmpty }

    mutating func insert(_ continuation: AsyncStream<Element>.Continuation) -> UUID {
        let token = UUID()
        continuations[token] = continuation
        return token
    }

    mutating func remove(_ token: UUID) {
        continuations.removeValue(forKey: token)
    }

    func yield(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    mutating func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }
}
