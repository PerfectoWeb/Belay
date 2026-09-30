import BelayModules
import XCTest

@testable import Belay

/// No test here opens a microphone: the tap is a counter and the Mac around
/// it is a set of switches.
@MainActor
final class MicKeepWarmTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""
    private let tap = FakeTap()
    private let mac = FakeMac()

    override func setUp() async throws {
        suiteName = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeKeeper() throws -> MicKeepWarm {
        MicKeepWarm(
            defaults: try XCTUnwrap(defaults), tap: tap, surroundings: mac.surroundings,
            settle: .milliseconds(20))
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

    func testSwitchingOnHoldsTheMicrophone() async throws {
        let keeper = try makeKeeper()
        keeper.activate()

        await eventually("never warmed up") { keeper.warmth == .warm }
        XCTAssertEqual(keeper.microphone, "Test Microphone")
        XCTAssertEqual(tap.opens, 1)
        XCTAssertEqual(mac.asked, 0, "asked for a permission it already had")
    }

    func testTheQuestionIsAskedOnlyWhenTheUserSwitchesItOn() async throws {
        mac.permission = .undecided
        let keeper = try makeKeeper()

        keeper.start()
        XCTAssertEqual(mac.asked, 0, "a launch must never raise the question")
        XCTAssertEqual(keeper.warmth, .needsPermission)
        keeper.stop()

        keeper.activate()
        XCTAssertEqual(mac.asked, 1)
        await eventually("granted, and still cold") { keeper.warmth == .warm }
    }

    func testARefusalLeavesTheMicrophoneAlone() async throws {
        mac.permission = .undecided
        mac.answer = false
        let keeper = try makeKeeper()

        keeper.activate()

        XCTAssertEqual(keeper.warmth, .needsPermission)
        XCTAssertEqual(tap.opens, 0)
    }

    func testTheBatteryPausesItWhenAskedTo() async throws {
        let keeper = try makeKeeper()
        keeper.rules.pausesOnBattery = true
        keeper.activate()
        await eventually("never warmed up") { keeper.warmth == .warm }

        mac.isOnBattery = true
        mac.change()
        XCTAssertEqual(keeper.warmth, .pausedOnBattery)
        XCTAssertEqual(tap.closes, 1)
        XCTAssertNil(keeper.microphone)

        mac.isOnBattery = false
        mac.change()
        await eventually("back on power, and still cold") { keeper.warmth == .warm }
        XCTAssertEqual(tap.opens, 2)
    }

    func testABluetoothMicrophoneIsLetGoAndTheNextOnePickedUp() async throws {
        let keeper = try makeKeeper()
        keeper.activate()
        await eventually("never warmed up") { keeper.warmth == .warm }

        mac.input = .bluetooth
        mac.change()
        XCTAssertEqual(keeper.warmth, .pausedForBluetooth)
        XCTAssertEqual(tap.closes, 1)
        XCTAssertNil(keeper.microphone)

        mac.input = .builtIn
        mac.change()
        await eventually("headphones gone, and still cold") { keeper.warmth == .warm }
        XCTAssertEqual(tap.opens, 2)
    }

    func testABluetoothMicrophoneIsHeldWhenAskedTo() async throws {
        mac.input = .bluetooth
        let keeper = try makeKeeper()
        keeper.activate()
        XCTAssertEqual(keeper.warmth, .pausedForBluetooth)
        XCTAssertEqual(tap.opens, 0)

        keeper.rules.leavesBluetoothAlone = false
        await eventually("asked to hold it, and still cold") { keeper.warmth == .warm }
    }

    func testSwitchingOffLetsGoAndStopsWatching() async throws {
        let keeper = try makeKeeper()
        keeper.activate()
        await eventually("never warmed up") { keeper.warmth == .warm }

        keeper.stop()

        XCTAssertEqual(keeper.warmth, .off)
        XCTAssertEqual(tap.closes, 1)
        XCTAssertEqual(mac.watching, 0)
    }

    func testAChangeOfMicrophoneReopensOnceThingsSettle() async throws {
        let keeper = try makeKeeper()
        keeper.activate()
        await eventually("never warmed up") { keeper.warmth == .warm }

        tap.plug("Headset")
        tap.disturb()
        tap.disturb()
        tap.disturb()

        await eventually("kept the old microphone") { keeper.microphone == "Headset" }
        XCTAssertEqual(tap.opens, 2, "three announcements of one change, one reopening")
    }

    func testAMacWithNoMicrophoneSaysSoAndRecovers() async throws {
        tap.plug(nil)
        let keeper = try makeKeeper()
        keeper.activate()
        await eventually("claimed a microphone") { keeper.warmth == .noMicrophone }

        tap.plug("USB Microphone")
        tap.disturb()
        await eventually("missed the new microphone") { keeper.warmth == .warm }
    }

    func testRemovingForgetsTheRules() throws {
        let defaults = try XCTUnwrap(defaults)
        let keeper = try makeKeeper()
        keeper.rules.pausesOnBattery = true
        XCTAssertNotNil(defaults.data(forKey: MicRules.defaultsKey))

        keeper.forgetEverything()

        XCTAssertNil(defaults.object(forKey: MicRules.defaultsKey))
        XCTAssertEqual(keeper.rules, MicRules())
    }
}
