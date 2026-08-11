import Foundation
import Testing
import VigilCore

@testable import VigilSettings

/// These use literal key strings on purpose: the on-disk names are a contract,
/// and renaming one would silently reset every user's preferences.
@MainActor
@Suite struct SettingsClampingTests {
    @Test func outOfRangeStoredValuesAreClamped() throws {
        try withScratchDefaults { scratch in
            scratch.defaults.set(99_999.0, forKey: "gracePeriod")
            scratch.defaults.set(1.0, forKey: "assertionTimeout")
            scratch.defaults.set(5.0, forKey: "batteryFloor")
            scratch.defaults.set(-10.0, forKey: "sessionTTL")
            scratch.defaults.set(0.0, forKey: "awaitingUserBudget")
            scratch.defaults.set(60 * 60 * 24 * 365.0, forKey: "maxContinuousAwake")

            let store = SettingsStore(defaults: scratch.defaults)

            #expect(store.gracePeriod == SettingsBounds.gracePeriod.upperBound)
            #expect(store.assertionTimeout == SettingsBounds.assertionTimeout.lowerBound)
            #expect(store.batteryFloor == SettingsBounds.batteryFloor.upperBound)
            #expect(store.sessionTTL == SettingsBounds.sessionTTL.lowerBound)
            #expect(store.awaitingUserBudget == SettingsBounds.awaitingUserBudget.lowerBound)
            #expect(store.maxContinuousAwake == SettingsBounds.maxContinuousAwake.upperBound)
        }
    }

    @Test func garbageStoredValuesFallBackToDefaults() throws {
        try withScratchDefaults { scratch in
            scratch.defaults.set("banana", forKey: "gracePeriod")
            scratch.defaults.set([1, 2], forKey: "assertionTimeout")
            scratch.defaults.set(Double.nan, forKey: "sessionTTL")
            scratch.defaults.set("wednesday", forKey: "mode")
            scratch.defaults.set("claudeCode", forKey: "enabledProviders")

            let store = SettingsStore(defaults: scratch.defaults)

            #expect(store.policy == AwakePolicy.default)
            #expect(store.enabledProviders == [.claudeCode])
        }
    }

    @Test func clampedValuesAreNeverPersistedOutOfRange() throws {
        try withScratchDefaults { scratch in
            scratch.defaults.set(99_999.0, forKey: "gracePeriod")
            let store = SettingsStore(defaults: scratch.defaults)
            store.keepDisplayAwake = true

            let reopened = SettingsStore(defaults: try scratch.reopened())

            #expect(reopened.gracePeriod == SettingsBounds.gracePeriod.upperBound)
        }
    }

    @Test func callerSuppliedValuesAreClampedToo() throws {
        try withScratchDefaults { scratch in
            let store = SettingsStore(defaults: scratch.defaults)
            store.assertionTimeout = 100_000
            store.sessionTTL = 1
            store.taskFinishedThreshold = -1

            #expect(store.assertionTimeout == SettingsBounds.assertionTimeout.upperBound)
            #expect(store.sessionTTL == SettingsBounds.sessionTTL.lowerBound)
            #expect(store.taskFinishedThreshold == SettingsBounds.taskFinishedThreshold.lowerBound)
        }
    }

    @Test func unlimitedMaxAwakeIsDistinctFromZero() throws {
        try withScratchDefaults { scratch in
            let store = SettingsStore(defaults: scratch.defaults)
            store.maxContinuousAwake = nil
            #expect(store.policy.maxContinuousAwake == nil)

            let reopened = SettingsStore(defaults: try scratch.reopened())
            #expect(reopened.maxContinuousAwake == nil)

            reopened.maxContinuousAwake = 0
            #expect(reopened.maxContinuousAwake == SettingsBounds.maxContinuousAwake.lowerBound)
            #expect(reopened.maxContinuousAwake != nil)

            let again = SettingsStore(defaults: try scratch.reopened())
            #expect(again.maxContinuousAwake == SettingsBounds.maxContinuousAwake.lowerBound)
        }
    }

    @Test func disabledBatteryGuardRoundTrips() throws {
        try withScratchDefaults { scratch in
            let store = SettingsStore(defaults: scratch.defaults)
            store.batteryFloor = nil

            let reopened = SettingsStore(defaults: try scratch.reopened())

            #expect(reopened.batteryFloor == nil)
            #expect(reopened.policy.batteryFloor == nil)

            reopened.batteryFloor = 0
            #expect(reopened.batteryFloor == 0)
        }
    }
}
