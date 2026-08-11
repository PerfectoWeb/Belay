import Foundation

public enum SettingsError: LocalizedError, Equatable {
    case unreadableStore
    case migrationFailed(from: Int)

    public var errorDescription: String? {
        switch self {
        case .unreadableStore:
            return "Vigil could not read its preferences and has fallen back to defaults."
        case .migrationFailed(let version):
            return "Vigil could not migrate preferences from version \(version)."
        }
    }
}
