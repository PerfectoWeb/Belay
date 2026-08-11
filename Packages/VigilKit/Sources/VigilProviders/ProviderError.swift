import Foundation

public enum ProviderError: LocalizedError, Equatable {
    case watchFailed(path: String)
    case accessNotGranted(path: String)

    public var errorDescription: String? {
        switch self {
        case .watchFailed(let path):
            return String(localized: "Vigil could not watch \(path) for activity.", bundle: .main)
        case .accessNotGranted(let path):
            return String(localized: "Vigil needs your permission to read \(path).", bundle: .main)
        }
    }
}
