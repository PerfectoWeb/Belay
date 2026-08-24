import BelayCore
import BelayProviders
import BelaySupport
import XCTest

/// Runs the real Copilot CLI through one tiny turn and asserts the provider
/// saw it. Costs one model call on the user's Copilot quota; runs only with
/// `BELAY_LIVE_COPILOT` set, like the other live stands.
final class LiveCopilotTests: XCTestCase {
    func testOneRealTurnIsSeen() async throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_COPILOT"] != nil else {
            throw XCTSkip("set BELAY_LIVE_COPILOT to run a real copilot turn")
        }
        let binary = "/opt/homebrew/bin/copilot"
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw XCTSkip("copilot is not installed")
        }

        let provider = CopilotProvider(configuration: .copilotHome(), access: DirectFileAccess())
        try await provider.start()
        actor Seen {
            var activities: [SessionActivity] = []
            func note(_ signal: ActivitySignal) { activities.append(signal.activity) }
        }
        let seen = Seen()
        let stream = await provider.signals
        let pump = Task {
            for await signal in stream {
                print("live copilot signal: \(signal.session) \(signal.activity) ws=\(signal.workspace ?? "?")")
                await seen.note(signal)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-p", "Reply with exactly: ok. Do not use any tools."]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        // The CLI's own output, kept: when the turn stalls, this transcript is
        // the only witness saying why.
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("belay-live-copilot.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let sink = try FileHandle(forWritingTo: log)
        // Copilot finds its auth by shelling out to `gh`, which lives in
        // /opt/homebrew/bin — absent from a test host's PATH, and the turn
        // dies at the door with "No authentication information found".
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = sink
        process.standardError = sink
        try process.run()
        print("live copilot log: \(log.path)")

        // The turn plus slack; the provider should see working while it runs
        // and the ending when session.shutdown lands.
        let deadline = Date().addingTimeInterval(120)
        var worked = false
        var closed = false
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let activities = await seen.activities
            worked = worked || activities.contains(.working)
            closed = activities.contains(.ended) || activities.contains(.idle)
            if worked && closed { break }
        }
        process.terminate()
        pump.cancel()
        await provider.stop()

        XCTAssertTrue(worked, "the live turn never reported working")
        XCTAssertTrue(closed, "the finished turn never closed out")
    }
}
