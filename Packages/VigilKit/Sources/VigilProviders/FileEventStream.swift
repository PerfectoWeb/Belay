import CoreServices
import Foundation
import VigilSupport

/// FSEvents, wrapped so the C callback never reaches past this file.
///
/// Verified on the host: watching a directory with `kFSEventStreamCreateFlagFileEvents`
/// delivers per-file paths for creates and appends. (`docs/DISCOVERY.md` §6 left
/// this open because a throwaway probe crashed; the probe was the bug.)
///
/// Lifetime: the callback context is a separate sink object handed to FSEvents
/// with real retain/release callbacks, so a callback already in flight on the
/// dispatch queue cannot outlive its captured state while `stop()` runs.
final class FileEventStream {
    private var stream: FSEventStreamRef?
    private let queue: DispatchQueue

    var isRunning: Bool { stream != nil }

    /// `onChange` is called on `queue` with the changed paths and must be cheap:
    /// the real work belongs on the provider actor.
    ///
    /// - Throws: `ProviderError.watchFailed` if FSEvents will not watch the root.
    init(
        root: URL,
        latency: TimeInterval,
        queue: DispatchQueue,
        onChange: @escaping @Sendable ([String]) -> Void
    ) throws {
        self.queue = queue

        // FSEvents reports symlink-resolved paths, so watch the resolved root or
        // nothing under /tmp or a relocated home ever matches.
        let watched = root.resolvingSymlinksInPath().path
        let sink = FileEventSink(onChange)
        let info = Unmanaged.passRetained(sink)
        defer { info.release() }

        var context = FSEventStreamContext(
            version: 0,
            info: info.toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                return UnsafeRawPointer(Unmanaged<FileEventSink>.fromOpaque(pointer).retain().toOpaque())
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<FileEventSink>.fromOpaque(pointer).release()
            },
            copyDescription: nil)

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard
            let created = FSEventStreamCreate(
                kCFAllocatorDefault,
                Self.callback,
                &context,
                [watched] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags)
        else { throw ProviderError.watchFailed(path: watched) }

        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            throw ProviderError.watchFailed(path: watched)
        }
        stream = created
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    deinit {
        stop()
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
        guard let info, count > 0 else { return }
        let sink = Unmanaged<FileEventSink>.fromOpaque(info).takeUnretainedValue()
        let raw = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        var changed: [String] = []
        changed.reserveCapacity(count)
        for index in 0..<count {
            changed.append(String(cString: raw[index]))
        }
        sink.handle(changed)
    }
}

/// Immutable box for the callback closure. Handed to FSEvents as a raw pointer,
/// which is why it needs a stable identity rather than being captured directly.
private final class FileEventSink: Sendable {
    let handle: @Sendable ([String]) -> Void

    init(_ handle: @escaping @Sendable ([String]) -> Void) {
        self.handle = handle
    }
}
