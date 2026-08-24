import BelayCore
import BelayProviders
import BelaySupport
import XCTest

/// Runs the real Cline CLI through one tiny turn and asserts the provider saw
/// it. Costs one model call on the user's configured provider; runs only with
/// `BELAY_LIVE_CLINE` set, like the other live stands.
final class LiveClineTests: XCTestCase {
    func testOneRealTurnIsSeen() async throws {
        guard ProcessInfo.processInfo.environment["BELAY_LIVE_CLINE"] != nil else {
            throw XCTSkip("set BELAY_LIVE_CLINE to run a real cline turn")
        }
        let binary = "/opt/homebrew/bin/cline"
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            throw XCTSkip("cline is not installed")
        }

        let provider = ClineProvider(configuration: .clineHome(), access: DirectFileAccess())
        try await provider.start()
        actor Seen {
            var activities: [SessionActivity] = []
            func note(_ signal: ActivitySignal) { activities.append(signal.activity) }
        }
        let seen = Seen()
        let stream = await provider.signals
        let pump = Task {
            for await signal in stream {
                print("live cline signal: \(signal.session) \(signal.activity)")
                await seen.note(signal)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-t", "90", "Reply with exactly: ok. Do not use any tools."]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        // The turn plus slack; the provider should see working while it runs
        // and the ending when the status file closes out.
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
