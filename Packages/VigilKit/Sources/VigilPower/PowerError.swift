import Foundation

public enum PowerError: LocalizedError, Equatable {
    case assertionFailed(code: Int32)
    case noPowerSource

    public var errorDescription: String? {
        switch self {
        case .assertionFailed(let code):
            return "macOS refused to create the sleep assertion (IOKit error \(code))."
        case .noPowerSource:
            return "Vigil could not read this Mac's power source."
        }
    }
}
