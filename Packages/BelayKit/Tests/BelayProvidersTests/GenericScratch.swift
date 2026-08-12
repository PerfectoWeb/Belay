// `@unchecked Sendable` justification: `SteppedClock` and `RosterBox` are
// written by test code and read from inside the provider actor, so both cross
// isolation domains. Every stored property is guarded by the file's own
// `NSLock`; there is no other state. Neither can be an actor because `Clock.now`
// and the roster closure are synchronous requirements.

import BelayCore
import Foundation

@testable import BelayProviders

/// A throwaway folder tree for generic-provider tests.
final class GenericScratch {
    let root: URL

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("belay-generic-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// A folder inside the scratch tree, created on demand.
    func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func write(_ text: String, to name: String, in folder: URL) -> URL {
        let url = folder.appendingPathComponent(name)
        try? Data(text.utf8).write(to: url)
        return url
    }
}

/// Time the test moves by hand, so a 45 s quiet period costs no wall clock.
final class SteppedClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ interval: TimeInterval) {
        lock.lock()
        current += interval
        lock.unlock()
    }

    func sleep(until deadline: Date) async throws {
        try Task.checkCancellation()
    }
}

/// A process table the test controls: names can be added and taken away.
final class RosterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var names: Set<String>

    init(_ names: Set<String> = []) {
        self.names = names
    }

    var scan: @Sendable () -> Set<String>? {
        { [self] in
            lock.lock()
            defer { lock.unlock() }
            return names
        }
    }

    func set(_ updated: Set<String>) {
        lock.lock()
        names = updated
        lock.unlock()
    }
}
