import Foundation

/// Single source of truth for the product name and identifiers, so the rename
/// procedure in docs/NAMING.md stays a two-file change.
enum Branding {
    static let appName = "Vigil"
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.perfecto-web.vigil"

    /// The GitHub account, spelled once. Note it is **not** the bundle-id prefix:
    /// that is `perfecto-web`, the account is `perfectoweb`, and writing the URLs
    /// out by hand three times is how one of them ends up pointing at a 404.
    static let repositorySlug = "perfectoweb/vigil"

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
    static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
}
