import VigilCore
import XCTest

@testable import Vigil

/// PRD R7's notification is the feature that makes people install Vigil for a
/// reason other than sleep (docs/11 R8), and notification fatigue is what kills
/// utilities. So the rule that matters most here is "at most one per event,
/// never repeated for the same session".
final class AnnouncementTriggerTests: XCTestCase {
    private func snapshot(
        state: VigilState,
        sessions: [(String, SessionActivity)] = [],
        holdingSince: Date? = nil
    ) -> CoordinatorSnapshot {
        var states: [SessionState] = []
        var activities: [SessionID: SessionActivity] = [:]
        for (name, activity) in sessions {
            let id = SessionID(name)
            states.append(
                SessionState(id: id, provider: .claudeCode, workspace: "acme-api", firstSeen: Date())
            )
            activities[id] = activity
        }
        return CoordinatorSnapshot(
            state: state,
            sessions: states,
            activities: activities,
            holdReason: holdingSince == nil ? nil : .working(sessions: 1, workspace: "acme-api"),
            holdingSince: holdingSince
        )
    }

    func testAWaitingSessionIsAnnouncedExactlyOnce() {
        var trigger = AnnouncementTrigger()
        let blocked = snapshot(state: .awaitingUser, sessions: [("a", .awaitingUser)])

        let first = trigger.diff(blocked)
        XCTAssertEqual(first, [.needsInput(session: SessionID("a"), workspace: "acme-api")])

        // Fifteen minutes of polling must not produce fifteen notifications.
        for _ in 0..<15 {
            XCTAssertTrue(trigger.diff(blocked).isEmpty, "a still-waiting session was announced again")
        }
    }

    func testASessionThatResumesCanBeAnnouncedAgainLater() {
        var trigger = AnnouncementTrigger()
        _ = trigger.diff(snapshot(state: .awaitingUser, sessions: [("a", .awaitingUser)]))

        let resumed = trigger.diff(snapshot(state: .working, sessions: [("a", .working)]))
        XCTAssertEqual(resumed, [.resumed(SessionID("a"))])

        let blockedAgain = trigger.diff(snapshot(state: .awaitingUser, sessions: [("a", .awaitingUser)]))
        XCTAssertEqual(blockedAgain, [.needsInput(session: SessionID("a"), workspace: "acme-api")])
    }

    func testFinishedCarriesTheHoldDurationAndWorkspace() {
        var trigger = AnnouncementTrigger()
        let start = Date()
        _ = trigger.diff(
            snapshot(state: .working, sessions: [("a", .working)], holdingSince: start),
            now: start
        )

        let ended = trigger.diff(snapshot(state: .armed), now: start.addingTimeInterval(600))
        guard case .finished(let duration, let workspace) = ended.first else {
            return XCTFail("expected a finished announcement, got \(ended)")
        }
        XCTAssertEqual(duration, 600, accuracy: 1)
        // The session is gone from the snapshot by the time the hold ends, so
        // the workspace has to have been remembered.
        XCTAssertEqual(workspace, "acme-api")
    }

    func testSafetyReleaseIsAnnouncedOncePerTransition() {
        var trigger = AnnouncementTrigger()
        let low = snapshot(state: .suspended(.batteryLow(charge: 0.15)))

        XCTAssertEqual(trigger.diff(low), [.releasedForSafety(.batteryLow(charge: 0.15))])
        XCTAssertTrue(trigger.diff(low).isEmpty, "the same suspension was announced twice")
    }

    func testNothingIsAnnouncedForOrdinaryIdleWork() {
        var trigger = AnnouncementTrigger()
        XCTAssertTrue(trigger.diff(snapshot(state: .armed)).isEmpty)
        XCTAssertTrue(trigger.diff(snapshot(state: .armed)).isEmpty)
    }
}
