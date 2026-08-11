import AppKit
import VigilCore
import XCTest

@testable import Vigil

/// The mode picker, fourth attempt. Three tabs, all visible, one click each —
/// so the rules are simple, and that is the point: the two designs before this
/// needed rules about what "off then on again" restores, and needing a rule was
/// the tell.
@MainActor
final class ModeControlTests: XCTestCase {
    private func picked(_ mode: AwakeMode, from current: AwakeMode) -> AwakeMode? {
        let state = AppState()
        state.mode = current
        var written: AwakeMode?
        state.onModeChange = { written = $0 }
        PanelModePicker(state: state).selectForTesting(mode)
        return written
    }

    func testEveryModeIsOneClickFromEveryOther() {
        for from in AwakeMode.allCases {
            for to in AwakeMode.allCases where to != from {
                XCTAssertEqual(picked(to, from: from), to, "\(to) is not reachable from \(from)")
            }
        }
    }

    /// Re-picking the current mode must not write: every write goes out to the
    /// settings store and makes the coordinator re-evaluate.
    func testPickingTheCurrentModeWritesNothing() {
        for mode in AwakeMode.allCases {
            XCTAssertNil(picked(mode, from: mode), "\(mode) wrote itself back")
        }
    }

    /// The panel mirrors the mode immediately; the snapshot catches up when the
    /// coordinator has re-evaluated. If this stopped happening the tab would not
    /// move until the next tick.
    func testTheSelectionMovesBeforeTheSnapshotDoes() {
        let state = AppState()
        state.mode = .auto
        PanelModePicker(state: state).selectForTesting(.off)
        XCTAssertEqual(state.mode, .off)
    }

    /// Three tabs, three explanations, three symbols — all of them shown, so a
    /// missing one is a blank in the control rather than a crash.
    func testEveryModeIsFullyDescribed() {
        for mode in AwakeMode.allCases {
            XCTAssertFalse(mode.symbolName.isEmpty, "\(mode) has no symbol")
            XCTAssertNotNil(
                NSImage(systemSymbolName: mode.symbolName, accessibilityDescription: nil),
                "\(mode) names a symbol this macOS does not have — the tab would draw blank")
        }
        XCTAssertEqual(Set(AwakeMode.allCases.map(\.symbolName)).count, AwakeMode.allCases.count)
    }
}
