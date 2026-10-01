import Foundation

/// The name a module is known by, in the ledger and in the log.
///
/// A string rather than an enum so a ledger written by a newer Belay still
/// loads in an older one: a module this build has never heard of is carried
/// along, not dropped on the first save.
public struct ModuleID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let screenshotCleaner = ModuleID(rawValue: "screenshot-cleaner")
    public static let micKeepWarm = ModuleID(rawValue: "mic-keep-warm")
    public static let autoAllow = ModuleID(rawValue: "auto-allow")
    public static let nudge = ModuleID(rawValue: "nudge")
    public static let orphanWatch = ModuleID(rawValue: "orphan-watch")
}
