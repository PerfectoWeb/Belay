import Foundation

/// Every StoreKit identifier in the product, in one place, because none of them
/// are real yet.
///
/// Consumable tip products cannot be registered without the user's App Store
/// Connect account (BLOCKERS.md B2). The identifiers below are the names we
/// intend to register, spelled the way App Store Connect wants them, and
/// `areRegistered` is the single switch that turns the tip jar on once they
/// exist. Until then `StoreKitTipJar.isAvailable` is false and no tip UI is
/// ever built — asking StoreKit for products that do not exist succeeds and
/// returns nothing, which would show the user an empty tip sheet.
public enum TipProducts {
    public static let small = "com.perfecto-web.vigil.tip.small"
    public static let medium = "com.perfecto-web.vigil.tip.medium"
    public static let large = "com.perfecto-web.vigil.tip.large"

    public static let identifiers = [small, medium, large]

    /// Flip to `true` in the same commit that registers the products, and not
    /// before. See BLOCKERS.md B2.
    public static let areRegistered = false

    /// The direct build's equivalent: a plain link, no purchase, no nagging.
    public static let supportLink = Tip(
        id: "support",
        title: "Support development",
        subtitle: "Opens the project page in your browser"
    )
}
