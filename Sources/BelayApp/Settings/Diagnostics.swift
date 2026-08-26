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
        // A SIGKILL leaves no crash report and no goodbye, so the only place
        // it can ever be seen is here, on the next launch. Caught in the
        // field: an overnight death that looked like nothing at all.
        if endedDirty(tail: logTail()) {
            write("previous run ended without a shutdown mark: killed, crashed, or forced off")
        }
        write("collection on, Belay \(Branding.version)")
        // From here the kit modules write too — sessions appearing and dying,
        // assertions going up and down. Same file, same shape.
        EventLog.install { appendFromAnywhere($0) }

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
        write("collection off")
        EventLog.install(nil)
        watchdog?.invalidate()
        watchdog = nil
        NSSetUncaughtExceptionHandler(nil)
    }

    /// Whether the log's previous session never said goodbye: a
    /// `collection on` with no `collection off` after it. The one line each
    /// graceful exit writes is what makes the silent kind visible.
    static func endedDirty(tail: String) -> Bool {
        guard let lastOn = tail.range(of: "collection on", options: .backwards) else { return false }
        guard let lastOff = tail.range(of: "collection off", options: .backwards) else { return true }
        return lastOff.lowerBound < lastOn.lowerBound
    }

    /// The last stretch of the log, enough to hold the previous session's
    /// markers without reading a multi-day file whole.
    private static func logTail() -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 65_536 ? size - 65_536 : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Called on wake from system sleep. The watchdog measures gaps between
    /// main-thread ticks, and a slept Mac produces a gap of exactly the nap's
    /// length — which then reads as "the main thread stalled for 69s" over a
    /// stall that never happened. The beat restarts at the wake instead.
    static func resetBeat() {
        beat = Date()
    }

    static func write(_ line: String) {
        appendFromAnywhere(line)
    }

    /// One structured event, written only while collection is on. The format
    /// is `subject verb key=value …`, one line, greppable: these lines exist
    /// so that after a test run the log alone can say what fired, when, and
    /// with which numbers — not to read as prose.
    static func note(_ line: String) {
        guard watchdog != nil else { return }
        write(line)
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
