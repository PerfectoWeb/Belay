import Foundation
import VigilSupport

/// What the store found on disk. Exposed so the UI and the tests can tell a
/// fresh install from an upgrade without re-reading UserDefaults.
public enum SettingsMigrationOutcome: Equatable, Sendable {
    /// Nothing of ours was stored; the schema stamp was written.
    case fresh
    case upToDate
    case migrated(from: Int)
    /// Written by a newer Vigil. Stored values are ignored and defaults used.
    case futureSchema(Int)

    public var usesStoredValues: Bool {
        if case .futureSchema = self { return false }
        return true
    }
}

/// The versioned layout of the preferences domain.
///
/// Adding version 2 is meant to be boring: bump `current`, append one
/// `Step(from: 1, to: 2)`, and the existing tests cover the mechanism.
enum SettingsSchema {
    static let current = 1

    struct Step: Sendable {
        let from: Int
        let to: Int
        let apply: @Sendable (UserDefaults) -> Void
    }

    /// Version 1 is the first published layout, so its step is deliberately a
    /// no-op: it exists to prove the ordering and the stamping work.
    static let steps: [Step] = [Step(from: 0, to: 1) { _ in }]

    /// Brings `defaults` up to `current`, or reports that it is from the future.
    /// Never throws and never wipes: preferences are not worth crashing over.
    static func migrate(_ defaults: UserDefaults) -> SettingsMigrationOutcome {
        guard let stored = defaults.count(.schemaVersion) else {
            // No stamp: either a first launch, or a build that predates
            // versioning and whose keys are still readable as version 0.
            guard defaults.holdsAnySetting else {
                defaults.store(current, .schemaVersion)
                return .fresh
            }
            return run(from: 0, defaults)
        }
        guard stored != current else { return .upToDate }
        guard stored < current else {
            Log.settings.error(
                "Preferences schema \(stored, privacy: .public) is newer than this build; using defaults")
            return .futureSchema(stored)
        }
        return run(from: stored, defaults)
    }

    private static func run(from version: Int, _ defaults: UserDefaults) -> SettingsMigrationOutcome {
        for step in steps where step.from >= version {
            step.apply(defaults)
        }
        defaults.store(current, .schemaVersion)
        Log.settings.notice(
            "Migrated preferences from schema \(version, privacy: .public) to \(current, privacy: .public)")
        return .migrated(from: version)
    }
}
