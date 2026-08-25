import BelayCore
import SwiftUI
import XCTest

@testable import Belay

/// The panel headline is derived from the same `BelayState` that decides whether
/// an IOKit assertion exists. These tests exist to keep those two from ever
/// disagreeing — a panel saying "keeping your Mac awake" while nothing is held
/// is the bug that destroys trust in the whole product.
final class PanelStatusTests: XCTestCase {
    private let everyState: [BelayState] = [
        .off,
        .alwaysOn,
        .armed,
        .working,
        .awaitingUser,
        .coolingDown,
        .suspended(.batteryLow(charge: 0.1)),
        .suspended(.maxDurationReached(3600)),
        .suspended(.timerEnded(900))
    ]

    func testHoldingAgreesWithTheAssertionForEveryState() {
        for state in everyState {
            XCTAssertEqual(
                PanelStatus.derive(from: state).isHolding,
                state.holdsAssertion,
                "panel and assertion disagree for \(state)"
            )
        }
    }

    func testOnlySuspendedStatesReadAsInterrupted() {
        for state in everyState {
            let expected: Bool
            if case .suspended = state { expected = true } else { expected = false }
            XCTAssertEqual(PanelStatus.derive(from: state).isInterrupted, expected, "\(state)")
        }
    }

    /// An off-by-100 here renders "battery is at 0%" during normal use, so it is
    /// worth pinning: the coordinator carries a 0…1 fraction, the UI shows percent.
    func testBatteryChargeBecomesARoundedPercentage() {
        guard case .batteryLow(let percent) = PanelStatus.derive(from: .suspended(.batteryLow(charge: 0.184)))
        else {
            return XCTFail("expected a batteryLow status")
        }
        XCTAssertEqual(percent, 18)
    }

    func testMaxDurationSuspensionIsRecognised() {
        guard case .maxDurationReached = PanelStatus.derive(from: .suspended(.maxDurationReached(7200)))
        else {
            return XCTFail("expected a maxDurationReached status")
        }
    }

    /// A running timer changes the sentence, and only the sentence: the same
    /// Always-on look must keep holding.
    func testTimerVariantsOfAlwaysOn() {
        let timer = AlwaysOnTimer(duration: 900, deadline: Date().addingTimeInterval(900))
        XCTAssertEqual(PanelStatus.derive(from: .alwaysOn, timer: timer), .alwaysOnTimed)
        XCTAssertEqual(PanelStatus.derive(from: .alwaysOn, timer: nil), .alwaysOn)
        XCTAssertTrue(PanelStatus.alwaysOnTimed.isHolding)
        XCTAssertEqual(PanelStatus.derive(from: .suspended(.timerEnded(900))), .timerEnded)
        XCTAssertTrue(PanelStatus.timerEnded.isInterrupted)
    }
}

/// Switching between Auto and Always on changed nothing on screen, which reads
/// as the click not having registered.
@MainActor
final class ModeLookTests: XCTestCase {
    func testAlwaysOnLooksDifferentFromWorking() {
        XCTAssertNotEqual(PanelStatus.alwaysOn.look, PanelStatus.working.look)
    }

    func testEveryHoldingStateIsDistinguishable() {
        let looks = [PanelStatus.alwaysOn, .working, .armed, .off, .awaitingUser].map(\.look)
        XCTAssertEqual(Set(looks).count, looks.count, "two states share a mark")
    }

    /// The panel and the menu bar must never disagree about what is happening.
    func testThePanelAgreesWithTheMenuBar() {
        let pairs: [(BelayState, PanelStatus)] = [
            (.alwaysOn, .alwaysOn), (.working, .working), (.armed, .armed), (.off, .off),
            (.awaitingUser, .awaitingUser)
        ]
        for (state, status) in pairs {
            XCTAssertEqual(BelayGlyph.Look(state: state), status.look, "\(state)")
        }
    }
}

