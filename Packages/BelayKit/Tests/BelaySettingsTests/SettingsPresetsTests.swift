import BelayCore
import Foundation
import Testing

@testable import BelaySettings

/// A preset list that cannot express the default is worse than no list: SwiftUI
/// renders an empty pop-up and then writes some other value back, so the user
/// silently ends up with a setting they never chose. That is how the
/// maximum-awake backstop switched itself off on first launch.
@Suite("Settings presets")
struct SettingsPresetsTests {
    @Test("Every default is offered by its own preset list")
    func defaultsAreRepresentable() {
        let policy = AwakePolicy.default
        #expect(
            SettingsPresets.gracePeriods.contains(policy.gracePeriod),
            "grace period default \(policy.gracePeriod) is not in \(SettingsPresets.gracePeriods)"
        )
        #expect(
            SettingsPresets.maxContinuousAwake.contains(policy.maxContinuousAwake),
            "max awake default is not offered by the preset list"
        )
    }

    @Test("Unlimited is offered, and is distinct from every finite choice")
    func unlimitedIsAnOption() {
        #expect(SettingsPresets.maxContinuousAwake.contains(nil))
        let finite = SettingsPresets.maxContinuousAwake.compactMap { $0 }
        #expect(finite.count == SettingsPresets.maxContinuousAwake.count - 1)
        #expect(Set(finite).count == finite.count, "duplicate preset values")
    }

    @Test("Presets are ordered, so the pop-up reads sensibly")
    func presetsAreSorted() {
        #expect(SettingsPresets.gracePeriods == SettingsPresets.gracePeriods.sorted())
        let finite = SettingsPresets.maxContinuousAwake.compactMap { $0 }
        #expect(finite == finite.sorted())
    }
}

/// A pop-up has a row per value and no row for anything else, so a value in
/// neither list draws an empty box. Two answers, and this covers both: schema 2
/// moves the one number an earlier build left everybody holding, and `nearest`
/// is what the control reads through so it can never draw blank whatever else
/// finds its way into the store.
///
/// What is deliberately *not* done is constraining the store to the lists.
/// `SettingsBounds` says what is legal, a 45 s grace period is legal, and a
/// model narrowed to fit one control's rows is the control leaking downwards.
@MainActor
@Suite("Every duration reaches a row")
struct SettingsSnapTests {
    @Test("Nearest always answers with a member of the list")
    func nearestStaysInTheList() {
        let finite = SettingsPresets.maxContinuousAwake.compactMap { $0 }
        for seconds in stride(from: -500.0, through: 60_000, by: 91) {
            #expect(
                SettingsPresets.gracePeriods.contains(
                    SettingsPresets.nearest(seconds, in: SettingsPresets.gracePeriods)))
            #expect(finite.contains(SettingsPresets.nearest(seconds, in: finite)))
        }
    }

    @Test("Nearest picks the closer of two neighbours")
    func nearestIsActuallyNearest() {
        #expect(SettingsPresets.nearest(90, in: SettingsPresets.gracePeriods) == 60)
        #expect(SettingsPresets.nearest(170, in: SettingsPresets.gracePeriods) == 180)
        #expect(SettingsPresets.nearest(100_000, in: SettingsPresets.gracePeriods) == 600)
    }

    private func migrated(gracePeriod: Double) throws -> SettingsStore {
        let suite = "belay.tests.migrate.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1, forKey: "schemaVersion")
        defaults.set(gracePeriod, forKey: "gracePeriod")
        return SettingsStore(defaults: defaults)
    }

    /// The install that prompted all of this: never touched the setting, so it
    /// held the old 90 s default and the control came up empty.
    @Test("Schema 2 moves the old 90 second default onto its row")
    func migrationMovesTheOldDefault() throws {
        let store = try migrated(gracePeriod: 90)
        #expect(store.migration == .migrated(from: 1))
        #expect(store.gracePeriod == 60, "90 s did not reach a row")
    }

    /// A number somebody chose is theirs, even if no row shows it.
    @Test("Schema 2 leaves a hand-set value alone")
    func migrationLeavesOtherValuesAlone() throws {
        #expect(try migrated(gracePeriod: 45).gracePeriod == 45)
    }
}

/// The delays behind the Shift key. They are ordinary settings values once
/// chosen, so everything the visible list has to satisfy, they have to too.
@Suite("Long sleep delays")
struct LongGracePeriodTests {
    @Test("The long delays extend the list rather than replacing it")
    func extendedListIsTheUnion() {
        let all = SettingsPresets.allGracePeriods
        #expect(all == all.sorted())
        #expect(Set(all) == Set(SettingsPresets.gracePeriods + SettingsPresets.longGracePeriods))
        // The default has to stay in the always-visible half: a setting whose
        // own value is behind a modifier key draws as a blank box.
        #expect(SettingsPresets.gracePeriods.contains(AwakePolicy.default.gracePeriod))
        #expect(Set(SettingsPresets.gracePeriods).isDisjoint(with: SettingsPresets.longGracePeriods))
    }

    @Test("Every long delay is one the settings layer will actually keep")
    func longDelaysSurviveClamping() {
        for seconds in SettingsPresets.longGracePeriods {
            #expect(
                SettingsBounds.gracePeriod.contains(seconds),
                "\(seconds) is outside the stored bounds and would be clamped away")
            #expect(SettingsPresets.nearest(seconds, in: SettingsPresets.allGracePeriods) == seconds)
        }
    }
}
