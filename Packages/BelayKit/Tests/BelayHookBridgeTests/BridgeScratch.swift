import BelayCore
import Foundation

@testable import BelayHookBridge

/// A throwaway home directory. Every test in this target points the whole module
/// at one of these, so nothing can reach the real `~/.claude/settings.json`.
struct BridgeScratch {
    let root: URL
    let paths: BridgePaths

    init(settings: String? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("belay-bridge-\(UUID().uuidString)", isDirectory: true)
        paths = BridgePaths(
            support: root.appendingPathComponent("Application Support/Belay", isDirectory: true),
            claudeSettings: root.appendingPathComponent(".claude/settings.json"),
            codexHome: root.appendingPathComponent(".codex", isDirectory: true),
            clineHome: root.appendingPathComponent(".cline", isDirectory: true))
        try FileManager.default.createDirectory(
            at: claudeDirectory, withIntermediateDirectories: true)
        if let settings { try Data(settings.utf8).write(to: paths.claudeSettings) }
    }

    var claudeDirectory: URL { paths.claudeSettings.deletingLastPathComponent() }
    var installer: HookInstaller { HookInstaller(paths: paths) }
    var store: BridgeEndpointStore { BridgeEndpointStore(paths: paths) }

    func settingsText() -> String? {
        guard let data = try? Data(contentsOf: paths.claudeSettings) else { return nil }
        return String(bytes: data, encoding: .utf8)
    }

    func settingsObject() throws -> [String: Any] {
        let data = try Data(contentsOf: paths.claudeSettings)
        let parsed = try JSONSerialization.jsonObject(with: data)
        return parsed as? [String: Any] ?? [:]
    }

    func hooks(for event: HookEvent) throws -> [[String: Any]] {
        let section = try settingsObject()["hooks"] as? [String: Any] ?? [:]
        return section[event.rawValue] as? [[String: Any]] ?? []
    }

    func claudeDirectoryContents() -> [String] {
        let found = try? FileManager.default.contentsOfDirectory(atPath: claudeDirectory.path)
        return (found ?? []).sorted()
    }

    func backupContents() -> [String] {
        let found = try? FileManager.default.contentsOfDirectory(atPath: paths.backups.path)
        return (found ?? []).sorted()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension BridgeScratch {
    static let endpoint = BridgeEndpoint(port: 51234, token: "token-alpha")
    static let movedEndpoint = BridgeEndpoint(port: 51999, token: "token-alpha")
}

func sameJSON(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
    NSDictionary(dictionary: lhs).isEqual(to: rhs)
}

extension HookInstaller.Outcome {
    var backup: URL? {
        guard case .written(let url) = self else { return nil }
        return url
    }
}

/// A settings file that already has hooks of the user's own on the same events
/// Belay wants — including an HTTP hook on loopback at `/hook` that is *not*
/// ours. This is the dangerous shape, so most installer tests start here.
let settingsWithUserHooks = """
    {
      "skipWorkflowUsageWarning": true,
      "hooks": {
        "PreToolUse": [
          { "matcher": "Bash", "hooks": [{ "type": "command", "command": "audit.sh" }] }
        ],
        "Stop": [
          { "hooks": [{ "type": "http", "url": "http://127.0.0.1:9999/hook" }] }
        ],
        "TeammateIdle": [
          { "hooks": [{ "type": "command", "command": "notify" }] }
        ]
      }
    }
    """

/// Drains a receiver's stream in the background so a test can wait for signals
/// without owning the single-consumer iterator itself.
actor SignalCollector {
    private var received: [ActivitySignal] = []
    private var task: Task<Void, Never>?

    func start(on stream: AsyncStream<ActivitySignal>) {
        task = Task { [weak self] in
            for await signal in stream { await self?.append(signal) }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func append(_ signal: ActivitySignal) {
        received.append(signal)
    }

    var all: [ActivitySignal] { received }

    func wait(for count: Int, timeout: TimeInterval = 3) async -> [ActivitySignal] {
        let deadline = Date().addingTimeInterval(timeout)
        while received.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return received
    }

    /// Gives anything in flight a chance to arrive, for the tests that assert
    /// nothing was emitted.
    func settle() async {
        try? await Task.sleep(nanoseconds: 400_000_000)
    }
}

enum LoopbackProbe {
    /// A plain TCP connect, so "the port was released" is answered by the kernel
    /// rather than by a framework's idea of readiness.
    static func accepts(port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let outcome = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return outcome == 0
    }

    /// What the kernel says the socket is bound to, via `lsof`.
    static func listeningAddresses(port: UInt16) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
