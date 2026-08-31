import Foundation

/// What a graceful quit took out of the agents' settings, so the next launch
/// can put exactly that back.
///
/// Hooks name a port, and a closed Belay answers on no port: every tool call
/// an agent made between quit and relaunch used to land as `ECONNREFUSED` in
/// the user's own terminal. Parking removes Belay's entries on the way out
/// and this record — not a guess, not a consent flag kept somewhere else —
/// says what to restore on the way back in. Restore consumes it, so a file
/// that lingers can only re-add what a quit provably removed.
public struct ParkedHooks: Codable, Equatable, Sendable {
    public var claude: Bool
    public var cline: Bool

    public init(claude: Bool = false, cline: Bool = false) {
        self.claude = claude
        self.cline = cline
    }

    public var isEmpty: Bool { !claude && !cline }
}

public struct ParkedHooksStore: Sendable {
    private let url: URL

    public init(paths: BridgePaths) {
        url = paths.support.appendingPathComponent("parked-hooks.json")
    }

    public func load() -> ParkedHooks? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ParkedHooks.self, from: data)
    }

    public func save(_ parked: ParkedHooks) {
        guard !parked.isEmpty else {
            clear()
            return
        }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(parked) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
