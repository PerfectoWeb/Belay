import Foundation
import Testing

@testable import BelayModules

@Suite("Screenshot sweep")
struct ScreenshotSweepTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let hour: TimeInterval = 3600

    private func shot(
        _ name: String = "a.png",
        age: TimeInterval,
        editedAfter: TimeInterval = 0,
        recording: Bool = false,
        tagged: Bool = false
    ) -> ScreenshotCandidate {
        let created = now.addingTimeInterval(-age)
        return ScreenshotCandidate(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            created: created,
            modified: created.addingTimeInterval(editedAfter),
            isRecording: recording,
            isTagged: tagged
        )
    }

    @Test("Only screenshots past the age are due")
    func ageDecides() {
        let rules = ScreenshotRules(age: 4 * hour)
        let young = shot("young.png", age: 4 * hour - 1)
        let old = shot("old.png", age: 4 * hour)

        #expect(ScreenshotSweep.due([young, old], rules: rules, now: now) == [old])
    }

    @Test("A recording is kept unless recordings are included")
    func recordings() {
        let film = shot("film.mov", age: 10 * hour, recording: true)

        #expect(ScreenshotSweep.due([film], rules: ScreenshotRules(age: hour), now: now).isEmpty)
        let inclusive = ScreenshotRules(age: hour, includesRecordings: true)
        #expect(ScreenshotSweep.due([film], rules: inclusive, now: now) == [film])
    }

    @Test("Tagged and edited screenshots are kept by default")
    func touchedAreKept() {
        let tagged = shot("tagged.png", age: 10 * hour, tagged: true)
        let edited = shot("edited.png", age: 10 * hour, editedAfter: 60)

        #expect(
            ScreenshotSweep.due([tagged, edited], rules: ScreenshotRules(age: hour), now: now)
                .isEmpty)
    }

    @Test("The second or two macOS takes to write a file is not an edit")
    func writeLagIsNotAnEdit() {
        let plain = shot(age: 10 * hour, editedAfter: 2)

        #expect(ScreenshotSweep.due([plain], rules: ScreenshotRules(age: hour), now: now) == [plain])
    }

    @Test("With the protection off, a recent edit still buys the file its full age")
    func editRestartsTheClock() {
        let rules = ScreenshotRules(age: 4 * hour, keepsTouched: false)
        let justSaved = shot("saved.png", age: 10 * hour, editedAfter: 9 * hour)
        let savedLongAgo = shot("stale.png", age: 10 * hour, editedAfter: hour)

        #expect(ScreenshotSweep.due([justSaved, savedLongAgo], rules: rules, now: now) == [savedLongAgo])
    }

    @Test("An automatic pass counts nothing from before the cleaner was switched on")
    func graceFromSwitchOn() {
        let rules = ScreenshotRules(age: 4 * hour)
        let alreadyThere = shot("old.png", age: 100 * hour)
        let switchedOn = now.addingTimeInterval(-3 * hour)

        #expect(
            ScreenshotSweep.due([alreadyThere], rules: rules, now: now, notBefore: switchedOn)
                .isEmpty)
        let later = now.addingTimeInterval(hour)
        #expect(
            ScreenshotSweep.due([alreadyThere], rules: rules, now: later, notBefore: switchedOn)
                == [alreadyThere])
        // Asked for by name: no grace.
        #expect(ScreenshotSweep.due([alreadyThere], rules: rules, now: now) == [alreadyThere])
    }

    @Test("A file dated in the future is never due")
    func futureDate() {
        let ahead = shot(age: -hour)

        #expect(ScreenshotSweep.due([ahead], rules: ScreenshotRules(age: hour), now: now).isEmpty)
    }

    @Test("A pass counts what it moved, what refused, and what it could not read")
    func passReport() {
        let old = shot("old.png", age: 5 * hour)
        let stuck = shot("stuck.png", age: 5 * hour)
        let young = shot("young.png", age: 60)
        let sweeper = ScreenshotSweeper(
            list: { folder in
                guard folder.path == "/desk" else { throw CocoaError(.fileReadNoPermission) }
                return [old, stuck, young]
            },
            trash: { url in
                if url.lastPathComponent == "stuck.png" { throw CocoaError(.fileWriteNoPermission) }
            }
        )
        let rules = ScreenshotRules(age: 4 * hour, folders: ["/desk", "/gone"])

        let report = sweeper.run(rules: rules, now: now)

        #expect(report.trashed == 1)
        #expect(report.failed == 1)
        #expect(report.unreadable.map(\.path) == ["/gone"])
    }
}

@Suite("Screenshot rules")
struct ScreenshotRulesTests {
    @Test("A record written before a rule existed takes that rule's default")
    func missingFields() throws {
        let rules = try JSONDecoder().decode(
            ScreenshotRules.self, from: Data(#"{"age": 7200}"#.utf8))

        #expect(rules == ScreenshotRules(age: 7200))
        #expect(rules.keepsTouched)
        #expect(!rules.includesRecordings)
    }

    @Test("An age the picker cannot show lands on the nearest one it can")
    func nearestAge() {
        #expect(ScreenshotRules(age: 5000).age == 3600)
        #expect(ScreenshotRules(age: 0).age == 3600)
        #expect(ScreenshotRules(age: 9_999_999).age == 168 * 3600)
    }

    @Test("Rules survive a relaunch")
    func roundTrip() throws {
        let scratch = try Scratch()
        defer { scratch.discard() }
        let rules = ScreenshotRules(
            age: 8 * 3600, includesRecordings: true, keepsTouched: false, folders: ["/desk"])

        rules.save(to: scratch.defaults)

        #expect(ScreenshotRules.load(from: try scratch.reopened()) == rules)
    }
}
