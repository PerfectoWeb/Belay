import Foundation

/// The shape of the release JSON Belay reads, and the one decision it makes
/// about it: which link Update Now should open.
///
/// Its own file for two reasons. `ReleaseChecker` was at the length this
/// project allows, and the nesting limit is two types deep, which an `Asset`
/// inside a `Release` inside the checker is not.
///
/// Coding keys rather than snake-cased properties, so the linters stay happy
/// and the wire format is written down in one obvious place.
struct GitHubRelease: Decodable {
    let tag: String
    let page: String

    /// Optional, and it has to be. A release with no files attached is a
    /// legitimate release, and treating its absence as a decoding failure
    /// turned "there is an update, here is the page" into "the update service
    /// sent something Belay could not read".
    let assets: [GitHubReleaseAsset]?

    /// Where to send somebody who pressed Update.
    ///
    /// The disk image itself when the release has one, so the download starts
    /// instead of a page opening for them to find the link on. The release page
    /// otherwise, which is the honest answer when a release is built some other
    /// way rather than a dead end.
    var installable: String {
        assets?.first { $0.name.hasSuffix(".dmg") }?.download ?? page
    }

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case page = "html_url"
        case assets
    }
}

/// One file attached to a release. Belay wants the disk image and ignores
/// everything else, including checksum files and whatever a later release
/// decides to carry alongside them.
struct GitHubReleaseAsset: Decodable {
    let name: String
    let download: String

    enum CodingKeys: String, CodingKey {
        case name
        case download = "browser_download_url"
    }
}
