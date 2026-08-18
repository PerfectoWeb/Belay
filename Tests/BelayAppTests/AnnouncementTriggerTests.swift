import BelayCore
import XCTest

@testable import Belay

/// PRD R7's notification is the feature that makes people install Belay for a
/// reason other than sleep (docs/11 R8), and notification fatigue is what kills
/// utilities. So the rule that matters most here is "at most one per event,
/// never repeated for the same session".
final class AnnouncementTriggerTests: XCTestCase {
    private func snapshot(
        state: BelayState,
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

    private func tree(
        state: BelayState,
        sessions: [(String, SessionActivity, String?)]
    ) -> CoordinatorSnapshot {
        var states: [SessionState] = []
        var activities: [SessionID: SessionActivity] = [:]
        for (name, activity, parent) in sessions {
            let id = SessionID(name)
            var session = SessionState(
                id: id, provider: .claudeCode, workspace: "acme-api", firstSeen: Date())
            session.parent = parent.map(SessionID.init)
            states.append(session)
            activities[id] = activity
        }
        return CoordinatorSnapshot(
            state: state, sessions: states, activities: activities,
            holdReason: nil, holdingSince: nil)
    }

    func testAWorkingSessionThatVanishesIsAnnouncedAsQuiet() {
        var trigger = AnnouncementTrigger()
        _ = trigger.diff(snapshot(state: .working, sessions: [("a", .working)]))

        let gone = trigger.diff(snapshot(state: .armed))
        XCTAssertEqual(gone, [.wentQuiet(session: SessionID("a"), workspace: "acme-api")])

        // And only the once: the session is not coming back to clear itself.
        XCTAssertTrue(trigger.diff(snapshot(state: .armed)).isEmpty)
    }

    func testASessionThatSaidItFinishedIsNotQuiet() {
        var trigger = AnnouncementTrigger()
        _ = trigger.diff(snapshot(state: .working, sessions: [("a", .working)]))
        // Stop arrives, so the session is idle before its TTL evicts it.
        _ = trigger.diff(snapshot(state: .coolingDown, sessions: [("a", .idle)]))

        XCTAssertTrue(
            trigger.diff(snapshot(state: .armed)).isEmpty,
            "an ordinary finish was reported as going quiet")
    }

    func testAParentIsNotQuietWhileASubagentIsStillWorking() {
        var trigger = AnnouncementTrigger()
        _ = trigger.diff(
            tree(
                state: .working,
                sessions: [("parent", .working, nil), ("child", .working, "parent")]))

        // The parent is evicted; the subagent it spawned is still going, so the
        // work has not stopped and there is nothing to report.
        let announcements = trigger.diff(
            tree(state: .working, sessions: [("child", .working, "parent")]))
        XCTAssertTrue(announcements.isEmpty, "a parent with a live subagent was called quiet")
    }

    func testTheFamilyGoingTogetherIsAnnouncedForTheParent() {
        var trigger = AnnouncementTrigger()
        _ = trigger.diff(
            tree(
                state: .working,
                sessions: [("parent", .working, nil), ("child", .working, "parent")]))

        let announcements = trigger.diff(tree(state: .armed, sessions: []))
        XCTAssertTrue(
            announcements.contains(.wentQuiet(session: SessionID("parent"), workspace: "acme-api")),
            "the parent going quiet with its children was not reported")
    }

    func testARunThatDiedIsNotAlsoReportedAsFinished() {
        var trigger = AnnouncementTrigger()
        let start = Date()
        _ = trigger.diff(
            snapshot(state: .working, sessions: [("a", .working)], holdingSince: start),
            now: start)

        let ended = trigger.diff(snapshot(state: .armed), now: start.addingTimeInterval(600))
        XCTAssertTrue(
            ended.contains(.wentQuiet(session: SessionID("a"), workspace: "acme-api")))
        XCTAssertFalse(
            ended.contains { if case .finished = $0 { true } else { false } },
            "a run that died was also announced as finished")
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

        // The session says it stopped before it is evicted, which is what an
        // ordinary finish looks like. Without this the run reads as one that
        // died mid-work, and `wentQuiet` correctly takes the announcement.
        _ = trigger.diff(
            snapshot(state: .working, sessions: [("a", .idle)], holdingSince: start),
            now: start.addingTimeInterval(599)
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
