import Foundation
import Observation
import VigilSupport

/// Checks for a newer release.
///
/// **This is the one thing in Vigil that touches the network, and it is off by
/// default.** The app's whole pitch is that nothing leaves the Mac; an updater
/// that phones home the moment you install it would make that a lie told in the
/// About pane. So the user turns it on, and until they do Vigil never opens a
/// socket. What leaves the Mac when they do is one HTTPS GET carrying no query
/// and no identifier — GitHub sees an IP and a user agent, the same as opening
/// the releases page in a browser.
///
/// It only *finds* updates. Downloading and installing one in place is Sparkle's
/// job and needs an EdDSA key and a hosted appcast (BLOCKERS.md B3); until those
/// exist, "there is a new version, here it is" is the honest half to ship, and
/// this type is shaped so Sparkle replaces the second half without the UI
/// changing.
@MainActor
@Observable
final class ReleaseChecker {
    enum Status: Equatable {
        case never
        case checking
        case upToDate(Date)
        case available(version: String, url: URL)
        case failed(String)
    }

    private(set) var status: Status = .never

    /// Off until asked. Stored here rather than in `SettingsStore` because it is
    /// not policy — it does not affect what Vigil does to your Mac — and adding
    /// it there means a schema migration for a checkbox.
    var isAutomatic: Bool {
        get { defaults.bool(forKey: Self.automaticKey) }
        set {
            defaults.set(newValue, forKey: Self.automaticKey)
            if newValue { check() }
        }
    }

    static let automaticKey = "vigil.updates.automatic"
    static let lastCheckKey = "vigil.updates.lastCheck"
    /// Daily. An update checker that runs on launch and then every hour is
    /// telemetry with extra steps.
    static let interval: TimeInterval = 24 * 60 * 60

    /// The App Store ships its own updater and rejects a second one, so on that
    /// channel this whole block is absent rather than disabled.
    static var isSupported: Bool {
        #if VIGIL_MAS
        return false
        #else
        return true
        #endif
    }

    private let defaults: UserDefaults
    private let fetch: @Sendable (URL) async throws -> Data
    private let current: String

    init(
        defaults: UserDefaults = .standard,
        current: String = Branding.version,
        fetch: @escaping @Sendable (URL) async throws -> Data = ReleaseChecker.get
    ) {
        self.defaults = defaults
        self.current = current
        self.fetch = fetch
    }

    /// Runs a check if one is due. Called at launch and on a daily timer, and it
    /// is the *only* automatic caller — the button below goes straight to
    /// `check()`.
    func checkIfDue(now: Date = Date()) {
        guard Self.isSupported, isAutomatic else { return }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date
        guard last.map({ now.timeIntervalSince($0) >= Self.interval }) ?? true else { return }
        check(now: now)
    }

    func check(now: Date = Date()) {
        guard Self.isSupported, status != .checking else { return }
        status = .checking
        Task { [fetch, current] in
            guard let url = Self.latestReleaseURL else {
                status = .failed(String(localized: "No release feed is configured."))
                return
            }
            do {
                let release = try JSONDecoder().decode(Release.self, from: try await fetch(url))
                defaults.set(now, forKey: Self.lastCheckKey)
                let latest = release.tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if Self.isNewer(latest, than: current), let page = URL(string: release.page) {
                    status = .available(version: latest, url: page)
                } else {
                    status = .upToDate(now)
                }
            } catch {
                Log.app.error("update check failed: \(error.localizedDescription, privacy: .public)")
                status = .failed(Self.reason(for: error))
            }
        }
    }

    /// What a failed check says out loud.
    ///
    /// Never the system's own description, which was what this used to show. It
    /// names the host it could not reach, it arrives in the language macOS is
    /// running rather than the one picked in Settings, and for a malformed
    /// payload it is a sentence about Swift decoding. Three outcomes is all
    /// anyone can act on, and none of them needs to say where releases live:
    /// that is a distribution decision, and it may become the App Store.
    private static func reason(for error: Error) -> String {
        if let update = error as? UpdateError, let described = update.errorDescription {
            return described
        }
        if error is DecodingError {
            return String(localized: "The update service sent something Vigil could not read.")
        }
        return String(localized: "Could not reach the update service.")
    }

    var lastChecked: Date? { defaults.object(forKey: Self.lastCheckKey) as? Date }

    static var latestReleaseURL: URL? {
        URL(string: "https://api.github.com/repos/\(Branding.repositorySlug)/releases/latest")
    }

    /// Numeric, component by component. String comparison would call 1.10.0
    /// older than 1.9.0 and quietly stop offering updates at the tenth release.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let right = current.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let mine = index < left.count ? left[index] : 0
            let theirs = index < right.count ? right[index] : 0
            if mine != theirs { return mine > theirs }
        }
        return false
    }

    /// One session for the process. `URLSession` retains itself until it is
    /// invalidated, so building one per check leaked a session and its storage
    /// on every daily tick.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    /// No cookies, no credentials, no cache that could outlive the check.
    private static let get: @Sendable (URL) async throws -> Data = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Vigil/\(Branding.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    /// The two fields of the release JSON Vigil reads. Coding keys rather
    /// than snake-cased properties, so the linters stay happy and the wire
    /// format is written down in one obvious place.
    private struct Release: Decodable {
        let tag: String
        let page: String

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case page = "html_url"
        }
    }

    enum UpdateError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(404):
                return String(localized: "No releases have been published yet.")
            case .badResponse(let code):
                // Named after the role, not the host. Where releases come
                // from is a distribution decision that can change to the App
                // Store or anywhere else, and a message that has to be
                // retranslated in six languages when it does is a message that
                // should not have said it.
                return String(localized: "The server answered \(code).")
            }
        }
    }
}
