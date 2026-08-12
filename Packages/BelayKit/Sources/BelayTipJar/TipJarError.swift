import Foundation

public enum TipJarError: LocalizedError, Equatable {
    case unavailable
    case unknownTip(String)
    case cancelled
    case pending
    case unverified

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "Tipping is not available in this build.", bundle: .main)
        case .unknownTip(let id):
            String(localized: "There is no tip called \(id).", bundle: .main)
        case .cancelled:
            String(localized: "The purchase was cancelled.", bundle: .main)
        case .pending:
            String(
                localized: "The purchase is waiting for approval. Nothing else is needed from you.",
                bundle: .main)
        case .unverified:
            String(localized: "The App Store could not verify the purchase.", bundle: .main)
        }
    }
}
