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
    /// Deliberately not "start, stop, start again and compare": a port just
    /// released is usually handed straight back, so that test passes whether or
    /// not the code asks for anything. The first version of this fix did ask,
    /// through `NWParameters.requiredLocalEndpoint`, which a listener ignores –
    /// it came up on a different port every time and the round-trip test still
    /// went green. This one writes a port nobody is near and insists on it.
    @Test("The recorded port is the one bound")
    func bindsTheRecordedPort() async throws {
        let scratch = try BridgeScratch()
        let store = BridgeEndpointStore(paths: scratch.paths)

        // A port that was free a moment ago, and is free again now.
        let probe = HookReceiver(store: store)
        let borrowed = try await probe.start()
        await probe.stop()
        let free = borrowed.port

        // Record a different one, far from whatever the system would hand out.
        let asked = free > 40_000 ? free - 7_000 : free + 7_000
        try store.save(BridgeEndpoint(port: asked, token: borrowed.token))

        let receiver = HookReceiver(store: store)
        let bound = try await receiver.start()
        await receiver.stop()

        #expect(bound.port == asked, "asked for \(asked) and got \(bound.port)")
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
