import XCTest

@testable import Belay

/// The only network access in the app, so the tests are mostly about it not
/// happening.
@MainActor
final class ReleaseCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUp() async throws {
        suite = "belay.updates.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func checker(
        current: String = "1.0.0", body: @escaping @Sendable (URL) async throws -> Data
    ) -> ReleaseChecker {
        ReleaseChecker(defaults: defaults, current: current, fetch: body)
    }

    /// The promise in the About pane. A checker that runs before the user opts
    /// in makes that promise false on first launch, which is the worst possible
    /// moment for it.
    func testNothingIsFetchedUntilTheUserOptsIn() async {
        let touched = Sent()
        let checker = checker { _ in
            await touched.mark()
            return Data()
        }
        XCTAssertFalse(checker.isAutomatic, "update checks are on by default")
        checker.checkIfDue()
        try? await Task.sleep(nanoseconds: 100_000_000)
        let used = await touched.value
        XCTAssertFalse(used, "Belay reached the network without being asked")
    }

    func testADueCheckRunsOnceOptedIn() async throws {
        let checker = checker { _ in releaseJSON("1.2.0") }
        checker.isAutomatic = true
        try await settle(checker)
        XCTAssertEqual(
            checker.status, .available(version: "1.2.0", url: URL(string: "https://example.com/r")!))
    }

    /// Daily, not hourly: an update checker that runs on every launch is
    /// telemetry with extra steps.
    func testACheckIsNotRepeatedWithinTheInterval() async throws {
        let counter = Counter()
        let checker = checker { _ in
            await counter.bump()
            return releaseJSON("1.0.0")
        }
        checker.isAutomatic = true
        try await settle(checker)
        checker.checkIfDue()
        try await Task.sleep(nanoseconds: 100_000_000)
        let count = await counter.value
        XCTAssertEqual(count, 1, "checked \(count) times inside one interval")
    }

    func testTheManualButtonIgnoresTheInterval() async throws {
        let counter = Counter()
        let checker = checker { _ in
            await counter.bump()
            return releaseJSON("1.0.0")
        }
        checker.isAutomatic = true
        try await settle(checker)
        checker.check()
        try await settle(checker)
        let count = await counter.value
        XCTAssertEqual(count, 2, "Check Now did nothing")
    }

    func testAFailureIsReportedRatherThanSwallowed() async throws {
        let checker = checker { _ in throw ReleaseChecker.UpdateError.badResponse(404) }
        checker.check()
        try await settle(checker)
        guard case .failed = checker.status else { return XCTFail("\(checker.status)") }
    }

    /// String comparison calls 1.10.0 older than 1.9.0 and quietly stops
    /// offering updates at the tenth release.
    func testVersionsCompareNumerically() {
        XCTAssertTrue(ReleaseChecker.isNewer("1.10.0", than: "1.9.0"))
        XCTAssertTrue(ReleaseChecker.isNewer("2.0.0", than: "1.999.9"))
        XCTAssertFalse(ReleaseChecker.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(ReleaseChecker.isNewer("1.0.0", than: "1.0.1"))
        XCTAssertTrue(ReleaseChecker.isNewer("1.0.1", than: "1.0"))
    }

    private func settle(_ checker: ReleaseChecker) async throws {
        for _ in 0..<50 where checker.status == .checking {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

/// A free function, not a method: the fetch closure is `@Sendable` and cannot
/// capture the test case.
private func releaseJSON(_ tag: String) -> Data {
    Data(#"{"tag_name":"\#(tag)","html_url":"https://example.com/r"}"#.utf8)
}

private actor Sent {
    private(set) var value = false
    func mark() { value = true }
}

private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}
