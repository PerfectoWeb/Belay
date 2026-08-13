import XCTest

@testable import Belay

/// The migration that runs once, at launch, against the user's real
/// preferences. Untested it would have been the riskiest thing shipped today:
/// its first version copied every global default macOS had registered into
/// Belay's own domain, and that was found by reading a plist rather than by a
/// failing test.
final class PreviousDomainTests: XCTestCase {
    private var suiteName = ""
    private var destination: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        destination = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        destination.removePersistentDomain(forName: suiteName)
        UserDefaults.standard.removePersistentDomain(forName: PreviousDomain.identifier)
        super.tearDown()
    }

    private func seedPreviousDomain(_ values: [String: Any]) {
        UserDefaults.standard.setPersistentDomain(values, forName: PreviousDomain.identifier)
    }

    func testItCarriesTheOldSettingsAcross() {
        seedPreviousDomain(["mode": "alwaysOn", "gracePeriod": 120, "schemaVersion": 2])

        PreviousDomain.adopt(into: destination)

        XCTAssertEqual(destination.string(forKey: "mode"), "alwaysOn")
        XCTAssertEqual(destination.integer(forKey: "gracePeriod"), 120)
    }

    /// The old domain is left alone, so going back to 1.0.0 still finds it.
    func testItCopiesRatherThanMoves() {
        seedPreviousDomain(["mode": "alwaysOn"])

        PreviousDomain.adopt(into: destination)

        let previous = UserDefaults.standard.persistentDomain(forName: PreviousDomain.identifier)
        XCTAssertEqual(previous?["mode"] as? String, "alwaysOn")
    }

    func testItRunsOnlyOnce() {
        seedPreviousDomain(["mode": "alwaysOn"])
        PreviousDomain.adopt(into: destination)

        // Someone who then sets the mode back is not overruled at the next launch.
        destination.set("off", forKey: "mode")
        PreviousDomain.adopt(into: destination)

        XCTAssertEqual(destination.string(forKey: "mode"), "off")
    }

    /// A user who already has settings here is not a user who needs migrating.
    func testItLeavesAnAlreadyConfiguredInstallAlone() {
        seedPreviousDomain(["mode": "alwaysOn"])
        destination.set("off", forKey: "mode")

        PreviousDomain.adopt(into: destination)

        XCTAssertEqual(destination.string(forKey: "mode"), "off")
    }

    /// The first version of this used `dictionaryRepresentation()`, which
    /// resolves the whole hierarchy, and dragged other people's global defaults
    /// into Belay's domain.
    func testItDoesNotDragInGlobalDefaults() {
        seedPreviousDomain(["mode": "alwaysOn"])

        PreviousDomain.adopt(into: destination)

        let carried = destination.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertNil(carried["AppleLanguages"], "a global default was copied")
        XCTAssertLessThanOrEqual(
            carried.count, 3, "expected the seeded keys and the done marker, got \(carried.keys)")
    }
}
