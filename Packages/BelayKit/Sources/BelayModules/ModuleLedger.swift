import Foundation

/// One installed module: whether it is switched on, and since when it has been
/// here.
public struct ModuleRecord: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var installedAt: Date

    public init(isEnabled: Bool, installedAt: Date) {
        self.isEnabled = isEnabled
        self.installedAt = installedAt
    }
}

/// Which modules the user installed, and which of those are switched on.
///
/// Installed and enabled are two facts on purpose. Switching a module off keeps
/// its settings and its folder grants for the next time; removing it forgets
/// both. A single flag could only ever mean one of those.
public struct ModuleLedger: Equatable, Sendable {
    public static let defaultsKey = "BelayModules"

    public private(set) var records: [String: ModuleRecord]

    public init(records: [String: ModuleRecord] = [:]) {
        self.records = records
    }

    /// A ledger that does not decode is an empty one: the cost is installing a
    /// module again, which beats a Settings pane that cannot open.
    public init(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.defaultsKey),
            let records = try? JSONDecoder().decode([String: ModuleRecord].self, from: data)
        else {
            self.init()
            return
        }
        self.init(records: records)
    }

    public func isInstalled(_ id: ModuleID) -> Bool {
        records[id.rawValue] != nil
    }

    public func isEnabled(_ id: ModuleID) -> Bool {
        records[id.rawValue]?.isEnabled ?? false
    }

    /// Installing switches the module on: nobody installs something to leave it
    /// off. Installing twice keeps the first date.
    public mutating func install(_ id: ModuleID, at now: Date) {
        let since = records[id.rawValue]?.installedAt ?? now
        records[id.rawValue] = ModuleRecord(isEnabled: true, installedAt: since)
    }

    public mutating func remove(_ id: ModuleID) {
        records[id.rawValue] = nil
    }

    /// Does nothing for a module that is not installed, so a stale switch in a
    /// view cannot install one by accident.
    public mutating func setEnabled(_ isEnabled: Bool, for id: ModuleID) {
        records[id.rawValue]?.isEnabled = isEnabled
    }

    public func save(to defaults: UserDefaults) {
        guard !records.isEmpty else {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        defaults.set(try? JSONEncoder().encode(records), forKey: Self.defaultsKey)
    }
}
