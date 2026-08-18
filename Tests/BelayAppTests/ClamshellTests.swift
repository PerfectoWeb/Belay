import XCTest

@testable import Belay

/// The rule this pins down is Apple's, not ours: a shut lid sleeps the Mac
/// unless an external display and mains power are both present.
final class ClamshellTests: XCTestCase {
    func testAnOpenLidNeverStandsInTheWay() {
        XCTAssertTrue(Clamshell.holdCanWork(lidClosed: false, externalDisplays: 0, onAC: false))
        XCTAssertTrue(Clamshell.holdCanWork(lidClosed: false, externalDisplays: 2, onAC: true))
    }

    func testAMachineWithNoLidIsNeverInThisSituation() {
        XCTAssertTrue(Clamshell.holdCanWork(lidClosed: nil, externalDisplays: 0, onAC: false))
    }

    func testAShutLidOnBatteryDefeatsAnyHold() {
        XCTAssertFalse(Clamshell.holdCanWork(lidClosed: true, externalDisplays: 0, onAC: false))
        // A display alone is not enough: unplug the power and the Mac sleeps.
        XCTAssertFalse(Clamshell.holdCanWork(lidClosed: true, externalDisplays: 1, onAC: false))
    }

    func testAShutLidSurvivesWithBothHalvesOfTheException() {
        XCTAssertTrue(Clamshell.holdCanWork(lidClosed: true, externalDisplays: 1, onAC: true))
    }

    func testPowerAloneIsNotTheException() {
        XCTAssertFalse(Clamshell.holdCanWork(lidClosed: true, externalDisplays: 0, onAC: true))
    }

    /// Reading the registry must be safe on any Mac, with or without a lid.
    /// The value itself cannot be asserted: it depends on the machine running
    /// the tests, and on a Mac mini the property is absent altogether.
    func testReadingTheLidIsSafeEverywhere() {
        let closed = Clamshell.isClosed()
        XCTAssertTrue(closed == nil || closed == true || closed == false)
    }
}
