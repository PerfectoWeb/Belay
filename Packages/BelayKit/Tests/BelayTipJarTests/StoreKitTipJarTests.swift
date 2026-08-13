import Foundation
import Testing

@testable import BelayTipJar

/// The one property that matters before the products exist: the App Store tip
/// jar must report itself unavailable, so the UI never renders a tip sheet
/// against identifiers App Store Connect has never heard of.
@Suite struct StoreKitTipJarTests {
    @Test func isUnavailableWhileProductIdentifiersArePlaceholders() {
        #expect(TipProducts.areRegistered == false)
        #expect(StoreKitTipJar().isAvailable == false)
    }

    @Test func offersNothingWhileUnavailable() async {
        #expect(await StoreKitTipJar().availableTips().isEmpty)
    }

    /// Guards the order of the checks in `purchase`: it has to refuse before it
    /// reaches StoreKit, otherwise an unavailable jar still shows the system
    /// purchase sheet.
    @Test func purchaseRefusesWhileUnavailable() async {
        let tip = Tip(id: TipProducts.small, title: "Small", subtitle: "")

        await #expect(throws: TipJarError.unavailable) {
            try await StoreKitTipJar().purchase(tip)
        }
    }

    @Test func productIdentifiersAreDistinctAndBundleScoped() {
        #expect(TipProducts.identifiers.count == Set(TipProducts.identifiers).count)
        #expect(TipProducts.identifiers.allSatisfy { $0.hasPrefix("com.perfectoweb.belay.tip.") })
    }
}
