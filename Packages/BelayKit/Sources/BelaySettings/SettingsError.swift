import Foundation

public enum SettingsError: LocalizedError, Equatable {
    case unreadableStore
    case migrationFailed(from: Int)

    public var errorDescription: String? {
        switch self {
        case .unreadableStore:
            return String(
                localized: "Belay could not read its preferences and has fallen back to defaults.",
                bundle: .main)
        case .migrationFailed(let version):
            return String(
                localized: "Belay could not migrate preferences from version \(version).",
                bundle: .main)
        }
    }
}
