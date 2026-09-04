import BelaySupport
import Foundation
import OSLog
import os

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
    // `systemUptime`, not `Date`: the wall clock keeps running while the Mac
    // sleeps, and a dark wake fires this timer without any wake notification —
    // every nap over five seconds then read as "the main thread stalled".
    // Uptime stands still with the machine, so a gap in it is a real stall.
    private static var beat = ProcessInfo.processInfo.systemUptime

    /// Turns collection on or off. Safe to call with the value it already has.
    static func setEnabled(_ on: Bool) {
        if on { start() } else { stop() }
    }

    private static func start() {
        guard watchdog == nil else { return }
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        // Trim while the gate is still shut: an append from another thread
        // landing inside the atomic replace would vanish with the old file.
        // And before the tail is read: the kept megabyte is exactly the
        // window `endedDirty` looks at, so nothing it needs is ever cut.
        LogTrim.trimIfOversized(file)
        collecting.withLock { $0 = true }
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
                let gap = ProcessInfo.processInfo.systemUptime - beat
                if gap > 5 { write("the main thread stalled for \(Int(gap))s") }
                beat = ProcessInfo.processInfo.systemUptime
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private static func stop() {
        flushRepeats()
        write("collection off")
        collecting.withLock { $0 = false }
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
        // A megabyte, not a token 64KB: a busy multi-day session writes more
        // than 64KB after its "collection on", pushing the marker out of the
        // window and silently disabling dirty-exit detection. Read once, at
        // collection start.
        let window: UInt64 = 1_048_576
        let start = size > window ? size - window : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// Called on wake from system sleep. The watchdog measures gaps between
    /// main-thread ticks, and a slept Mac produces a gap of exactly the nap's
    /// length — which then reads as "the main thread stalled for 69s" over a
    /// stall that never happened. The beat restarts at the wake instead.
    static func resetBeat() {
        beat = ProcessInfo.processInfo.systemUptime
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

    /// A line that keeps arriving, and how long it has been arriving for.
    ///
    /// Belay's own log was the thing that crashed a user's Mac overnight — not
    /// through any one line, but through the sheer number of them. A failure
    /// that repeats on a timer writes the same sentence for as long as it
    /// lasts: an unreachable lid helper produced one every fifteen seconds,
    /// which is 5 760 identical lines a day and not one fact more than the
    /// first one carried.
    ///
    /// So consecutive identical lines are counted rather than written, and the
    /// count is written instead. The summary still lands, because a log that
    /// swallows a live fault entirely is its own kind of lie — but it lands on
    /// a widening interval: a minute in, then two, then four, up to an hour.
    /// The first minutes of a fault are when somebody is reading; the tenth
    /// hour of the same fault needs one line, not two hundred.
    private struct Repeats: Sendable {
        var line = ""
        var held = 0
        var since = Date.distantPast
        var step: TimeInterval = firstWindow
    }

    nonisolated private static let repeats = OSAllocatedUnfairLock(initialState: Repeats())
    /// Readable from any thread, because the paths that write "from anywhere"
    /// run on whatever thread died — or on the signal source.
    nonisolated private static let collecting = OSAllocatedUnfairLock(initialState: false)

    /// How long after a summary the next one may come, at first.
    nonisolated static let firstWindow: TimeInterval = 60
    /// And the longest that interval ever grows to.
    nonisolated static let longestWindow: TimeInterval = 60 * 60

    /// What should actually be written for `line`, given what came before it.
    ///
    /// Pure but for the counter it owns, and separated from the file so the
    /// rule can be tested without a disk: `DiagnosticsTests` drives this.
    nonisolated static func collapse(_ line: String, now: Date = Date()) -> [String] {
        repeats.withLock { state in
            guard line == state.line else {
                var out: [String] = []
                if state.held != 0 { out.append(summary(of: state)) }
                state = Repeats(line: line, held: 0, since: now)
                out.append(line)
                return out
            }
            state.held += 1
            let due = now.timeIntervalSince(state.since) >= state.step
            guard due else { return [] }
            let out = [summary(of: state)]
            state.held = 0
            state.since = now
            state.step = min(state.step * 2, longestWindow)
            return out
        }
    }

    nonisolated private static func summary(of state: Repeats) -> String {
        "the line above repeated \(state.held) more time\(state.held == 1 ? "" : "s")"
    }

    /// Everything held back, written now. Called before the log stops, so a
    /// run does not end with a count nobody ever sees.
    nonisolated static func flushRepeats() {
        let pending: [String] = repeats.withLock { state in
            guard state.held != 0 else { return [] }
            let out = [summary(of: state)]
            state.held = 0
            return out
        }
        for line in pending { rawAppend(line) }
    }

    /// Appends one line, creating the file if it is not there.
    ///
    /// `nonisolated` and free of any state but the path, because the exception
    /// handler runs on whatever thread died.
    nonisolated static func appendFromAnywhere(_ line: String) {
        // Off means off. The exception handler and the EventLog sink are only
        // installed while collection is on, but the termination path calls
        // this unconditionally — and a user who never enabled Local Reports
        // must not find a log file created by every logout.
        guard collecting.withLock({ $0 }) else { return }
        for text in collapse(line) { rawAppend(text) }
    }

    /// One line to the file, with no counting in front of it.
    nonisolated private static func rawAppend(_ line: String) {
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
