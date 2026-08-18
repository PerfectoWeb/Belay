import Foundation

/// The root daemon behind "hold through a closed lid" (docs/ROADMAP).
///
/// It does one thing: `pmset -a disablesleep`, the only lever that survives a
/// closing lid. Everything else here exists to make that lever safe to own:
///
/// - The flag never outlives its deadline. Every `keepSleepDisabled` arms a
///   timer, and the timer's only job is to clear the flag when the app stops
///   asking. A crashed Belay costs one leash length, nothing more.
/// - The flag never survives a restart of anything. `pmset disablesleep`
///   persists in the power-management preferences, so a helper that starts —
///   at boot via RunAtLoad, or relaunched by launchd — clears it first and
///   asks questions never.
/// - Only Belay may speak. The connection requires Belay's code signature;
///   anything else on the machine is refused before a byte of protocol runs.
final class SleepFlag: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.perfectoweb.belay.lidhelper.flag")
    private var expiry: DispatchSourceTimer?

    func keep(until deadline: Date) -> Bool {
        queue.sync {
            let leash = min(
                deadline.timeIntervalSinceNow, LidDaemon.maximumLeash)
            guard leash > 0 else { return lowerLocked() }
            guard Self.pmset(disabled: true) else { return false }
            expiry?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + leash)
            timer.setEventHandler { [weak self] in _ = self?.lowerLocked() }
            timer.resume()
            expiry = timer
            return true
        }
    }

    func lower() -> Bool {
        queue.sync { lowerLocked() }
    }

    /// Returns whether the flag is *down*, which is the caller's question.
    private func lowerLocked() -> Bool {
        expiry?.cancel()
        expiry = nil
        return Self.pmset(disabled: false)
    }

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

    func keepSleepDisabled(until deadline: Date, reply: @escaping (Bool) -> Void) {
        reply(flag.keep(until: deadline))
    }

    func standDown(reply: @escaping (Bool) -> Void) {
        reply(flag.lower())
    }

    func version(reply: @escaping (String) -> Void) {
        reply(LidDaemon.version)
    }

    /// Startup is a cleanup: whatever a previous life left set, unset.
    func clearStaleFlag() {
        _ = flag.lower()
    }
}

let helper = SwitchKeeper()
helper.clearStaleFlag()
let listener = NSXPCListener(machServiceName: LidDaemon.machService)
listener.delegate = helper
listener.resume()
RunLoop.main.run()
