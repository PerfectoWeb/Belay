import Foundation
import Testing

@testable import BelayHookBridge

/// The port has to survive a restart. An agent posts to whatever address its
/// settings file names, so a new port on every launch is a window where every
/// tool call fails — and during an update, when the outgoing instance is still
/// holding the socket, that window is guaranteed. Reported from the field on
/// 28 Aug 2026: 61716 became 61717 mid-session and the agent's terminal filled
/// with refusals for three hours.
@Suite("The bridge keeps its port")
struct BridgePortTests {
    @Test("A second start comes back on the same port")
    func portSurvivesARestart() async throws {
        let scratch = try BridgeScratch()
        let store = BridgeEndpointStore(paths: scratch.paths)

        let first = HookReceiver(store: store)
        let before = try await first.start()
        await first.stop()

        let second = HookReceiver(store: store)
        let after = try await second.start()
        await second.stop()

        #expect(after.port == before.port, "the remembered port is the one asked for")
    }

    @Test("A port somebody else holds is given up on rather than waited for forever")
    func fallsBackWhenThePortIsTaken() async throws {
        let scratch = try BridgeScratch()
        let store = BridgeEndpointStore(paths: scratch.paths)

        let holder = HookReceiver(store: store)
        let held = try await holder.start()

        // A second receiver against the same record: the port it wants is the
        // one the first is sitting on, so it must end up somewhere else rather
        // than leaving the bridge down.
        let other = HookReceiver(store: store)
        let moved = try await other.start()
        #expect(moved.port != held.port)

        await other.stop()
        await holder.stop()
    }
}
