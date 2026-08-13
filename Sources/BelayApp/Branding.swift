import Foundation

/// Single source of truth for the product name and identifiers, so the rename
/// procedure in docs/NAMING.md stays a two-file change.
enum Branding {
    static let appName = "Belay"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.perfectoweb.belay"

    /// The GitHub account, spelled once, because writing these URLs out by hand
    /// three times is how one of them ends up pointing at a 404. The bundle id
    /// now shares this spelling; the web domain does not, and is hyphenated.
    static let repositorySlug = "perfectoweb/belay"

    static let repositoryURL = URL(string: "https://github.com/\(repositorySlug)")
    static let issuesURL = URL(string: "https://github.com/\(repositorySlug)/issues")
    /// Placeholder until there is somewhere real to point it. The About pane
    /// hides the row rather than shipping a dead link.
    static let coffeeURL: URL? = nil
    static let donateURL = URL(string: "https://perfecto-web.com/d/")
    /// Whose app this is. Linked from the About footer rather than printed as
    /// dead text: the name is already there, and a name nobody can follow is a
    /// missed introduction.
    static let homepageURL = URL(string: "https://perfecto-web.com/")
    static let supportURL = repositoryURL

    /// The numeric Apple ID of the Mac App Store listing, once there is one.
    /// Until then the button opens the App Store's Updates page, which is the
    /// right place either way and needs no identifier.
    static let appStoreID: String? = nil

    /// Opening this asks the App Store app to do the work. It is a hand-off,
    /// not a request: the App Store build has no outbound network entitlement
    /// and could not check for a new version itself if it wanted to.
    static var appStoreURL: URL? {
        if let appStoreID {
            return URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)")
        }
        return URL(string: "macappstore://showUpdatesPage")
    }
    static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
}
