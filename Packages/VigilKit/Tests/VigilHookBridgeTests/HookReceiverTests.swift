import Foundation
import Testing
import VigilCore

@testable import VigilHookBridge

@Suite("Hook receiver")
struct HookReceiverTests {
    /// The `UserPromptSubmit` body captured in docs/DISCOVERY §3.2, prompt and
    /// all. Nothing in Vigil may ever be able to repeat what it says.
    static let secret = "my aws root password is hunter2 and the merger closes friday"

    static func body(
        event: String,
        session: String = "c39e2033-0022-4c90-b847-1c93117f8152",
        cwd: String = "/private/tmp/hooktest"
    ) -> String {
        """
        {"session_id":"\(session)",
         "transcript_path":"/Users/davx/.claude/projects/-private-tmp-hooktest/\(session).jsonl",
         "cwd":"\(cwd)","permission_mode":"default","hook_event_name":"\(event)",
         "prompt":"\(secret)"}
        """
    }

    @Test func acceptsARealCapturedEnvelope() async throws {
        try await withReceiver { endpoint, collector in
            let status = try await post(
                Self.body(event: "UserPromptSubmit"), to: endpoint,
                token: endpoint.token)
            #expect(status == 204)

            let signals = await collector.wait(for: 1)
            let signal = try #require(signals.first)
            #expect(signal.provider == .claudeCode)
            #expect(signal.session == SessionID("c39e2033-0022-4c90-b847-1c93117f8152"))
            #expect(signal.activity == .working)
            #expect(signal.workspace == "hooktest")
            #expect(signal.confidence == .exact)
        }
    }

    @Test func rejectsAWrongOrMissingToken() async throws {
        try await withReceiver { endpoint, collector in
            let wrong = try await post(Self.body(event: "Stop"), to: endpoint, token: "not-the-token")
            let none = try await post(Self.body(event: "Stop"), to: endpoint, token: nil)
            #expect(wrong == 401)
            #expect(none == 401)

            await collector.settle()
            #expect(await collector.all.isEmpty, "an unauthenticated body must not even be parsed")
        }
    }

    @Test func answersAMalformedBodyWithoutEmittingAnything() async throws {
        try await withReceiver { endpoint, collector in
            for body in ["not json at all", "", "{\"hook_event_name\":\"Stop\"}", "[]"] {
                let status = try await post(body, to: endpoint, token: endpoint.token)
                #expect(status == 204, "a body Vigil cannot use is still a body it must answer")
            }

            await collector.settle()
            #expect(await collector.all.isEmpty)
        }
    }

    @Test func ignoresEventsItDoesNotRegister() async throws {
        try await withReceiver { endpoint, collector in
            let status = try await post(
                Self.body(event: "TeammateIdle"), to: endpoint,
                token: endpoint.token)
            #expect(status == 204)
            await collector.settle()
            #expect(await collector.all.isEmpty)
        }
    }

    @Test func mapsEveryRegisteredEventToItsActivity() async throws {
        try await withReceiver { endpoint, collector in
            for event in HookEvent.allCases {
                let status = try await post(
                    Self.body(event: event.rawValue), to: endpoint,
                    token: endpoint.token)
                #expect(status == 204)
            }
            let signals = await collector.wait(for: HookEvent.allCases.count)
            #expect(signals.count == HookEvent.allCases.count)
            for (event, signal) in zip(HookEvent.allCases, signals) {
                #expect(signal.activity == event.activity, "\(event.rawValue)")
            }
        }
    }

    /// The privacy line of the whole module: a body carrying the user's prompt
    /// produces a signal, and the prompt appears in nothing Vigil keeps.
    @Test func neverEmitsOrKeepsThePrompt() async throws {
        let scratch = try BridgeScratch()
        defer { scratch.remove() }
        let receiver = HookReceiver(store: scratch.store)
        let endpoint = try await receiver.start()
        let collector = SignalCollector()
        await collector.start(on: await receiver.signals)

        _ = try await post(Self.body(event: "UserPromptSubmit"), to: endpoint, token: endpoint.token)
        let signals = await collector.wait(for: 1)
        await collector.stop()
        await receiver.stop()

        #expect(signals.count == 1)
        for signal in signals {
            #expect(String(describing: signal).contains(Self.secret) == false)
        }
        let record = try Data(contentsOf: scratch.paths.bridgeRecord)
        let recorded = String(bytes: record, encoding: .utf8) ?? ""
        #expect(recorded.contains(Self.secret) == false)
        #expect(scratch.claudeDirectoryContents().isEmpty, "the receiver writes nothing to ~/.claude")
    }

    @Test func releasesThePortOnStop() async throws {
        let scratch = try BridgeScratch()
        defer { scratch.remove() }
        let receiver = HookReceiver(store: scratch.store)
        let endpoint = try await receiver.start()

        #expect(LoopbackProbe.accepts(port: endpoint.port))
        await receiver.stop()
        #expect(await receiver.endpoint == nil)
        #expect(LoopbackProbe.accepts(port: endpoint.port) == false)
    }

    @Test func startsAndStopsSymmetrically() async throws {
        let scratch = try BridgeScratch()
        defer { scratch.remove() }
        let receiver = HookReceiver(store: scratch.store)

        let first = try await receiver.start()
        #expect(try await receiver.start() == first, "a second start must not open a second listener")
        await receiver.stop()

        let second = try await receiver.start()
        #expect(second.token == first.token, "the token outlives the port")
        #expect(LoopbackProbe.accepts(port: second.port))
        await receiver.stop()
        #expect(LoopbackProbe.accepts(port: second.port) == false)
    }

    @Test func listensOnLoopbackOnly() async throws {
        try await withReceiver { endpoint, _ in
            let listening = LoopbackProbe.listeningAddresses(port: endpoint.port)
            guard !listening.isEmpty else { return }
            #expect(listening.contains("127.0.0.1:\(endpoint.port)"))
            #expect(listening.contains("*:\(endpoint.port)") == false)
        }
    }

    // MARK: - Harness

    private func withReceiver(
        _ body: (BridgeEndpoint, SignalCollector) async throws -> Void
    ) async throws {
        let scratch = try BridgeScratch()
        let receiver = HookReceiver(store: scratch.store)
        let endpoint = try await receiver.start()
        let collector = SignalCollector()
        await collector.start(on: await receiver.signals)

        let result: Result<Void, Error>
        do {
            try await body(endpoint, collector)
            result = .success(())
        } catch {
            result = .failure(error)
        }
        await collector.stop()
        await receiver.stop()
        scratch.remove()
        try result.get()
    }

    @discardableResult
    private func post(
        _ body: String, to endpoint: BridgeEndpoint, token: String?, path: String = "/hook?src=vigil"
    ) async throws -> Int {
        let url = try #require(URL(string: "http://127.0.0.1:\(endpoint.port)\(path)"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.timeoutInterval = 5
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let configuration = URLSessionConfiguration.ephemeral
        // A VPN was live on the machine this was written on; loopback must not
        // be allowed to wander off through a proxy.
        configuration.connectionProxyDictionary = [:]
        let (_, response) = try await URLSession(configuration: configuration).data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
