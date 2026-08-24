import BelayCore
import Foundation
import Testing

@testable import BelayHookBridge

/// The codex side of the bridge: hooks.json surgery, the positional trust
/// keys, and the config.toml ledger — all against a scratch home.
@Suite("Codex hook installer")
struct CodexInstallerTests {
    private let endpoint = BridgeEndpoint(port: 4242, token: "sekret")

    private func scratch(settings: String? = nil) throws -> BridgeScratch {
        try BridgeScratch(settings: settings)
    }

    private func installer(
        _ scratch: BridgeScratch, listed: [CodexListedHook]? = nil
    ) -> CodexHookInstaller {
        let path = scratch.paths.codexHooks.path
        let hooks =
            listed
            ?? CodexHookConfiguration.eventNames.map {
                CodexListedHook(
                    key: "\(path):\(CodexHookConfiguration.snakeCase($0)):0:0",
                    currentHash: "sha256:hash-\($0)",
                    trustStatus: "untrusted",
                    sourcePath: path)
            }
        return CodexHookInstaller(paths: scratch.paths, listHooks: { hooks })
    }

    private func hooksObject(_ scratch: BridgeScratch) throws -> [String: Any] {
        let data = try Data(contentsOf: scratch.paths.codexHooks)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return parsed?["hooks"] as? [String: Any] ?? [:]
    }

    @Test("Install writes the four events and trust follows; uninstall clears both")
    func installRoundTrip() throws {
        let scratch = try self.scratch()
        let installer = installer(scratch)
        try installer.install(endpoint: endpoint)

        let section = try hooksObject(scratch)
        #expect(Set(section.keys) == Set(CodexHookConfiguration.eventNames))
        for (_, value) in section {
            let groups = value as? [[String: Any]] ?? []
            #expect(groups.count == 1)
            let entry = (groups.first?["hooks"] as? [[String: Any]])?.first
            #expect(entry?["type"] as? String == "command")
            #expect(entry?["async"] as? Bool == true)
            let command = entry?["command"] as? String ?? ""
            #expect(command.contains("Bearer sekret"))
            #expect(command.contains("http://127.0.0.1:4242/hook?src=belay&agent=codex"))
        }
        #expect(try installer.isInstalled())

        let config = try String(contentsOf: scratch.paths.codexConfig, encoding: .utf8)
        for event in CodexHookConfiguration.eventNames {
            let snake = CodexHookConfiguration.snakeCase(event)
            #expect(config.contains("[hooks.state.\"\(scratch.paths.codexHooks.path):\(snake):0:0\"]"))
            #expect(config.contains("trusted_hash = \"sha256:hash-\(event)\""))
        }

        try installer.uninstall()
        #expect(try !installer.isInstalled())
        let cleaned = try String(contentsOf: scratch.paths.codexConfig, encoding: .utf8)
        #expect(!cleaned.contains("hooks.state"))
    }

