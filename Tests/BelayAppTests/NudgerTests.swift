import BelayCore
import BelayModules
import XCTest

@testable import Belay

/// No test here plays a sound or posts a banner: both are lists, and time is
/// a clock the test moves.
@MainActor
final class NudgerTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""
    private let sounds = FakeSounds()
    private let notices = FakeNotices()
    private let apps = FakeAgentApps()
    private let clock = TestClock()

    override func setUp() async throws {
        suiteName = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        apps.seat("a", in: "com.example.editor")
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeNudger() throws -> Nudger {
        Nudger(
            defaults: try XCTUnwrap(defaults), sounds: sounds, notices: notices, finder: apps,
            now: { [clock] in clock.now })
    }

    private func snapshot(
        _ activity: SessionActivity?, session: String = "a", workspace: String = "Belay"
    ) -> CoordinatorSnapshot {
        guard let activity else { return .idle }
        let state = SessionState(
            id: SessionID(session), provider: .claudeCode, workspace: workspace,
            firstSeen: clock.now)
        return CoordinatorSnapshot(
            state: .working, sessions: [state], activities: [state.id: activity],
            holdReason: nil, holdingSince: nil)
    }

    private func eventually(
        _ what: String, file: StaticString = #filePath, line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), what, file: file, line: line)
    }

    func testNothingHappensBeforeItIsSwitchedOn() throws {
        let nudger = try makeNudger()
        nudger.observe(snapshot(.working))
        clock.advance(by: 600)
        nudger.observe(snapshot(.awaitingUser))
        clock.advance(by: 600)
        nudger.tick()

        XCTAssertTrue(sounds.played.isEmpty)
        XCTAssertTrue(notices.posted.isEmpty)
        XCTAssertEqual(nudger.waiting, 0)
        XCTAssertEqual(notices.asked, 0, "asked macOS for notifications before being switched on")
    }

    func testSwitchingOnAsksForNotificationsAndALaunchDoesNot() async throws {
        let nudger = try makeNudger()
        nudger.start()
        await Task.yield()
        XCTAssertEqual(notices.asked, 0, "a launch must never raise the question")
        nudger.stop()

        nudger.activate()
        await eventually("never asked") { notices.asked == 1 }
    }

    func testAFinishedRunSoundsAndNamesItsWorkspace() throws {
        let nudger = try makeNudger()
        nudger.start()
        nudger.observe(snapshot(.working))
        clock.advance(by: 12 * 60)
        nudger.observe(snapshot(.idle))

        XCTAssertEqual(sounds.played, [.nudgeFinished])
        XCTAssertEqual(notices.posted.count, 1)
        XCTAssertTrue(notices.posted[0].body.contains("Belay"))
        XCTAssertEqual(notices.posted[0].bundleID, "com.example.editor")
    }

    func testARunShorterThanTheMinimumSaysNothing() throws {
        let nudger = try makeNudger()
        nudger.start()
        nudger.observe(snapshot(.working))
        clock.advance(by: 10)
        nudger.observe(snapshot(.idle))

        XCTAssertTrue(sounds.played.isEmpty)
        XCTAssertTrue(notices.posted.isEmpty)
    }

    func testWaitingSoundsOnceAndIsCounted() throws {
        let nudger = try makeNudger()
        nudger.start()
        nudger.observe(snapshot(.working))
        nudger.observe(snapshot(.awaitingUser))
        nudger.observe(snapshot(.awaitingUser))

        XCTAssertEqual(sounds.played, [.nudgeWaiting])
        XCTAssertEqual(nudger.waiting, 1)
        nudger.observe(snapshot(.working))
        XCTAssertEqual(nudger.waiting, 0)
    }

    func testAReminderIsPostedWithTheAppToRaiseAndStopsAtTheCap() throws {
        let nudger = try makeNudger()
        nudger.start()
        nudger.observe(snapshot(.awaitingUser))
        clock.advance(by: 299)
        nudger.tick()
        XCTAssertTrue(notices.posted.isEmpty)

        clock.advance(by: 1)
        nudger.tick()
        XCTAssertEqual(notices.posted.count, 1)
        let first = notices.posted[0]
        XCTAssertEqual(first.bundleID, "com.example.editor")
        XCTAssertTrue(first.body.contains("Belay"))

        for _ in 0..<10 {
            clock.advance(by: 300)
            nudger.tick()
        }
        XCTAssertEqual(notices.posted.count, 3, "the default cap is three")
        XCTAssertEqual(sounds.played, [.nudgeWaiting], "a reminder is a banner, not a second chime")
    }

    func testEachSoundFollowsItsCheckbox() throws {
        let nudger = try makeNudger()
        nudger.rules.finishedSound = false
        nudger.rules.waitingSound = false
        nudger.rules.quietSound = false
        nudger.rules.namesFinished = false
        nudger.start()
        nudger.observe(snapshot(.working))
        clock.advance(by: 60)
        nudger.observe(snapshot(.awaitingUser))
        nudger.observe(snapshot(.working))
        nudger.observe(snapshot(.idle))
        nudger.observe(snapshot(.working))
        nudger.observe(snapshot(nil))

        XCTAssertTrue(sounds.played.isEmpty)
        XCTAssertTrue(notices.posted.isEmpty)
    }

    func testAVanishedWorkingSessionPlaysTheQuietNote() throws {
        let nudger = try makeNudger()
        nudger.start()
        nudger.observe(snapshot(.working))
        nudger.observe(snapshot(nil))

        XCTAssertEqual(sounds.played, [.nudgeQuiet])
    }

    func testSwitchingOffLetsGo() throws {
        let nudger = try makeNudger()
        nudger.start()
        nudger.observe(snapshot(.awaitingUser))
        XCTAssertEqual(nudger.waiting, 1)
        sounds.clear()

        nudger.stop()
        XCTAssertEqual(nudger.waiting, 0)
        clock.advance(by: 3_600)
        nudger.tick()
        nudger.observe(snapshot(.awaitingUser))

        XCTAssertTrue(sounds.played.isEmpty)
        XCTAssertTrue(notices.posted.isEmpty)
    }

    func testRefusalShowsAndRecovers() async throws {
        notices.refused = true
        let nudger = try makeNudger()
        nudger.activate()
        await eventually("did not notice the refusal") { nudger.notificationsRefused }

        notices.refused = false
        for _ in 0..<4 { nudger.tick() }
        await eventually("did not notice the permission") { !nudger.notificationsRefused }
    }

    func testRemovingForgetsTheRules() throws {
        let defaults = try XCTUnwrap(defaults)
        let nudger = try makeNudger()
        nudger.rules.repeatAfterMinutes = 10
        XCTAssertNotNil(defaults.data(forKey: NudgeRules.defaultsKey))

        nudger.forgetEverything()

        XCTAssertNil(defaults.object(forKey: NudgeRules.defaultsKey))
        XCTAssertEqual(nudger.rules, NudgeRules())
    }

    func testTheRulesComeBackAfterARelaunch() throws {
        let nudger = try makeNudger()
        nudger.rules.minimumRunSeconds = 300
        nudger.rules.quietSound = false

        let again = try makeNudger()
        XCTAssertEqual(again.rules.minimumRunSeconds, 300)
        XCTAssertFalse(again.rules.quietSound)
    }

    func testTheBannerCarriesTheAppAndTheClickReadsItBack() {
        let content = Notifier.content(
            category: .nudge, title: "t", body: "b",
            userInfo: [Notifier.raiseKey: "com.anthropic.claudefordesktop"])

        XCTAssertEqual(content.categoryIdentifier, "belay.nudge")
        XCTAssertNil(content.sound)
        XCTAssertEqual(
            NotificationClicks.raiseTarget(in: content.userInfo), "com.anthropic.claudefordesktop")
        XCTAssertNil(NotificationClicks.raiseTarget(in: [:]))
        XCTAssertNil(NotificationClicks.raiseTarget(in: [Notifier.raiseKey: ""]))
        XCTAssertNil(NotificationClicks.raiseTarget(in: [Notifier.raiseKey: 7]))
    }
}
