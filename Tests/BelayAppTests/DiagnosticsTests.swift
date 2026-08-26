import XCTest

@testable import Belay

/// The dirty-shutdown breadcrumb: a SIGKILL writes nothing, so the next
/// launch has to read the absence. Born from a field report — Belay gone in
/// the morning, no crash report, log simply stopping mid-hold.
@MainActor
final class DiagnosticsTests: XCTestCase {
    func testAGoodbyeAfterTheLastHelloIsClean() {
        let tail = """
            2026-08-25T10:00:00Z  collection on, Belay 1.6.0
            2026-08-25T12:00:00Z  hold on reason="x" display=1
            2026-08-25T12:34:00Z  collection off
            """
        XCTAssertFalse(Diagnostics.endedDirty(tail: tail))
    }

    func testAHelloWithNoGoodbyeIsDirty() {
        let tail = """
            2026-08-25T10:00:00Z  collection off
            2026-08-25T11:00:00Z  collection on, Belay 1.6.0
            2026-08-25T12:00:00Z  hold on reason="x" display=1
            """
        XCTAssertTrue(Diagnostics.endedDirty(tail: tail))
    }

    func testALogWithNoMarkersSaysNothing() {
        XCTAssertFalse(Diagnostics.endedDirty(tail: ""))
        XCTAssertFalse(Diagnostics.endedDirty(tail: "2026-08-25T10:00:00Z  hold on"))
    }

    func testOnlyTheLatestSessionCounts() {
        let tail = """
            2026-08-24T10:00:00Z  collection on, Belay 1.5.0
            2026-08-24T22:00:00Z  collection off
            2026-08-25T09:00:00Z  collection on, Belay 1.6.0
            """
        XCTAssertTrue(Diagnostics.endedDirty(tail: tail))
    }
}