/// A button that is labelled, focusable and accessible, and calls a closure
/// nobody assigned, is indistinguishable from a working one until it is pressed.
/// `AppState`'s callbacks all default to no-ops, so this is the shape of bug
/// that will happen again.
@MainActor
final class AppStateCallbackTests: XCTestCase {
    func testEveryCallbackTheUIOffersIsWiredByTheApp() throws {
        // Assignments are split between the app's composition root, the
        // controller and `AppState.connect` — which exists so the window and the
        // panel can be captured weakly in one place — so all three are searched
        // rather than assuming which.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BelayApp")
        let wiring = try [
            "BelayApp.swift", "BelayController.swift", "BelayControllerProviders.swift",
            "AppState.swift"
        ]
        .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
        .joined()

        for callback in [
            "onModeChange", "onOpenSettings", "onGrantAccess", "onChange",
            "onTimerChange", "onHoldAgain", "onToggleProvider",
            "onAddProviderRoot", "onRemoveProviderRoot", "onAddSuggestedRoot"
        ] {
            XCTAssertTrue(
                wiring.contains("\(callback) ="),
                "AppState.\(callback) is never assigned — whatever calls it does nothing")
        }
    }
}

/// Switching modes rewrites the status sentence. If the block it sits in can
/// change height, the whole panel jumps under the cursor mid-click.
@MainActor
final class PanelHeightStabilityTests: XCTestCase {
    private func height(
        _ state: BelayState, mode: AwakeMode = .auto, timer: AlwaysOnTimer? = nil
    ) -> CGFloat {
        let app = AppState()
        app.mode = mode
        app.apply(
            CoordinatorSnapshot(
                state: state, sessions: [], activities: [:], holdReason: nil, holdingSince: nil,
                timer: timer),
            totalAwake: 0)
        let host = NSHostingView(rootView: PanelView(state: app).frame(width: PanelView.width))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testEveryStateGivesThePanelTheSameHeight() {
        // The battery pause belongs here: it offers no button, so it adds no
        // row and the panel holds one height through it.
        let states: [BelayState] = [
            .off, .armed, .alwaysOn, .working, .awaitingUser, .coolingDown,
            .suspended(.batteryLow(charge: 0.18))
        ]
        let heights = states.map { height($0) }
        let spread = (heights.max() ?? 0) - (heights.min() ?? 0)
        XCTAssertLessThan(
            spread, 1,
            "the panel changes height between states by \(spread) pt — it will jump as you switch mode")
    }

    /// The pause row is the one deliberate exception to the rule above. It
    /// appears under the mode picker — below every control the cursor could be
    /// on, so nothing the user is about to click moves — and both pauses that
    /// carry the button must land on the same height, so one becoming the
    /// other cannot jump either.
    func testTheTwoActionablePausesShareOneHeight() {
        let base = height(.armed)
        let cap = height(.suspended(.maxDurationReached(4 * 3600)))
        let timer = height(.suspended(.timerEnded(900)))
        XCTAssertEqual(cap, timer, accuracy: 0.5, "the two pause rows must not differ")
        XCTAssertGreaterThan(cap, base, "the pause row should actually be there")
    }

    /// In Always on the slot is always filled — the duration chip when holding,
    /// the pause row when a bound fired — so within the mode the panel never
    /// changes height at all, countdown or not.
    func testAlwaysOnKeepsOneHeightThroughChipAndPause() {
        let deadline = AlwaysOnTimer(duration: 900, deadline: Date().addingTimeInterval(900))
        let chip = height(.alwaysOn, mode: .alwaysOn)
        let counting = height(.alwaysOn, mode: .alwaysOn, timer: deadline)
        let paused = height(.suspended(.timerEnded(900)), mode: .alwaysOn)
        XCTAssertEqual(chip, counting, accuracy: 0.5, "the countdown must not resize the chip")
        XCTAssertEqual(chip, paused, accuracy: 0.5, "chip and pause must share the slot's height")
    }
}
