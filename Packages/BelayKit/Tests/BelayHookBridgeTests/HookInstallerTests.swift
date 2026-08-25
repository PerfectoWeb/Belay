import Foundation
import Testing

@testable import BelayHookBridge

@Suite("Hook installer")
struct HookInstallerTests {
    @Test func writesEveryEventIntoAFileWithNoHooksKey() throws {
        let scratch = try BridgeScratch(settings: "{\n  \"skipWorkflowUsageWarning\": true\n}\n")
        defer { scratch.remove() }

        let outcome = try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        #expect(outcome != .unchanged)

        let object = try scratch.settingsObject()
        #expect(object["skipWorkflowUsageWarning"] as? Bool == true)
        let section = try #require(object["hooks"] as? [String: Any])
        #expect(section.count == HookEvent.allCases.count)

        let group = try #require(scratch.hooks(for: .stop).first)
        let entry = try #require((group["hooks"] as? [[String: Any]])?.first)
        #expect(entry["type"] as? String == "http")
        #expect(entry["async"] as? Bool == true)
        #expect(entry["timeout"] as? Int == 5)
        #expect(entry["url"] as? String == "http://127.0.0.1:51234/hook?src=belay")
        #expect((entry["headers"] as? [String: String])?["Authorization"] == "Bearer token-alpha")
    }

    @Test func writesMatcherOnlyOnToolScopedEvents() throws {
        let scratch = try BridgeScratch(settings: "{}")
        defer { scratch.remove() }
        try scratch.installer.install(endpoint: BridgeScratch.endpoint)

        for event in HookEvent.allCases {
            let ours = try #require(scratch.hooks(for: event).last)
            #expect(ours.keys.contains("matcher") == event.isToolScoped)
            if event.isToolScoped { #expect(ours["matcher"] as? String == "*") }
        }
    }

    @Test func keepsHooksTheUserAlreadyHad() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }
        try scratch.installer.install(endpoint: BridgeScratch.endpoint)

        let preToolUse = try scratch.hooks(for: .preToolUse)
        #expect(preToolUse.count == 2)
        #expect(preToolUse.first?["matcher"] as? String == "Bash")

        let stop = try scratch.hooks(for: .stop)
        #expect(stop.count == 2)
        let theirs = try #require((stop.first?["hooks"] as? [[String: Any]])?.first)
        #expect(theirs["url"] as? String == "http://127.0.0.1:9999/hook")

        // An event Belay does not register must come through untouched.
        let section = try #require(try scratch.settingsObject()["hooks"] as? [String: Any])
        #expect(section["TeammateIdle"] != nil)
    }

    @Test func uninstallRemovesOnlyMarkedEntries() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }
        try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        try scratch.installer.uninstall()

        let stop = try scratch.hooks(for: .stop)
        #expect(stop.count == 1)
        // Same host, same path, no marker: the user's, and it stays.
        let theirs = try #require((stop.first?["hooks"] as? [[String: Any]])?.first)
        #expect(theirs["url"] as? String == "http://127.0.0.1:9999/hook")
        #expect(try scratch.hooks(for: .sessionEnd).isEmpty)
    }

    @Test func roundTripRestoresTheOriginal() throws {
        for original in ["{\n  \"skipWorkflowUsageWarning\": true\n}\n", settingsWithUserHooks] {
            let scratch = try BridgeScratch(settings: original)
            defer { scratch.remove() }
            let before = try scratch.settingsObject()

            try scratch.installer.install(endpoint: BridgeScratch.endpoint)
            try scratch.installer.uninstall()

            #expect(sameJSON(try scratch.settingsObject(), before))
        }
    }

    @Test func installIsIdempotent() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }

        try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        let after = try scratch.settingsObject()
        let backups = scratch.backupContents()
        let second = try scratch.installer.install(endpoint: BridgeScratch.endpoint)

        #expect(second == .unchanged)
        #expect(sameJSON(try scratch.settingsObject(), after))
        #expect(try scratch.hooks(for: .preToolUse).count == 2)
        #expect(scratch.backupContents() == backups, "a no-op install must not churn backups")
    }

    @Test func uninstallOnACleanFileWritesNothing() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }

        #expect(try scratch.installer.uninstall() == .unchanged)
        #expect(scratch.settingsText() == settingsWithUserHooks)
    }

    @Test func selfHealRewritesAStalePort() throws {
        let scratch = try BridgeScratch(settings: "{}")
        defer { scratch.remove() }
        try scratch.installer.install(endpoint: BridgeScratch.endpoint)

        #expect(try scratch.installer.reconcile(endpoint: BridgeScratch.movedEndpoint) != .unchanged)
        let urls = SettingsMerge.installedURLs(in: try scratch.settingsObject())
        #expect(urls.count == HookEvent.allCases.count)
        #expect(urls.allSatisfy { $0 == BridgeScratch.movedEndpoint.url })
        #expect(try scratch.installer.reconcile(endpoint: BridgeScratch.movedEndpoint) == .unchanged)
    }

    @Test func selfHealNeverInstallsUnasked() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }

        #expect(try scratch.installer.reconcile(endpoint: BridgeScratch.endpoint) == .unchanged)
        #expect(try scratch.installer.isInstalled() == false)
        #expect(scratch.settingsText() == settingsWithUserHooks)
    }

    @Test func previewIsExactlyWhatGetsWritten() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }

        let preview = try scratch.installer.preview(endpoint: BridgeScratch.endpoint)
        #expect(preview.isChange)
        #expect(scratch.settingsText() == settingsWithUserHooks, "preview must not write")

        try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        #expect(scratch.settingsText() == preview.proposed)
    }

    @Test func snippetIsPlainJSONTheUserCanPaste() throws {
        let snippet = try HookInstaller.snippet(for: BridgeScratch.endpoint)
        let parsed = try JSONSerialization.jsonObject(with: Data(snippet.utf8))
        let section = try #require((parsed as? [String: Any])?["hooks"] as? [String: Any])
        #expect(section.count == HookEvent.allCases.count)
        #expect(snippet.contains("http://127.0.0.1:51234/hook?src=belay"))
    }

    /// A user value of the wrong shape under a registered event key must be
    /// refused, not overwritten: the merge is pure, so throwing leaves the file
    /// untouched rather than silently destroying `"Stop": "my-own-note"`.
    @Test func refusesToOverwriteAWrongShapedForeignEventValue() {
        let settings: [String: Any] = ["hooks": ["Stop": "my-own-note"]]
        #expect(throws: BridgeError.hooksNotAnObject) {
            _ = try SettingsMerge.merged(settings, endpoint: BridgeScratch.endpoint)
        }
    }
}

@Suite("Bridge endpoint store")
struct BridgeEndpointStoreTests {
    /// The save used to remove-then-create, leaving a window with no file: a
    /// concurrent load landing in it saw nothing and `endpoint(port:)` minted a
    /// fresh token, rotating the credential under every consented hook. An
    /// atomic replace closes the window — the token never changes under load.
    @Test func concurrentSavesNeverRotateTheToken() async throws {
        let scratch = try BridgeScratch()
        defer { scratch.remove() }
        let store = scratch.store
        let token = try store.endpoint(port: 5000).token

        await withTaskGroup(of: String?.self) { group in
            for offset in 0..<40 {
                group.addTask { try? store.endpoint(port: UInt16(6000 + offset)).token }
                group.addTask { store.load()?.token }
            }
            for await seen in group where seen != nil {
                #expect(seen == token, "the token must never rotate under concurrent access")
            }
        }
        #expect(store.load()?.token == token)
    }
}
