import SwiftUI
import VigilCore
import XCTest

@testable import Vigil

/// The panel headline is derived from the same `VigilState` that decides whether
/// an IOKit assertion exists. These tests exist to keep those two from ever
/// disagreeing — a panel saying "keeping your Mac awake" while nothing is held
/// is the bug that destroys trust in the whole product.
final class PanelStatusTests: XCTestCase {
    private let everyState: [VigilState] = [
        .off,
        .alwaysOn,
        .armed,
        .working,
        .awaitingUser,
        .coolingDown,
        .suspended(.batteryLow(charge: 0.1)),
        .suspended(.maxDurationReached(3600))
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
        let pairs: [(VigilState, PanelStatus)] = [
            (.alwaysOn, .alwaysOn), (.working, .working), (.armed, .armed), (.off, .off),
            (.awaitingUser, .awaitingUser)
        ]
        for (state, status) in pairs {
            XCTAssertEqual(VigilGlyph.Look(state: state), status.look, "\(state)")
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
        // Assignments are split between the app's composition root and the
        // controller, so both are searched rather than assuming which.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VigilApp")
        let wiring = try ["VigilApp.swift", "VigilController.swift"]
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined()

        for callback in ["onModeChange", "onOpenSettings", "onGrantAccess", "onChange"] {
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
    private func height(_ state: VigilState) -> CGFloat {
        let app = AppState()
        app.apply(
            CoordinatorSnapshot(
                state: state, sessions: [], activities: [:], holdReason: nil, holdingSince: nil),
            totalAwake: 0)
        let host = NSHostingView(rootView: PanelView(state: app).frame(width: PanelView.width))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    func testEveryStateGivesThePanelTheSameHeight() {
        let states: [VigilState] = [
            .off, .armed, .alwaysOn, .working, .awaitingUser, .coolingDown,
            .suspended(.batteryLow(charge: 0.18)), .suspended(.maxDurationReached(4 * 3600))
        ]
        let heights = states.map(height)
        let spread = (heights.max() ?? 0) - (heights.min() ?? 0)
        XCTAssertLessThan(
            spread, 1,
            "the panel changes height between states by \(spread) pt — it will jump as you switch mode")
    }
}
