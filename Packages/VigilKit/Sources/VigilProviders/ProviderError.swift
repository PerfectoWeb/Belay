import Foundation

public enum ProviderError: LocalizedError, Equatable {
    case watchFailed(path: String)
    case accessNotGranted(path: String)

    public var errorDescription: String? {
        switch self {
        case .watchFailed(let path):
            return "Vigil could not watch \(path) for activity."
        case .accessNotGranted(let path):
            return "Vigil needs your permission to read \(path)."
        }
    }
}
