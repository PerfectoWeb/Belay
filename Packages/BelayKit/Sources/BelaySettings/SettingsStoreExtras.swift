import Foundation

/// Accessors that arrived after the store hit the file-length ceiling; the
/// pattern is identical to its own.
extension SettingsStore {
    public var notifyOnAwaySummary: Bool {
        get { values.notifyOnAwaySummary }
        set { update { $0.notifyOnAwaySummary = newValue } }
    }

    public var showToolBadges: Bool {
        get { values.showToolBadges }
        set { update { $0.showToolBadges = newValue } }
    }
}
