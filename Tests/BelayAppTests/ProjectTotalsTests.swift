import BelayCore
import XCTest

@testable import Belay

/// The headline's numbers are the sum of the rows under it, always: built from
/// the same records the table shows, never a separate accumulator that could
/// drift. So a folder's totals add up its sessions, remember who reported
/// tokens, and match the list exactly.
final class ProjectTotalsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func record(
        _ folder: String?, minutes: Double, tokens: Int? = nil, at offset: TimeInterval = 0
    ) -> SessionRecord {
        SessionRecord(
            id: UUID(), provider: .claudeCode, workspace: folder,
            startedAt: start + offset, endedAt: start + offset + minutes * 60, tokens: tokens)
    }

    func testTotalsAreTheSumOfTheRows() {
        let rows = [
            record("belay", minutes: 30, tokens: 1000),
            record("belay", minutes: 15, at: 3600),
            record("belay", minutes: 5, tokens: 20, at: -600),
        ]
        let totals = ProjectTotals.over(rows)
        XCTAssertEqual(totals.sessions, rows.count, "the headline count is the row count")
        XCTAssertEqual(totals.seconds, 50 * 60, accuracy: 1)
        XCTAssertEqual(totals.tokens, 1020)
        XCTAssertEqual(totals.tokenSessions, 2, "one of the three never said")
    }

    func testTokensLabelIsADashWhenNobodyReported() {
        XCTAssertEqual(ProjectTotals.over([record("belay", minutes: 10)]).tokensLabel, "\u{2014}")
        XCTAssertEqual(
            ProjectTotals.over([record("belay", minutes: 10, tokens: 45_200)]).tokensLabel, "45.2k")
    }

    func testCaptionDropsTheSecondCount() {
        // Under the table the time is the headline, so the caption omits it;
        // and it never repeats the session count as a "reported" figure.
        let totals = ProjectTotals.over([
            record("belay", minutes: 10, tokens: 5), record("belay", minutes: 10),
        ])
        let caption = totals.caption(withTime: false)
        XCTAssertTrue(caption.contains("2 sessions"))
        XCTAssertFalse(caption.contains("reported"), "no second session count to contradict the first")
    }

    func testEmptyIsAllZeros() {
        XCTAssertEqual(ProjectTotals.over([]), ProjectTotals())
    }
}
