import BelaySupport
import Foundation

/// What the store found on disk. Exposed so the UI and the tests can tell a
/// fresh install from an upgrade without re-reading UserDefaults.
public enum SettingsMigrationOutcome: Equatable, Sendable {
    /// Nothing of ours was stored; the schema stamp was written.
    case fresh
    case upToDate
    case migrated(from: Int)
    /// Written by a newer Belay. Stored values are ignored and defaults used.
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
    static let current = 2

    struct Step: Sendable {
        let from: Int
        let to: Int
        let apply: @Sendable (UserDefaults) -> Void
    }

    /// Version 1 is the first published layout, so its step is deliberately a
    /// no-op: it exists to prove the ordering and the stamping work.
    ///
    /// Version 2 moves one number. The grace period default was 90 s, which the
    /// pop-up drew as "1 min" because the label rounded; when the list gained a
    /// real 1 min row and 90 stopped being offered, every install that had never
    /// touched the setting showed an empty control.
    ///
    /// Deliberately only 90, and deliberately not "snap anything outside the
    /// list". A value somebody set on purpose is theirs, and a migration that
    /// rewrites preferences it merely disagrees with is not a migration.
    static let steps: [Step] = [
        Step(from: 0, to: 1) { _ in },
        Step(from: 1, to: 2) { defaults in
            guard defaults.number(.gracePeriod) == 90 else { return }
            defaults.store(60, .gracePeriod)
        }
    ]

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
