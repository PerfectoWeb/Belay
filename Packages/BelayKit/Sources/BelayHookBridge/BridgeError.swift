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
            return String(
                localized: "Belay could not start its local hook receiver: \(reason)", bundle: .main)
        case .settingsNotPlainJSON:
            return String(
                localized:
                    "Your Claude Code settings file is not plain JSON, so Belay will not modify it.",
                bundle: .main)
        case .settingsUnreadable(let reason):
            return String(
                localized: "Belay could not read your Claude Code settings: \(reason)", bundle: .main
            )
        case .settingsWriteFailed(let reason):
            return String(
                localized: "Belay could not update your Claude Code settings: \(reason)",
                bundle: .main)
        case .hooksNotAnObject:
            return String(
                localized: """
                    Your Claude Code settings file has a hooks entry Belay does not recognise, \
                    so it made no changes.
                    """, bundle: .main)
        case .backupFailed(let reason):
            return String(
                localized: """
                    Belay could not back up your Claude Code settings, so it made no \
                    changes: \(reason)
                    """, bundle: .main)
        }
    }
}
