import Foundation
import Testing

@testable import BelayModules

@Suite("Nudge rules")
struct NudgeRulesTests {
    @Test("The defaults are the ones the card promises")
    func defaults() {
        let rules = NudgeRules()
        #expect(rules.finishedSound && rules.waitingSound && rules.quietSound)
        #expect(rules.namesFinished)
        #expect(rules.repeatAfterMinutes == 5)
        #expect(rules.repeatAtMost == 3)
        #expect(rules.minimumRunSeconds == 30)
    }

    @Test("A record with fields missing loads with their defaults")
    func missingFields() throws {
        let rules = try JSONDecoder().decode(NudgeRules.self, from: Data(#"{"quietSound":false}"#.utf8))
        #expect(rules.quietSound == false)
        #expect(rules.finishedSound && rules.waitingSound && rules.namesFinished)
        #expect(rules.repeatAfterMinutes == 5)
        #expect(rules.repeatAtMost == 3)
        #expect(rules.minimumRunSeconds == 30)
    }

    @Test("A value the card cannot show falls back to the default")
    func unknownValues() throws {
        let json = #"{"repeatAfterMinutes":7,"repeatAtMost":4,"minimumRunSeconds":-3}"#
        let rules = try JSONDecoder().decode(NudgeRules.self, from: Data(json.utf8))
        #expect(rules == NudgeRules())
        #expect(NudgeRules(repeatAfterMinutes: 0).repeatAfterMinutes == 0)
    }

    @Test("Saving and loading round-trips, and an empty store gives the defaults")
    func roundTrip() throws {
        let suite = "com.perfectoweb.belay.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(NudgeRules.load(from: defaults) == NudgeRules())

        let chosen = NudgeRules(
            finishedSound: false, waitingSound: true, quietSound: false, namesFinished: false,
            repeatAfterMinutes: 10, repeatAtMost: 5, minimumRunSeconds: 300)
        chosen.save(to: defaults)
        #expect(NudgeRules.load(from: defaults) == chosen)
    }
}
