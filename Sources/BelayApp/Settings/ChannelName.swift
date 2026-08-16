import BelayChannel
import Foundation

extension DistributionChannel {
    /// What to call this build in front of a person.
    ///
    /// Named for where it came from rather than for its build flag: `appStore`
    /// is our word for it and "Mac App Store" is theirs. It lives in the app
    /// target because that is where the string catalogue is; the enum itself
    /// is in a package, whose bundle has no translations in it.
    ///
    /// Shown beside the version in About, because the two answer one question
    /// between them. A bug report that says "1.0.0 (1)" leaves out the half
    /// that decides whether the reporter is sandboxed, whether they have an
    /// update check at all, and how the app reached their Mac.
    var displayName: String {
        switch self {
        case .appStore: String(localized: "Mac App Store")
        case .direct: String(localized: "Direct download")
        }
    }
}
