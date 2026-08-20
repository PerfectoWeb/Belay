import Foundation

/// The root daemon behind "hold through a closed lid" (docs/ROADMAP).
///
/// It does one thing: `pmset -a disablesleep`, the only lever that survives a
/// closing lid. Everything else here exists to make that lever safe to own:
///
/// - The flag never outlives its deadline. Every `keepSleepDisabled` arms a
///   timer, and the timer's only job is to clear the flag when the app stops
///   asking. A crashed Belay costs one leash length, nothing more.
/// - The flag never survives a restart of anything *that Belay raised*. A
///   sentinel file is written before the flag ever goes up, recording what the
///   flag was beforehand; startup restores that recorded value and a Mac whose
///   owner runs `disablesleep 1` by their own hand keeps their setting. The
///   ordering is crash-safe: sentinel first, flag second, so there is no
///   moment where the flag is ours and the restore value is not on disk.
/// - Only Belay may speak. The connection requires Belay's code signature;
///   anything else on the machine is refused before a byte of protocol runs.
final class SleepFlag: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.perfectoweb.belay.lidhelper.flag")
    private var expiry: DispatchSourceTimer?

    /// Root-owned, in root's own territory. Its presence means "the flag is
    /// Belay's"; its content is the value to put back.
    private static let sentinel = URL(fileURLWithPath: "/var/db/com.perfectoweb.belay.lidhold")

    func keep(until deadline: Date) -> Bool {
        queue.sync {
            let leash = min(
                deadline.timeIntervalSinceNow, LidDaemon.maximumLeash)
            guard leash > 0 else { return lowerLocked() }
            if !FileManager.default.fileExists(atPath: Self.sentinel.path) {
                let prior = Self.currentValue() ?? false
                try? Data((prior ? "1" : "0").utf8).write(to: Self.sentinel)
            }
            guard Self.pmset(disabled: true) else { return false }
            expiry?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            // Wall deadline on purpose: if the machine is somehow forced
            // asleep mid-leash, a suspended monotonic timer would hold the
            // flag for a stale leash after wake; a wall deadline fires the
            // moment the Mac is back.
            timer.schedule(wallDeadline: .now() + leash)
            timer.setEventHandler { [weak self] in _ = self?.lowerLocked() }
            timer.resume()
            expiry = timer
            return true
        }
    }

    func lower() -> Bool {
        queue.sync { lowerLocked() }
    }

    /// Restores what the sentinel recorded — 0 for everyone who never touched
    /// pmset themselves — and only forgets the sentinel once the restore
    /// actually happened. No sentinel means the flag was never Belay's, and a
    /// flag that is not ours is not ours to lower either. Returns whether the
    /// flag is *back to its owner's value*, which is the caller's question.
    private func lowerLocked() -> Bool {
        expiry?.cancel()
        expiry = nil
        guard FileManager.default.fileExists(atPath: Self.sentinel.path) else { return true }
        let restore =
            (try? String(contentsOf: Self.sentinel, encoding: .utf8))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "1" } ?? false
        guard Self.pmset(disabled: restore) else { return false }
        try? FileManager.default.removeItem(at: Self.sentinel)
        return true
    }

    /// Whether Belay raised the flag in a previous life and never lowered it.
    var owesARestore: Bool {
        queue.sync { FileManager.default.fileExists(atPath: Self.sentinel.path) }
    }

    /// One boot's worth of old-world cleanup. Helpers before the sentinel
    /// lowered blindly at startup, so their leftover flag carries no sentinel
    /// and would otherwise read as the owner's deliberate setting. The first
    /// start of a sentinel-aware helper clears it the old way, leaves a
    /// marker, and never does so again — from then on, a bare flag at boot is
    /// respected as the owner's.
    func migrateFromTheBlindEra() {
        queue.sync {
            guard !FileManager.default.fileExists(atPath: Self.migrated.path) else { return }
            if !FileManager.default.fileExists(atPath: Self.sentinel.path) {
                _ = Self.pmset(disabled: false)
            }
            try? Data("1".utf8).write(to: Self.migrated)
        }
    }

    private static let migrated = URL(
        fileURLWithPath: "/var/db/com.perfectoweb.belay.lidhold.migrated")

    private static func pmset(disabled: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Reads `SleepDisabled` out of `pmset -g`, or `nil` when it cannot.
    private static func currentValue() -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
            let text = String(bytes: data, encoding: .utf8)
        else { return nil }
        for line in text.split(separator: "\n") {
            let lowered = line.lowercased()
            guard lowered.contains("sleepdisabled") else { continue }
            return lowered.hasSuffix("1")
        }
        return nil
    }
}

final class SwitchKeeper: NSObject, NSXPCListenerDelegate, LidHelperProtocol {
    private let flag = SleepFlag()

    /// Belay, signed by us, and nobody else. The requirement covers both the
    /// notarized Developer ID build and a debug build signed to the same team.
    private static let requirement = """
        identifier "com.perfectoweb.belay" and anchor apple generic and \
        certificate leaf[subject.OU] = VSY2EB4Y9E
        """

    func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.setCodeSigningRequirement(Self.requirement)
        connection.exportedInterface = NSXPCInterface(with: LidHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func keepSleepDisabled(until deadline: Date, reply: @Sendable @escaping (Bool) -> Void) {
        reply(flag.keep(until: deadline))
    }

    func standDown(reply: @Sendable @escaping (Bool) -> Void) {
        reply(flag.lower())
    }

    func version(reply: @Sendable @escaping (String) -> Void) {
        reply(LidDaemon.version)
    }

    /// Startup is a cleanup — but only of Belay's own mess. A sentinel on disk
    /// means a previous life raised the flag and never restored it, so restore
    /// it now. No sentinel means the flag, whatever it reads, belongs to the
    /// machine's owner, and a helper that "cleans" it at every boot would be
    /// overwriting their deliberate setting.
    func clearStaleFlag() {
        flag.migrateFromTheBlindEra()
        guard flag.owesARestore else { return }
        _ = flag.lower()
    }
}

let helper = SwitchKeeper()
helper.clearStaleFlag()
let listener = NSXPCListener(machServiceName: LidDaemon.machService)
listener.delegate = helper
listener.resume()
RunLoop.main.run()
