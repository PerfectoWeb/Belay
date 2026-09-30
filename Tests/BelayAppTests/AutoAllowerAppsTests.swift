import BelayModules
import XCTest

@testable import Belay

/// Two apps side by side. As in `AutoAllowerTests`, each screen is a list.
@MainActor
final class AutoAllowerAppsTests: XCTestCase {
    private var defaults: UserDefaults?
    private var suiteName = ""
    private let claude = FakeScreen()
    private let codex = FakeScreen()

    override func setUp() async throws {
        suiteName = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func makeAllower() throws -> AutoAllower {
        AutoAllower(
            defaults: try XCTUnwrap(defaults), screens: [.claude: claude, .codex: codex], patience: 0)
    }

    private func look(_ allower: AutoAllower) {
        let done = expectation(description: "looked")
        allower.tick { done.fulfill() }
        wait(for: [done], timeout: 5)
    }

    func testEveryAppIsAnsweredByTheSameRules() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.activate()
        claude.show(FakeScreen.access(to: "cytron.local"))
        codex.show(FakeScreen.access(to: "shop.test"))
        codex.show(FakeScreen.access(to: "example.com"))

        look(allower)

        XCTAssertEqual(claude.pressed.count, 1)
        XCTAssertEqual(codex.pressed, [FakeScreen.access(to: "shop.test")])
        XCTAssertEqual(Set(allower.log.entries.map(\.subject)), ["cytron.local", "shop.test"])
    }

    func testAnAppWhoseAgentIsOffIsLeftAloneAndTheOtherCarriesOn() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.agentIsOn = { $0 == .claude }
        allower.activate()
        claude.show(FakeScreen.access(to: "cytron.local"))
        codex.show(FakeScreen.access(to: "cytron.local"))

        look(allower)

        XCTAssertEqual(allower.standing, .watching)
        XCTAssertEqual(allower.appsLeftAlone, [.codex])
        XCTAssertEqual(claude.pressed.count, 1)
        XCTAssertEqual(codex.looks, 0)
    }

    func testWithEveryAgentOffNothingIsLookedAt() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.agentIsOn = { _ in false }
        allower.activate()
        claude.show(FakeScreen.access(to: "cytron.local"))
        codex.show(FakeScreen.access(to: "cytron.local"))

        look(allower)

        XCTAssertEqual(allower.standing, .agentOff)
        XCTAssertEqual(allower.appsLeftAlone, [.claude, .codex])
        XCTAssertEqual(claude.looks + codex.looks, 0)
    }

    /// A session one app declined says nothing about a session of the same
    /// name in the other.
    func testEachAppKeepsItsOwnSessions() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.rules.reachesBehind = true
        allower.activate()
        claude.showSession("Belay")
        codex.showSession("Belay")
        // The look that switching on starts is over before anything waits.
        look(allower)
        claude.park([FakeScreen.access(to: "example.com")], in: "Cytrongift")
        codex.park([FakeScreen.access(to: "cytron.local")], in: "Cytrongift")

        look(allower)

        XCTAssertTrue(claude.pressed.isEmpty)
        XCTAssertEqual(codex.pressed, [FakeScreen.access(to: "cytron.local")])
        XCTAssertEqual(claude.showing, "Belay")
        XCTAssertEqual(codex.showing, "Belay")
    }

    func testSomebodyAtWorkInOneAppHoldsBackTheVisitsInBoth() throws {
        let allower = try makeAllower()
        defer { allower.stop() }
        allower.rules.reachesBehind = true
        allower.activate()
        claude.showSession("Belay")
        codex.showSession("Belay")
        // The look that switching on starts is over before anything waits.
        look(allower)
        codex.park([FakeScreen.access(to: "cytron.local")], in: "Cytrongift")
        claude.use(true)

        look(allower)

        XCTAssertTrue(codex.opened.isEmpty)
        XCTAssertTrue(codex.pressed.isEmpty)
    }
}
