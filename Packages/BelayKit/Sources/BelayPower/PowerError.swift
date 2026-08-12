import Foundation

public enum PowerError: LocalizedError, Equatable {
    case assertionFailed(code: Int32)
    case noPowerSource

    public var errorDescription: String? {
        switch self {
        case .assertionFailed(let code):
            return String(
                // Widened so the key carries %lld rather than a width that
                // depends on how IOKit happens to type its return.
                localized: "macOS refused to create the sleep assertion (IOKit error \(Int(code))).",
                bundle: .main)
        case .noPowerSource:
            return String(localized: "Belay could not read this Mac's power source.", bundle: .main)
        }
    }
}
