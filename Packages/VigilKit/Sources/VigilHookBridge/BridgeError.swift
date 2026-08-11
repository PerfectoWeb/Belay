import Foundation

public enum BridgeError: LocalizedError, Equatable {
    case listenerFailed(String)
    case settingsNotPlainJSON
    case settingsUnreadable(String)
    case settingsWriteFailed(String)
    /// `settings.json` parses, but its `hooks` value is not the object we know
    /// how to merge into. Refusing beats guessing at the user's file (risk R2).
    case hooksNotAnObject
    case backupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .listenerFailed(let reason):
            return "Vigil could not start its local hook receiver: \(reason)"
        case .settingsNotPlainJSON:
            return "Your Claude Code settings file is not plain JSON, so Vigil will not modify it."
        case .settingsUnreadable(let reason):
            return "Vigil could not read your Claude Code settings: \(reason)"
        case .settingsWriteFailed(let reason):
            return "Vigil could not update your Claude Code settings: \(reason)"
        case .hooksNotAnObject:
            return "Your Claude Code settings file has a hooks entry Vigil does not recognise, "
                + "so it made no changes."
        case .backupFailed(let reason):
            return "Vigil could not back up your Claude Code settings, so it made no changes: \(reason)"
        }
    }
}