    @Test("A user's own hook keeps its place and its trust")
    func coexistsWithUserHooks() throws {
        let scratch = try self.scratch()
        let theirs = """
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/bin/echo theirs"}]}]}}
            """
        try FileManager.default.createDirectory(
            at: scratch.paths.codexHome, withIntermediateDirectories: true)
        try Data(theirs.utf8).write(to: scratch.paths.codexHooks)
        try Data("model = \"gpt\"\n".utf8).write(to: scratch.paths.codexConfig)

        // Their Stop group sits at index 0, so ours lands at 1 — and the key
        // says so.
        let path = scratch.paths.codexHooks.path
        var listed: [CodexListedHook] = CodexHookConfiguration.eventNames.map {
            let index = $0 == "Stop" ? 1 : 0
            return CodexListedHook(
                key: "\(path):\(CodexHookConfiguration.snakeCase($0)):\(index):0",
                currentHash: "sha256:h", trustStatus: "untrusted", sourcePath: path)
        }
        listed.append(
            CodexListedHook(
                key: "\(path):stop:0:0", currentHash: "sha256:theirs",
                trustStatus: "trusted", sourcePath: path))
        let installer = installer(scratch, listed: listed)
        try installer.install(endpoint: endpoint)

        let stops = try hooksObject(scratch)["Stop"] as? [[String: Any]] ?? []
        #expect(stops.count == 2)
        let first = (stops.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
        #expect(first == "/bin/echo theirs")

        let config = try String(contentsOf: scratch.paths.codexConfig, encoding: .utf8)
        #expect(config.hasPrefix("model = \"gpt\""))
        #expect(config.contains(":stop:1:0"))
        #expect(!config.contains("\"\(path):stop:0:0\""), "their trust is not Belay's to write")

        try installer.uninstall()
        let after = try hooksObject(scratch)["Stop"] as? [[String: Any]] ?? []
        #expect(after.count == 1)
        let cleaned = try String(contentsOf: scratch.paths.codexConfig, encoding: .utf8)
        #expect(cleaned.hasPrefix("model = \"gpt\""))
        #expect(!cleaned.contains(":stop:1:0"))
    }

    @Test("Reinstall refreshes in place instead of stacking a second copy")
    func idempotent() throws {
        let scratch = try self.scratch()
        let installer = installer(scratch)
        try installer.install(endpoint: endpoint)
        try installer.install(endpoint: endpoint)
        let section = try hooksObject(scratch)
        for (_, value) in section {
            #expect((value as? [Any])?.count == 1)
        }
        let config = try String(contentsOf: scratch.paths.codexConfig, encoding: .utf8)
        let occurrences = config.components(separatedBy: ":stop:0:0").count - 1
        #expect(occurrences == 1)
    }

    @Test("Reconcile rewrites a stale port and leaves a current one alone")
    func reconcile() throws {
        let scratch = try self.scratch()
        let installer = installer(scratch)
        #expect(try installer.reconcile(endpoint: endpoint) == .unchanged, "not installed, nothing to heal")
        try installer.install(endpoint: endpoint)
        #expect(try installer.reconcile(endpoint: endpoint) == .unchanged)
        let moved = BridgeEndpoint(port: 5555, token: "sekret")
        guard case .written = try installer.reconcile(endpoint: moved) else {
            Issue.record("expected a rewrite for the moved port")
            return
        }
        let section = try hooksObject(scratch)
        let entry =
            ((section["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        #expect((entry?["command"] as? String ?? "").contains(":5555/"))
    }

    @Test("The trust ledger edit is surgical")
    func configSurgery() {
        let text = """
            model = "gpt"

            [hooks.state."/x/hooks.json:stop:0:0"]
            trusted_hash = "sha256:old"

            [tools]
            web_search = true
            """
        let updated = CodexConfigDocument.addingTrust(
            text, entries: [(key: "/x/hooks.json:stop:0:0", hash: "sha256:new")])
        #expect(updated.contains("sha256:new"))
        #expect(!updated.contains("sha256:old"))
        #expect(updated.contains("web_search = true"))

        let removed = CodexConfigDocument.removingTrust(
            updated, keys: ["/x/hooks.json:stop:0:0"])
        #expect(!removed.contains("hooks.state"))
        #expect(removed.contains("model = \"gpt\""))
        #expect(removed.contains("web_search = true"))
    }

    @Test("The receiver reads the poster off the URL")
    func attribution() {
        #expect(HookReceiver.provider(inPath: "/hook?src=belay&agent=codex") == .codex)
        #expect(HookReceiver.provider(inPath: "/hook?src=belay") == .claudeCode)
        #expect(HookReceiver.provider(inPath: "/hook?src=belay&agent=next") == .claudeCode)
    }

    @Test("The app-server reply parses out of an interleaved stream")
    func replyParsing() {
        let stream = """
            {"id":1,"result":{"userAgent":"x"}}
            {"method":"remoteControl/status/changed","params":{"status":"disabled"}}
            {"id":2,"result":{"data":[{"cwd":"/w","hooks":[{"key":"/h.json:stop:0:0",\
            "currentHash":"sha256:abc","trustStatus":"untrusted","sourcePath":"/h.json"}]}]}}
            """
        let hooks = CodexAppServer.answer(in: Data(stream.utf8))
        #expect(hooks?.count == 1)
        #expect(hooks?.first?.key == "/h.json:stop:0:0")
        #expect(hooks?.first?.currentHash == "sha256:abc")
        #expect(CodexAppServer.answer(in: Data("{\"id\":1,\"result\":{}}".utf8)) == nil)
    }
}
