import BelaySupport
import Foundation
import OSLog

/// A file of what went wrong, kept on this Mac and sent nowhere.
///
/// Belay already logs through `os.Logger`, which is the right place for it: the
/// system rotates it, redacts it, and costs nothing when nobody is reading. What
/// it is not is something a person can attach to a bug report, because reading
/// it means knowing `log show` exists.
///
/// So this is a switch, off by default, that copies the app's own log lines into
/// a plain file, plus the two things `os.Logger` never sees: an uncaught
/// exception, and the main thread stopping.
///
/// Nothing is sent anywhere and there is nothing to send it with. The App Store
/// build has no network entitlement at all, and the direct build's only network
/// use is the update check.
@MainActor
enum Diagnostics {
    /// `~/Library/Logs/Belay`, or the container's equivalent in the sandboxed
    /// build. Console.app shows both without the user finding either.
    static var folder: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return library.appendingPathComponent("Logs/Belay", isDirectory: true)
    }

    static var file: URL { folder.appendingPathComponent("belay.log") }

    private static var watchdog: Timer?
    private static var beat = Date()

    /// Turns collection on or off. Safe to call with the value it already has.
    static func setEnabled(_ on: Bool) {
        if on { start() } else { stop() }
    }

    private static func start() {
        guard watchdog == nil else { return }
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        write("collection on, Belay \(Branding.version)")

        // A crash that kills the process cannot write anything afterwards, so
        // the handler writes at the moment it happens and hopes to finish.
        NSSetUncaughtExceptionHandler { exception in
            let line = "uncaught exception: \(exception.name.rawValue) \(exception.reason ?? "")"
            Diagnostics.appendFromAnywhere(line)
        }

        // The main thread stopping is the failure a log never records, because
        // the code that would record it is the code that is stuck. Timing the
        // gap between ticks catches it from outside.
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let gap = Date().timeIntervalSince(beat)
                if gap > 5 { write("the main thread stalled for \(Int(gap))s") }
                beat = Date()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private static func stop() {
        watchdog?.invalidate()
        watchdog = nil
        NSSetUncaughtExceptionHandler(nil)
    }

    static func write(_ line: String) {
        appendFromAnywhere(line)
    }

    /// Appends one line, creating the file if it is not there.
    ///
    /// `nonisolated` and free of any state but the path, because the exception
    /// handler runs on whatever thread died.
    nonisolated static func appendFromAnywhere(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp)  \(line)\n"
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let path = library.appendingPathComponent("Logs/Belay/belay.log")
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: path)
        }
    }
}
