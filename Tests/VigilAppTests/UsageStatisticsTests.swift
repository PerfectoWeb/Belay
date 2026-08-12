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

    /// Three sentences, one per case, and the tests say which case was chosen
    /// rather than what English it came out as. Asserting on the words is
    /// asserting that the Mac running the suite is set to English, which it was
    /// until somebody switched the app to Russian and six tests went red.
    private func summary(rescued: Int) -> String {
        var statistics = UsageStatistics()
        // A run counts as rescued only when it was left unattended.
        statistics.record(hold: 3600, away: rescued > 0 ? 3600 : 0, on: day)
        for offset in 1..<max(rescued, 1) {
            statistics.record(hold: 600, away: 600, on: day.addingTimeInterval(Double(offset) * 86_400))
        }
        XCTAssertEqual(statistics.totalRescued, max(rescued, 0), "fixture does not rescue what it claims")
        return ShareStatistics.summary(statistics)
    }

    func testShareTextClaimsNoRescueWhenThereWasNone() {
        let none = summary(rescued: 0)
        XCTAssertNotEqual(none, summary(rescued: 1), "nothing rescued reads like something was")
        XCTAssertNotEqual(none, summary(rescued: 3))
        XCTAssertFalse(none.lowercased().contains("saved"), none)
    }

    /// One rescue gets its own sentence rather than the plural one with a 1 in
    /// it, which is what a declining language needs.
    func testShareTextUsesSingularForOneRescue() {
        XCTAssertNotEqual(summary(rescued: 1), summary(rescued: 3))
    }

    func testShareCarriesTheLink() {
        var statistics = UsageStatistics()
        statistics.record(hold: 3600, away: 3600, on: day)
        XCTAssertTrue(ShareStatistics.items(from: statistics).contains { $0 is URL })
    }
}

/// Erasing the statistics.
@MainActor
final class UsageResetTests: XCTestCase {
    func testResetClearsEverythingIncludingTheRunInProgress() {
        let suite = "com.perfecto-web.vigil.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // `defaults.description` is not the domain name, so this emptied nothing
        // and left a suite behind on every run.
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = UsageRecorder(store: UsageStatisticsStore(defaults: defaults))
        let start = Date(timeIntervalSince1970: 1_780_000_000)

        recorder.update(holdingSince: start, now: start)
        recorder.update(holdingSince: nil, now: start.addingTimeInterval(600))
        XCTAssertFalse(recorder.statistics.isEmpty, "nothing was recorded to erase")

        // Mid-hold on purpose: a reset that banks the run you are in the middle
        // of is not a reset, and that run was already inside what was discarded.
        recorder.update(holdingSince: start.addingTimeInterval(700), now: start.addingTimeInterval(700))
        recorder.reset()
        XCTAssertTrue(recorder.statistics.isEmpty)
        XCTAssertNil(recorder.statistics.firstRun)

        recorder.update(holdingSince: nil, now: start.addingTimeInterval(1300))
        XCTAssertTrue(recorder.statistics.isEmpty, "the interrupted run came back after the reset")
    }
}
