import BelayModules
import SwiftUI
import XCTest

@testable import Belay

/// The sessions the Claude window is not showing. As in `AutoAllowerTests`,
/// the screen is a list and nothing real is pressed.
@MainActor
final class AutoAllowerBehindTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""
    private let screen = FakeScreen()
    private let clock = TestClock()

    override func setUp() async throws {
        suiteName = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeAllower() throws -> AutoAllower {
        let clock = clock
        return AutoAllower(defaults: try XCTUnwrap(defaults), screens: [.claude: screen], patience: 0) {
            clock.now
        }
    }

    private func look(_ allower: AutoAllower) {
        let done = expectation(description: "looked")
        allower.tick { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    private func makeReachingAllower() throws -> AutoAllower {
        let allower = try makeAllower()
        allower.rules.reachesBehind = true
        allower.activate()
        screen.showSession("Belay")
        look(allower)
        return allower
    }

    func testAWaitingSessionIsOpenedAnsweredAndTheWindowPutBack() throws {
        let allower = try makeReachingAllower()
        defer { allower.stop() }
        screen.park([FakeScreen.click(on: "cytron.local")], in: "Cytrongift")

        look(allower)

        XCTAssertEqual(screen.pressed, [FakeScreen.click(on: "cytron.local")])
        XCTAssertEqual(screen.opened, ["Cytrongift", "Belay"])
        XCTAssertEqual(screen.showing, "Belay")
        XCTAssertEqual(allower.log.entries.map(\.subject), ["cytron.local"])
    }

    func testTheSwitchIsOffUntilAsked() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.activate()
        screen.showSession("Belay")
        screen.park([FakeScreen.click(on: "cytron.local")], in: "Cytrongift")

        look(allower)

        XCTAssertTrue(screen.opened.isEmpty)
        XCTAssertTrue(screen.pressed.isEmpty)
    }

    func testTheWindowIsLeftAloneWhileThePersonIsAtWork() throws {
        let allower = try makeReachingAllower()
        defer { allower.stop() }
        screen.park([FakeScreen.click(on: "cytron.local")], in: "Cytrongift")
        screen.use(true)

        look(allower)
        XCTAssertTrue(screen.opened.isEmpty)

        screen.use(false)
        look(allower)
        XCTAssertEqual(screen.pressed.count, 1)
    }

    /// What waits for the person is looked at once and then left: the
    /// window must not flip to it on every look.
    func testASessionWithNothingForBelayIsOpenedOnce() throws {
        let allower = try makeReachingAllower()
        defer { allower.stop() }
        screen.park([FakeScreen.command("rm -rf build")], in: "Cytrongift")

        look(allower)
        look(allower)
        look(allower)

        XCTAssertTrue(screen.pressed.isEmpty)
        XCTAssertEqual(screen.opened, ["Cytrongift", "Belay"])
        XCTAssertEqual(screen.showing, "Belay")
    }

    /// Found live: a session left alone once stayed left alone, because it
    /// moved on while the person was typing in Claude and nobody was looking
    /// at the list. Its next request then waited until a human opened it.
    func testASessionThatMovedOnWhileThePersonWorkedIsOpenedAgain() throws {
        let allower = try makeReachingAllower()
        defer { allower.stop() }
        screen.park([FakeScreen.command("rm -rf build")], in: "Cytrongift")
        look(allower)
        XCTAssertEqual(screen.opened, ["Cytrongift", "Belay"])

        screen.use(true)
        screen.park([], in: "Cytrongift")
        look(allower)
        screen.park([FakeScreen.click(on: "cytron.local")], in: "Cytrongift")
        look(allower)
        XCTAssertEqual(screen.opened, ["Cytrongift", "Belay"], "opened under the person's hands")

        screen.use(false)
        look(allower)

        XCTAssertEqual(screen.pressed, [FakeScreen.click(on: "cytron.local")])
        XCTAssertEqual(screen.opened, ["Cytrongift", "Belay", "Cytrongift", "Belay"])
    }

    /// Found live: a session that had just stopped was opened for nothing.
    /// While the hooks see no tool call under way, nothing can be asking.
    func testNoVisitWhileNoToolCallIsUnderWay() throws {
        let allower = try makeReachingAllower()
        defer { allower.stop() }
        var asking = false
        allower.mayHaveRequest = { _ in asking }
        screen.park([FakeScreen.click(on: "cytron.local")], in: "Cytrongift")

        look(allower)
        XCTAssertTrue(screen.opened.isEmpty)

        asking = true
        look(allower)
        XCTAssertEqual(screen.pressed, [FakeScreen.click(on: "cytron.local")])
        XCTAssertEqual(screen.opened, ["Cytrongift", "Belay"])
    }

    /// The window on show is answered whatever the hooks say.
    func testTheShownSessionIsAnsweredWithoutAToolCall() throws {
        let allower = try makeReachingAllower()
        defer { allower.stop() }
        allower.mayHaveRequest = { _ in false }
        screen.show(FakeScreen.access(to: "cytron.local"))

        look(allower)

        XCTAssertEqual(screen.pressed, [FakeScreen.access(to: "cytron.local")])
    }

    func testTheSessionInTheWindowComesFirst() throws {
        let allower = try makeReachingAllower()
        defer { allower.stop() }
        screen.show(FakeScreen.access(to: "cytron.local"))
        screen.park([FakeScreen.click(on: "cytron.local")], in: "Cytrongift")

        look(allower)

        XCTAssertEqual(screen.pressed, [FakeScreen.access(to: "cytron.local")])
        XCTAssertTrue(screen.opened.isEmpty)
    }

    func testARowThatWillNotOpenIsNotTriedAgain() throws {
        let allower = try makeReachingAllower()
        defer { allower.stop() }
        screen.park([FakeScreen.click(on: "cytron.local")], in: "Cytrongift")
        screen.jamRow("Cytrongift")

        look(allower)
        look(allower)

        XCTAssertTrue(screen.pressed.isEmpty)
        XCTAssertEqual(screen.opened, ["Cytrongift", "Belay"])
    }

    /// The box in the settings writes through a binding, not by assignment.
    func testTickingTheBoxIsKept() throws {
        let allower = try makeAllower()
        @Bindable var bound = allower

        $bound.rules.reachesBehind.wrappedValue = true

        XCTAssertTrue(allower.rules.reachesBehind)
        XCTAssertTrue(AutoAllowRules.load(from: try XCTUnwrap(defaults)).reachesBehind)
        let again = try makeAllower()
        XCTAssertTrue(again.rules.reachesBehind)
    }
}
