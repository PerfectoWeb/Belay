import Foundation

public enum ProviderError: LocalizedError, Equatable {
    case watchFailed(path: String)
    case accessNotGranted(path: String)
    /// The folder Belay watches does not exist yet. Distinct from the two
    /// above: nothing has gone wrong and nobody needs to do anything, the tool
    /// has simply not been used here yet.
    case notInUseYet(path: String)

    public var errorDescription: String? {
        switch self {
        case .watchFailed(let path):
            return String(localized: "Belay could not watch \(path) for activity.", bundle: .main)
        case .accessNotGranted(let path):
            return String(localized: "Belay needs your permission to read \(path).", bundle: .main)
        case .notInUseYet(let path):
            return String(localized: "Nothing to watch yet: \(path) does not exist.", bundle: .main)
        }
    }
}
