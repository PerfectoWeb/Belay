import Foundation
import Testing
import VigilCore

@testable import VigilSettings

@MainActor
@Suite struct SettingsMigrationTests {
    @Test func firstLaunchStampsTheCurrentSchema() throws {
        try withScratchDefaults { scratch in
            let store = SettingsStore(defaults: scratch.defaults)

            #expect(store.migration == .fresh)
            #expect(scratch.defaults.count(.schemaVersion) == SettingsSchema.current)
        }
    }

    @Test func migrationDoesNotRunTwice() throws {
        try withScratchDefaults { scratch in
            _ = SettingsStore(defaults: scratch.defaults)

            let second = SettingsStore(defaults: try scratch.reopened())

            #expect(second.migration == .upToDate)
        }
    }

    @Test func aPreVersionedStoreMigratesAndKeepsItsValues() throws {
        try withScratchDefaults { scratch in
            scratch.defaults.set(45.0, forKey: "gracePeriod")

            let store = SettingsStore(defaults: scratch.defaults)

            #expect(store.migration == .migrated(from: 0))
            #expect(store.gracePeriod == 45)
            #expect(scratch.defaults.count(.schemaVersion) == SettingsSchema.current)
        }
    }

    @Test func aNewerSchemaFallsBackToDefaultsWithoutCrashing() throws {
        try withScratchDefaults { scratch in
            scratch.defaults.set(SettingsSchema.current + 98, forKey: "schemaVersion")
            scratch.defaults.set(45.0, forKey: "gracePeriod")

            let store = SettingsStore(defaults: scratch.defaults)

            #expect(store.migration == .futureSchema(SettingsSchema.current + 98))
            #expect(store.migration.usesStoredValues == false)
            #expect(store.policy == AwakePolicy.default)
            // The newer stamp is left alone: this build has no business
            // pretending it downgraded the store.
            #expect(scratch.defaults.count(.schemaVersion) == SettingsSchema.current + 98)
        }
    }

    @Test func stepsFormAContiguousChainToTheCurrentVersion() {
        #expect(SettingsSchema.steps.last?.to == SettingsSchema.current)
        for (index, step) in SettingsSchema.steps.enumerated() {
            #expect(step.from == index)
            #expect(step.to == index + 1)
        }
    }
}
