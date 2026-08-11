import Foundation
import Testing
import VigilCore

@testable import VigilHookBridge

@Suite("Generic webhook")
struct GenericWebhookTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A one-line curl becomes a generic signal")
    func parsesTheDocumentedForm() throws {
        let signal = try #require(
            GenericWebhook.signal(path: "/hook?provider=generic&session=my-tool&state=working", now: now)
        )
        #expect(signal.provider == .generic)
        #expect(signal.activity == .working)
        #expect(signal.session == SessionID("generic:my-tool"))
        // Never .exact: nothing verifies the caller knows what its agent is
        // doing, and .exact would let it override a real hook.
        #expect(signal.confidence == .inferred)
    }

    @Test(
        "Every documented state word maps",
        arguments: [
            ("working", SessionActivity.working), ("busy", .working), ("start", .working),
            ("idle", .idle), ("stop", .idle), ("done", .idle),
            ("waiting", .awaitingUser), ("blocked", .awaitingUser),
            ("ended", .ended), ("exit", .ended)
        ])
    func mapsStates(word: String, expected: SessionActivity) throws {
        let signal = try #require(
            GenericWebhook.signal(path: "/hook?provider=generic&session=s&state=\(word)", now: now)
        )
        #expect(signal.activity == expected)
    }

    @Test("An unknown state is dropped, never guessed")
    func rejectsUnknownState() {
        #expect(GenericWebhook.signal(path: "/hook?provider=generic&session=s&state=wat", now: now) == nil)
    }

    @Test("A Claude Code hook is not mistaken for a generic one")
    func ignoresTheClaudeCodePath() {
        #expect(GenericWebhook.signal(path: "/hook?src=vigil", now: now) == nil)
        #expect(GenericWebhook.signal(path: "/hook", now: now) == nil)
    }

    @Test("An empty or missing session is rejected")
    func requiresASession() {
        #expect(GenericWebhook.signal(path: "/hook?provider=generic&state=working", now: now) == nil)
        #expect(
            GenericWebhook.signal(path: "/hook?provider=generic&session=&state=working", now: now) == nil
        )
    }

    @Test("The workspace falls back to the session name")
    func workspaceDefaults() throws {
        let named = try #require(
            GenericWebhook.signal(
                path: "/hook?provider=generic&session=s&state=working&workspace=acme",
                now: now
            )
        )
        #expect(named.workspace == "acme")
        let plain = try #require(
            GenericWebhook.signal(path: "/hook?provider=generic&session=s&state=working", now: now)
        )
        #expect(plain.workspace == "s")
    }
}
