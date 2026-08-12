import BelaySupport
import Foundation

/// Where the receiver is listening and the secret that proves a caller is the
/// user's own Claude Code and not some other process on the machine.
public struct BridgeEndpoint: Sendable, Equatable, Codable {
    public let port: UInt16
    public let token: String

    public init(port: UInt16, token: String) {
        self.port = port
        self.token = token
    }

    public var url: String { HookConfiguration.url(port: port) }
}

/// Reads and writes `~/Library/Application Support/Belay/bridge.json`.
///
/// The token is a local credential: anything that can read it can tell Belay a
/// session is busy and pin the Mac awake. The file is therefore created `0600`
/// and its directory `0700`, and the token is reused across launches so a moved
/// or restarted app does not invalidate hooks the user already consented to.
public struct BridgeEndpointStore: Sendable {
    /// 256 bits from the system CSPRNG, hex encoded so it is safe verbatim in
    /// an HTTP header and in JSON.
    static let tokenByteCount = 32

    private let url: URL

    public init(paths: BridgePaths = .real()) {
        url = paths.bridgeRecord
    }

    public func load() -> BridgeEndpoint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BridgeEndpoint.self, from: data)
    }

    public func save(_ endpoint: BridgeEndpoint) throws {
        let directory = url.deletingLastPathComponent()
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(endpoint)
            try? manager.removeItem(at: url)
            // Created with the mode already set rather than chmod-ed afterwards:
            // no window in which the token is world readable.
            guard
                manager.createFile(
                    atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
            else {
                throw BridgeError.settingsWriteFailed("could not create \(url.lastPathComponent)")
            }
        } catch let error as BridgeError {
            throw error
        } catch {
            throw BridgeError.settingsWriteFailed(error.localizedDescription)
        }
    }

    /// Keeps the existing token if there is one, so reinstalls are not needed
    /// every time the ephemeral port changes.
    public func endpoint(port: UInt16) throws -> BridgeEndpoint {
        let endpoint = BridgeEndpoint(port: port, token: load()?.token ?? Self.makeToken())
        try save(endpoint)
        Log.bridge.debug("Hook receiver listening on 127.0.0.1:\(port, privacy: .public)")
        return endpoint
    }

    static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<tokenByteCount)
            .map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }
}
