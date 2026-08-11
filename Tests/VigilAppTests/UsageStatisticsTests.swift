import XCTest

@testable import Vigil

/// The statistics exist to tell the user something true. A number that flatters
/// the app is worse than no number, so most of these tests are about what it
/// must *not* claim.
final class UsageStatisticsTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_760_000_000)

    func testAHoldWithNobodyAwayIsNotARescue() {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: 0, on: day)
        XCTAssertEqual(statistics.totalHolds, 1)
        XCTAssertEqual(statistics.totalRescued, 0, "an hour at the keyboard rescued nothing")
        XCTAssertEqual(statistics.totalAway, 0)
    }

    func testBriefAbsenceIsNotARescueEither() {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: AwayTime.threshold - 1, on: day)
        XCTAssertEqual(statistics.totalRescued, 0)
    }

    func testRealAbsenceCounts() {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: AwayTime.threshold, on: day)
        XCTAssertEqual(statistics.totalRescued, 1)
        XCTAssertEqual(statistics.totalAway, AwayTime.threshold)
    }

    func testAwayTimeNeverExceedsTimeHeld() {
        var statistics = UsageStatistics()
        statistics.record(hold: 600, away: 600, on: day)
        XCTAssertLessThanOrEqual(statistics.totalAway, statistics.totalHeld)
    }

    func testSameDayAccumulatesIntoOneBucket() {
        var statistics = UsageStatistics()
        statistics.record(hold: 600, away: 600, on: day)
        statistics.record(hold: 1200, away: 0, on: day.addingTimeInterval(3600))
        XCTAssertEqual(statistics.days.count, 1)
        XCTAssertEqual(statistics.totalHeld, 1800)
        XCTAssertEqual(statistics.longestHold, 1200)
        XCTAssertEqual(statistics.totalHolds, 2)
    }

    func testZeroLengthHoldsAreIgnored() {
        var statistics = UsageStatistics()
        statistics.record(hold: 0, away: 0, on: day)
        XCTAssertTrue(statistics.isEmpty)
        XCTAssertNil(statistics.firstRun)
    }

    /// Ninety days is the promise; a year of daily use must not grow without
    /// bound in the preferences file.
    func testOldDaysAreDropped() {
        var statistics = UsageStatistics()
        for offset in 0..<200 {
            let date = day.addingTimeInterval(Double(offset) * 86_400)
            statistics.record(hold: 60, away: 0, on: date)
        }
        XCTAssertLessThanOrEqual(statistics.days.count, UsageStatistics.keptDays + 1)
    }

    /// A chart that silently drops empty days misrepresents the shape of a week.
    func testRecentIncludesQuietDays() {
        var statistics = UsageStatistics()
        statistics.record(hold: 600, away: 600, on: day)
        let window = statistics.recent(14, now: day.addingTimeInterval(6 * 86_400))
        XCTAssertEqual(window.count, 14)
        XCTAssertEqual(window.filter { $0.heldSeconds > 0 }.count, 1)
        XCTAssertEqual(window.map(\.date), window.map(\.date).sorted(), "days must run oldest first")
    }

    func testRoundTripsThroughStorage() throws {
        var statistics = UsageStatistics()
        statistics.record(hold: 900, away: 900, on: day)
        let data = try JSONEncoder().encode(statistics)
        XCTAssertEqual(try JSONDecoder().decode(UsageStatistics.self, from: data), statistics)
    }

    // MARK: - what the share text is allowed to say

    func testShareTextClaimsNoRescueWhenThereWasNone() {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: 0, on: day)
        let summary = ShareStatistics.summary(statistics)
        XCTAssertFalse(summary.lowercased().contains("saved"), summary)
        XCTAssertTrue(summary.contains("1 agent runs") || summary.contains("watched 1"), summary)
    }

    func testShareTextUsesSingularForOneRescue() {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: 3600, on: day)
        let summary = ShareStatistics.summary(statistics)
        XCTAssertTrue(summary.contains("1 agent run "), summary)
        XCTAssertFalse(summary.contains("1 agent runs"), summary)
    }

    func testShareCarriesTheLink() {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: 3600, on: day)
        XCTAssertTrue(ShareStatistics.items(from: statistics).contains { $0 is URL })
    }
}
