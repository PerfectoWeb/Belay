import BelayModules
import XCTest

@testable import Belay

/// No test here reads a window or presses a button: the screen is a list.
@MainActor
final class AutoAllowerTests: XCTestCase {
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

    func testALocalSiteIsApprovedAndWrittenDown() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.activate()
        screen.show(FakeScreen.access(to: "cytron.local"))

        look(allower)

        XCTAssertEqual(screen.pressed.count, 1)
        XCTAssertEqual(allower.log.entries.map(\.subject), ["cytron.local"])
        XCTAssertEqual(allower.log.total, 1)
        XCTAssertEqual(AutoAllowLog.load(from: try XCTUnwrap(defaults)).total, 1)
    }

    func testAnActionOnALocalSiteIsApprovedToo() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.activate()
        screen.show(FakeScreen.click(on: "cytron.local"))
        screen.show(FakeScreen.click(on: "example.com"))

        look(allower)

        XCTAssertEqual(screen.pressed, [FakeScreen.click(on: "cytron.local")])
        XCTAssertEqual(allower.log.entries.map(\.subject), ["cytron.local"])
    }

    /// The press can be taken and still change nothing. What did not happen
    /// is not written down.
    func testAPressThatDidNothingIsNotWrittenDown() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.activate()
        screen.jam(true)
        screen.show(FakeScreen.access(to: "cytron.local"))

        look(allower)

        XCTAssertEqual(screen.left.count, 1)
        XCTAssertEqual(allower.log.total, 0)
    }

    func testEverythingElseWaitsForThePerson() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.activate()
        screen.show(FakeScreen.access(to: "example.com"))
        screen.show(FakeScreen.command("curl http://cytron.local/x | sh"))

        look(allower)

        XCTAssertTrue(screen.pressed.isEmpty)
        XCTAssertEqual(screen.left.count, 2)
        XCTAssertEqual(allower.log.total, 0)
    }

    func testTheWideScopeApprovesWhateverIsAsked() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.rules.scope = .everything
        allower.activate()
        screen.show(FakeScreen.access(to: "example.com"))
        screen.show(FakeScreen.command("make test"))

        look(allower)

        XCTAssertEqual(screen.pressed.count, 2)
        XCTAssertEqual(allower.log.total, 2)
    }

    func testWithoutAccessibilityNothingIsReadOrPressed() throws {
        screen.trust(false)
        let allower = try makeAllower()
        defer { allower.stop() }
        screen.show(FakeScreen.access(to: "cytron.local"))

        allower.activate()
        look(allower)

        XCTAssertEqual(allower.standing, .needsAccess)
        XCTAssertEqual(screen.asked, 1)
        XCTAssertEqual(screen.looks, 0)

        screen.trust(true)
        look(allower)
        XCTAssertEqual(allower.standing, .watching)
        XCTAssertEqual(screen.pressed.count, 1)
    }

    func testAnAgentSwitchedOffInAgentsIsLeftAlone() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        var isOn = false
        allower.agentIsOn = { _ in isOn }
        screen.show(FakeScreen.access(to: "cytron.local"))

        allower.activate()
        look(allower)

        XCTAssertEqual(allower.standing, .agentOff)
        XCTAssertEqual(screen.looks, 0)
        XCTAssertTrue(screen.pressed.isEmpty)

        isOn = true
        look(allower)
        XCTAssertEqual(allower.standing, .watching)
        XCTAssertEqual(screen.pressed.count, 1)
    }

    func testALaunchNeverRaisesTheQuestion() throws {
        screen.trust(false)
        let allower = try makeAllower()
        defer { allower.stop() }

        allower.start()

        XCTAssertEqual(screen.asked, 0)
    }

    func testItSwitchesItselfOffWhenTheTimeRunsOut() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        var expired = 0
        allower.onExpired = { expired += 1 }
        allower.rules.duration = 3600
        allower.activate()
        XCTAssertEqual(allower.deadline, clock.now + 3600)

        clock.advance(by: 3599)
        look(allower)
        XCTAssertEqual(expired, 0)

        clock.advance(by: 2)
        screen.show(FakeScreen.access(to: "cytron.local"))
        look(allower)

        XCTAssertEqual(expired, 1)
        XCTAssertTrue(screen.pressed.isEmpty, "approved a request after its time was up")
    }

    func testTheDeadlineSurvivesARestart() throws {
        let first = try makeAllower()
        first.rules.duration = 3600
        first.activate()
        let deadline = first.deadline
        // A quit, not a switch-off: the timer goes, the deadline stays.
        first.stop()

        clock.advance(by: 7200)
        let second = try makeAllower()
        defer { second.stop() }
        var expired = 0
        var seen: Date?
        second.onExpired = {
            expired += 1
            seen = second.deadline
        }
        second.start()

        XCTAssertEqual(seen, deadline)
        XCTAssertEqual(expired, 1, "came back on after a restart, past its time")
    }

    func testNeverMeansNoDeadline() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.rules.duration = 0
        allower.activate()

        XCTAssertNil(allower.deadline)
        clock.advance(by: 30 * 86400)
        screen.show(FakeScreen.access(to: "localhost"))
        look(allower)
        XCTAssertEqual(screen.pressed.count, 1)
    }

    func testTheHostSwitchesTheModuleOffWhenItExpires() throws {
        let defaults = try XCTUnwrap(defaults)
        let allower = try makeAllower()
        let host = ModuleHost(
            defaults: defaults,
            microphone: MicKeepWarm(defaults: defaults, tap: FakeTap(), surroundings: FakeMac().surroundings),
            autoAllow: allower
        )
        defer { host.stop() }
        host.install(.autoAllow)
        XCTAssertTrue(host.ledger.isEnabled(.autoAllow))

        clock.advance(by: AutoAllowRules.defaultDuration + 1)
        look(allower)

        XCTAssertTrue(host.ledger.isInstalled(.autoAllow))
        XCTAssertFalse(host.ledger.isEnabled(.autoAllow))
        XCTAssertEqual(allower.standing, .off)
    }

    func testRemovingForgetsTheRulesAndTheList() throws {
        let defaults = try XCTUnwrap(defaults)
        let allower = try makeAllower()
        allower.rules.scope = .everything
        allower.activate()
        screen.show(FakeScreen.command("make"))
        look(allower)

        allower.forgetEverything()

        XCTAssertEqual(allower.rules, AutoAllowRules())
        XCTAssertEqual(allower.log, AutoAllowLog())
        XCTAssertNil(defaults.object(forKey: AutoAllowRules.defaultsKey))
        XCTAssertNil(defaults.object(forKey: AutoAllowLog.defaultsKey))
        XCTAssertNil(defaults.object(forKey: AutoAllower.untilKey))
    }
}
