import AppKit
import BelayChannel
import XCTest

@testable import Belay

/// The rule that decides who sees the release notes.
///
/// Every case here is one somebody would meet on a real Mac, and the expensive
/// mistakes are the two quiet ones: announcing a version to somebody who has
/// been running it for months, and announcing nothing to somebody who just
/// updated.
final class WhatsNewDecisionTests: XCTestCase {
    private let notes = [
        ReleaseNote(version: "1.2.0", items: [.init(symbol: "gift", title: "a", body: "b")]),
        ReleaseNote(version: "1.1.0", items: [.init(symbol: "bell", title: "c", body: "d")])
    ]

    private func outcome(_ current: String, _ lastSeen: String?, onboarded: Bool = true)
        -> WhatsNewDecision.Outcome
    {
        WhatsNewDecision.outcome(
            current: current, lastSeen: lastSeen, onboarded: onboarded, catalogue: notes)
    }

    func testAFirstLaunchBelongsToTheWelcomeScreen() {
        XCTAssertEqual(outcome("1.2.0", nil, onboarded: false), .nothing)
        XCTAssertEqual(outcome("1.2.0", "1.1.0", onboarded: false), .nothing)
    }

    /// The one that would embarrass the app. Everybody running 1.1.0 has no such
    /// key, and reading that as "new" tells all of them about a version they may
    /// have had for months.
    func testAnInstallFromBeforeTheKeyIsRecordedAndNotToldAnything() {
        XCTAssertEqual(outcome("1.2.0", nil), .recordOnly("1.2.0"))
    }

    func testTheSameVersionIsNotAnnouncedTwice() {
        XCTAssertEqual(outcome("1.2.0", "1.2.0"), .nothing)
        // Trailing zeros are the same version, not an update.
        XCTAssertEqual(outcome("1.2.0", "1.2"), .nothing)
    }

    /// String comparison says "1.10.0" < "1.9.0". This is the test that earns
    /// `AppVersion`.
    func testATwoDigitVersionIsNewerThanASingleDigitOne() {
        let big = [ReleaseNote(version: "1.10.0", items: notes[0].items)]
        XCTAssertEqual(
            WhatsNewDecision.outcome(
                current: "1.10.0", lastSeen: "1.9.0", onboarded: true, catalogue: big),
            .show(notes: big, record: "1.10.0"))
    }

    /// The window announces the update that just happened and nothing else.
    /// Whatever was skipped on the way lives in the changelog, not on screen.
    func testAnUpdateShowsTheInstalledVersionOnly() {
        XCTAssertEqual(outcome("1.2.0", "1.0.0"), .show(notes: [notes[0]], record: "1.2.0"))
        XCTAssertEqual(outcome("1.2.0", "1.1.0"), .show(notes: [notes[0]], record: "1.2.0"))
    }

    /// Notes committed for a version this build does not have yet must not
    /// escape the repository into somebody's window.
    func testNotesForAVersionNewerThanThisBuildAreNotShown() {
        XCTAssertEqual(outcome("1.1.0", "1.0.0"), .show(notes: [notes[1]], record: "1.1.0"))
    }

    /// A hotfix with nothing written for it. Recorded, so the next real release
    /// is still detected, and silent, so nobody is shown an empty window.
    func testAVersionWithNoNotesIsRecordedSilently() {
        XCTAssertEqual(outcome("1.3.0", "1.2.0"), .recordOnly("1.3.0"))
    }

    /// Going back a version. Nothing to announce, and the stored number has to
    /// come down or the way back up would announce nothing either.
    func testADowngradeRecordsWithoutShowing() {
        XCTAssertEqual(outcome("1.1.0", "1.2.0"), .recordOnly("1.1.0"))
    }

    func testAVersionThatIsNotAVersionDecidesNothing() {
        XCTAssertEqual(outcome("not.a.version", "1.1.0"), .nothing)
        // An unreadable stored value is treated as no value: recorded, silent.
        XCTAssertEqual(outcome("1.2.0", "banana"), .recordOnly("1.2.0"))
    }

    /// Five versions skipped, one window: only the newest is on screen, so the
    /// window cannot outgrow the screen however long somebody waited.
    func testSkippedVersionsStayInTheChangelog() {
        let many = (1...5).map { index in
            ReleaseNote(
                version: "1.\(index).0",
                items: (1...3).map { .init(symbol: "gift\($0)", title: "t", body: "b") })
        }.reversed()

        guard
            case .show(let shown, _) = WhatsNewDecision.outcome(
                current: "1.5.0", lastSeen: "1.0.0", onboarded: true, catalogue: Array(many))
        else { return XCTFail("expected notes") }

        XCTAssertEqual(shown.map(\.version), ["1.5.0"])
    }
}

final class ReleaseNotesTests: XCTestCase {
    /// A symbol name that does not resolve draws nothing at all, which leaves a
    /// hole in the row where the icon should be and no error anywhere.
    func testEverySymbolExists() {
        for note in ReleaseNotes.all {
            for item in note.items {
                XCTAssertNotNil(
                    NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil),
                    "\(note.version) names a symbol that does not exist: \(item.symbol)")
            }
        }
    }

    /// The notes are keyed by version and the versions have to be readable, or
    /// the entry silently never matches anything.
    func testEveryVersionParses() {
        for note in ReleaseNotes.all {
            XCTAssertNotNil(AppVersion(note.version), "\(note.version) is not a version")
        }
    }

    /// Newest first, because the window shows them in the order they are given
    /// and the hero takes its version from the first.
    func testTheNewestVersionIsFirst() {
        let versions = ReleaseNotes.all.compactMap { AppVersion($0.version) }
        XCTAssertEqual(versions, versions.sorted(by: >))
    }

    /// This build has to be able to say something about itself, or the feature
    /// ships switched off: a release with no entry announces nothing.
    func testThisBuildHasNotes() {
        XCTAssertTrue(
            ReleaseNotes.all.contains { $0.version == Branding.version },
            "no release notes written for \(Branding.version)")
    }

    /// Nothing may promise what this build cannot do. `Update Now` and Homebrew
    /// are direct-channel facts, and the App Store build has neither an updater
    /// nor anything to say about a package manager. Same rule that took Precise
    /// Detection out of the store listing, applied one screen earlier.
    @MainActor
    func testNothingDirectOnlyReachesTheAppStoreBuild() {
        guard DistributionChannel.current == .appStore else { return }
        for note in ReleaseNotes.all {
            XCTAssertFalse(
                note.items.contains(where: \.directOnly), "\(note.version) leaked a direct-only item")
            XCTAssertFalse(
                note.asides.contains(where: \.directOnly), "\(note.version) leaked a direct-only aside")
        }
    }
}

final class AppVersionTests: XCTestCase {
    func testOrdering() {
        XCTAssertTrue(AppVersion("1.9.0")! < AppVersion("1.10.0")!)
        XCTAssertTrue(AppVersion("1.2")! < AppVersion("1.2.1")!)
        XCTAssertEqual(AppVersion("1.2")!, AppVersion("1.2.0")!)
        XCTAssertTrue(AppVersion("2")! > AppVersion("1.99.99")!)
    }

    func testWhatIsNotAVersion() {
        for raw in [nil, "", " ", "1.2.3.4.5", "1..2", "v1.2", "1.2.x", "-1.0", "1.+2"] {
            XCTAssertNil(AppVersion(raw), "\(raw ?? "nil") should not parse")
        }
    }

    func testItPrintsWhatItWasGiven() {
        XCTAssertEqual(AppVersion("1.2.0")?.description, "1.2.0")
    }
}
