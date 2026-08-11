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
            "Tipping is not available in this build."
        case .unknownTip(let id):
            "There is no tip called \(id)."
        case .cancelled:
            "The purchase was cancelled."
        case .pending:
            "The purchase is waiting for approval. Nothing else is needed from you."
        case .unverified:
            "The App Store could not verify the purchase."
        }
    }
}
