import BelayTipJar
import SwiftUI

/// The row of destinations under the About promises.
///
/// Two of the four differ by channel, and both differences are the same idea:
/// a link that is right on one channel is wrong or dead on the other.
///
/// The prominent slot is Donate on the direct build. A payment link inside a
/// Mac App Store build is a guideline violation and a rejection, which is why
/// `BelayTipJar` exists and why `coffeeURL` is a permanent nil. `donateURL` is
/// nil there at compile time, so this asks whether there is one rather than
/// which channel it is on. Rather than leave a hole where the accent used to
/// be, that build points at the product's own page instead.
///
/// "Rate on the App Store" appears only on the App Store build. Anyone running
/// that one installed it from the store, so the listing exists and the review
/// sheet opens; the same link in the direct build would send someone to a page
/// they may never have used and cannot review from.
struct AboutLinks: View {
    var body: some View {
        HStack(spacing: 8) {
            prominent
            if DistributionChannel.current == .appStore, let review = Branding.appStoreReviewURL {
                AboutLink(title: "Rate on the App Store", symbol: "star.bubble", url: review)
            }
            if let repository = Branding.repositoryURL {
                // "Star" rather than "GitHub": the destination is the same and
                // the label may as well say what it is for. Anyone who
                // dismissed the ask in Statistics, or never reached it, can
                // still find this.
                AboutLink(title: "Star on GitHub", symbol: "star", url: repository)
            }
            if let issues = Branding.issuesURL {
                AboutLink(title: "Report a bug", symbol: "ladybug", url: issues)
            }
            if let coffee = Branding.coffeeURL {
                AboutLink(title: "Buy me a coffee", symbol: "cup.and.saucer", url: coffee)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var prominent: some View {
        if let donate = Branding.donateURL {
            AboutLink(
                title: "Donate", symbol: "heart.fill", url: donate, isProminent: true,
                sound: .thanks)
        } else if let website = Branding.websiteURL {
            AboutLink(
                title: "Website", symbol: "safari", url: website, isProminent: true,
                sound: .thanks)
        }
    }
}
