import Foundation
import Testing

@testable import VigilHookBridge

/// The half of the installer that exists to *not* do things. Every case here
/// asserts the user's file came out of a failure exactly as it went in.
@Suite("Settings safety")
struct SettingsSafetyTests {
    @Test func refusesAFileWithComments() throws {
        let jsonc = """
            {
              // Claude Code tolerates this; JSONSerialization does not.
              "skipWorkflowUsageWarning": true,
            }
            """
        let scratch = try BridgeScratch(settings: jsonc)
        defer { scratch.remove() }

        #expect(throws: BridgeError.settingsNotPlainJSON) {
            try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        }
        #expect(scratch.settingsText() == jsonc)
        #expect(scratch.backupContents().isEmpty)
    }

    @Test func refusesAHooksValueItDoesNotUnderstand() throws {
        let odd = "{\"hooks\": [\"surprise\"]}"
        let scratch = try BridgeScratch(settings: odd)
        defer { scratch.remove() }

        #expect(throws: BridgeError.hooksNotAnObject) {
            try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        }
        #expect(scratch.settingsText() == odd)
    }

    @Test func backsUpTheOriginalBytesBeforeWriting() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }

        let outcome = try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        let backup = try #require(outcome.backup)

        #expect(scratch.backupContents().count == 1)
        let saved = String(bytes: try Data(contentsOf: backup), encoding: .utf8)
        #expect(saved == settingsWithUserHooks)
        #expect(scratch.settingsText() != settingsWithUserHooks)
    }

    @Test func backupFailureAbortsTheWrite() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }
        // A plain file where the backups directory needs to be: creating it
        // fails, and nothing past that point may run.
        try FileManager.default.createDirectory(
            at: scratch.paths.support, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: scratch.paths.backups)

        #expect(throws: BridgeError.self) {
            try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        }
        #expect(scratch.settingsText() == settingsWithUserHooks)
    }

    @Test func writeLeavesNoTemporaryFileBehind() throws {
        let scratch = try BridgeScratch(settings: settingsWithUserHooks)
        defer { scratch.remove() }

        try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        try scratch.installer.uninstall()

        #expect(scratch.claudeDirectoryContents() == ["settings.json"])
    }

    @Test func createsASettingsFileWhenThereIsNone() throws {
        let scratch = try BridgeScratch()
        defer { scratch.remove() }

        try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        #expect(try scratch.installer.isInstalled())
        #expect(scratch.backupContents().isEmpty, "nothing existed, so there was nothing to back up")
    }

    @Test func treatsAnEmptyFileAsAnEmptyObject() throws {
        let scratch = try BridgeScratch(settings: "")
        defer { scratch.remove() }

        try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        #expect(try scratch.settingsObject()["hooks"] != nil)
    }

    /// Runs the whole install against a copy of whatever this machine's real
    /// settings file says, so the common path is exercised against reality and
    /// not only against fixtures. The real file is read, never written.
    @Test func handlesACopyOfTheRealSettingsFile() throws {
        guard let data = try? Data(contentsOf: BridgePaths.real().claudeSettings) else { return }
        let scratch = try BridgeScratch(settings: String(bytes: data, encoding: .utf8) ?? "")
        defer { scratch.remove() }

        let before = try scratch.settingsObject()
        try scratch.installer.install(endpoint: BridgeScratch.endpoint)
        #expect(try scratch.installer.isInstalled())
        try scratch.installer.uninstall()
        #expect(sameJSON(try scratch.settingsObject(), before))
    }

    @Test func bridgeRecordIsOwnerReadableOnly() throws {
        let scratch = try BridgeScratch()
        defer { scratch.remove() }

        let endpoint = try scratch.store.endpoint(port: 4321)
        #expect(scratch.store.load() == endpoint)
        #expect(endpoint.token.count == BridgeEndpointStore.tokenByteCount * 2)

        let attributes = try FileManager.default.attributesOfItem(atPath: scratch.paths.bridgeRecord.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        // A second launch keeps the token so hooks the user consented to still work.
        #expect(try scratch.store.endpoint(port: 9876).token == endpoint.token)
    }

    @Test func tokensAreNotGuessable() {
        let tokens = Set((0..<64).map { _ in BridgeEndpointStore.makeToken() })
        #expect(tokens.count == 64)
    }
}
