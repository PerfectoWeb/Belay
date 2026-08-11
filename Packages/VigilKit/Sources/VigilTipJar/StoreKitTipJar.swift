import Foundation
import StoreKit

/// The Mac App Store tip jar: consumable in-app purchases, because a payment
/// link inside a sandboxed build is a guideline violation (docs/06).
///
/// This type is compiled in both channels. It would rather live behind
/// `#if VIGIL_MAS`, but that condition is set on the *app* target and Xcode
/// does not pass it down to a local SwiftPM target, so the `#if` would be false
/// everywhere and the code would be dead in the MAS build too — see
/// `DistributionChannel`. Channel selection happens in `TipJar.forCurrentChannel`
/// instead; splitting this file into its own MAS-only package product is the
/// version to reach for once `Package.swift` is in scope.
public struct StoreKitTipJar: TipJarProviding {
    private let identifiers: [String]

    public init(identifiers: [String] = TipProducts.identifiers) {
        self.identifiers = identifiers
    }

    /// False until the products exist in App Store Connect (BLOCKERS.md B2).
    /// Callers hide the whole tip UI on false, which is the safety property
    /// this class of bug needs: an unregistered identifier is not an error at
    /// the StoreKit level, it is simply absent from the results.
    public var isAvailable: Bool { TipProducts.areRegistered }

    public func availableTips() async -> [Tip] {
        guard isAvailable, let products = try? await Product.products(for: identifiers) else {
            return []
        }
        return products.map {
            Tip(id: $0.id, title: $0.displayName, subtitle: $0.displayPrice)
        }
    }

    public func purchase(_ tip: Tip) async throws {
        guard isAvailable else { throw TipJarError.unavailable }
        guard let product = try await Product.products(for: [tip.id]).first else {
            throw TipJarError.unknownTip(tip.id)
        }

        switch try await product.purchase() {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw TipJarError.unverified
            }
            // Consumables unlock nothing, so there is no state to record before
            // finishing. Leaving it unfinished would re-deliver it forever.
            await transaction.finish()
        case .userCancelled:
            throw TipJarError.cancelled
        case .pending:
            throw TipJarError.pending
        @unknown default:
            throw TipJarError.unavailable
        }
    }
}
