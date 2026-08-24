import BelaySupport
import Foundation

/// One hook as `codex app-server` reports it: enough to trust it and nothing
/// more.
public struct CodexListedHook: Sendable, Equatable {
    public let key: String
    public let currentHash: String
    public let trustStatus: String
    public let sourcePath: String

    public var isTrusted: Bool { trustStatus == "trusted" }
}

/// Reads the hook trust ledger out of `codex app-server`.
///
/// Codex refuses to run hooks it does not trust — silently, which is the worst
/// kind of refusal — and trust is a `sha256` of the whole hook definition,
/// recorded in `config.toml`. The hash is not derivable from the command
/// string, but the CLI hands it over for free: `hooks/list` over the
/// app-server's stdio JSON-RPC returns every discovered hook with its `key`
/// and `currentHash`, offline, no API turn. Verified live on 0.148.0-alpha.21.
enum CodexAppServer {
    static let timeout: TimeInterval = 15

    /// Spawns the server, asks once, tears it down. `codexHome` nil means the
    /// binary's own default (`~/.codex`).
    static func listHooks(binary: URL, codexHome: URL? = nil) throws -> [CodexListedHook] {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["app-server"]
        var environment = ProcessInfo.processInfo.environment
        if let codexHome { environment["CODEX_HOME"] = codexHome.path }
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw BridgeError.codexUnavailable(error.localizedDescription)
        }
        defer {
            process.terminate()
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }

        let client = #"{"clientInfo":{"name":"belay","title":"Belay","version":"1.0"}}"#
        let requests = [
            #"{"id":1,"method":"initialize","params":"# + client + "}",
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"hooks/list","params":{}}"#
        ].map { $0 + "\n" }.joined()
        input.fileHandleForWriting.write(Data(requests.utf8))

        // Read until the id:2 answer arrives or the clock runs out. The
        // stream interleaves notifications; only the numbered replies count.
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        while Date() < deadline {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            buffer.append(chunk)
            if let hooks = answer(in: buffer) { return hooks }
        }
        throw BridgeError.codexUnavailable("codex app-server did not answer hooks/list")
    }

    /// One hook as the reply spells it, hoisted for the nesting rule.
    private struct ListedWire: Decodable {
        let key: String
        let currentHash: String?
        let trustStatus: String?
        let sourcePath: String?
    }

    /// The parsed `hooks/list` reply, or `nil` while it has not arrived yet.
    static func answer(in buffer: Data) -> [CodexListedHook]? {
        struct Reply: Decodable {
            let id: Int?
            let result: Result?
            struct Result: Decodable { let data: [Entry]? }
            struct Entry: Decodable { let hooks: [ListedWire]? }
        }
        for line in buffer.split(separator: UInt8(ascii: "\n")) {
            guard let reply = try? JSONDecoder().decode(Reply.self, from: Data(line)),
                reply.id == 2, let groups = reply.result?.data
            else { continue }
            return groups.flatMap { $0.hooks ?? [] }.map {
                CodexListedHook(
                    key: $0.key,
                    currentHash: $0.currentHash ?? "",
                    trustStatus: $0.trustStatus ?? "",
                    sourcePath: $0.sourcePath ?? "")
            }
        }
        return nil
    }

    /// Where the user's codex actually lives. The PATH is tried first; the
    /// ChatGPT app's bundled copy is the fallback that exists on this Mac's
    /// kind of install, where nothing was ever symlinked into the PATH.
    static func locateBinary() -> URL? {
        let candidates = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
