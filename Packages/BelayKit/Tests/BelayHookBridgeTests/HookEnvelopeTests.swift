import BelayCore
import Foundation
import Testing

@testable import BelayHookBridge

@Suite("Envelope and event mapping")
struct HookEnvelopeTests {
    private func decode(_ json: String) throws -> HookEnvelope {
        try JSONDecoder().decode(HookEnvelope.self, from: Data(json.utf8))
    }

    /// If this ever fails, someone widened the struct that stands between the
    /// user's prompt and the rest of Belay. Read the header of HookEnvelope.swift
    /// before changing the number.
    @Test func decodesExactlyFourFields() throws {
        let envelope = try decode(HookReceiverTests.body(event: "UserPromptSubmit"))
        let fields = Mirror(reflecting: envelope).children.compactMap(\.label)
        #expect(fields.sorted() == ["cwd", "eventName", "sessionID", "transcriptPath"])
        #expect(String(describing: envelope).contains(HookReceiverTests.secret) == false)
    }

    @Test func takesTheWorkspaceNameFromCwd() throws {
        #expect(try decode(HookReceiverTests.body(event: "Stop")).workspace == "hooktest")
        let noCwd = #"{"session_id":"s","hook_event_name":"Stop"}"#
        #expect(try decode(noCwd).workspace == nil)
    }

    @Test func yieldsNothingForAnEventItDoesNotKnow() throws {
        #expect(try decode(HookReceiverTests.body(event: "TeammateIdle")).signal(at: Date()) == nil)
        let noSession = #"{"session_id":"","hook_event_name":"Stop"}"#
        #expect(try decode(noSession).signal(at: Date()) == nil)
    }

    /// The mapping table from docs/DISCOVERY §3.3, spelled out rather than
    /// derived, so a change to it has to be deliberate.
    @Test(arguments: [
        ("SessionStart", SessionActivity.idle),
        ("UserPromptSubmit", .working),
        ("PreToolUse", .working),
        ("PostToolUse", .working),
        ("PostToolBatch", .working),
        ("SubagentStart", .working),
        ("SubagentStop", .working),
        ("PermissionRequest", .awaitingUser),
        ("Elicitation", .awaitingUser),
        ("ElicitationResult", .working),
        ("Notification", .awaitingUser),
        ("Stop", .idle),
        ("StopFailure", .working),
        ("SessionEnd", .ended)
    ])
    func mapsEventsToActivities(name: String, activity: SessionActivity) throws {
        let event = try #require(HookEvent(rawValue: name))
        #expect(event.activity == activity)
    }

    @Test func scopesMatchersToToolEventsOnly() {
        let scoped = HookEvent.allCases.filter(\.isToolScoped).map(\.rawValue)
        #expect(scoped.sorted() == ["PermissionRequest", "PostToolUse", "PreToolUse"])
    }

    @Test func recognisesOnlyItsOwnEntries() {
        let ours = HookConfiguration.entry(for: BridgeScratch.endpoint)
        #expect(HookConfiguration.isBelayEntry(ours))
        #expect(HookConfiguration.belayURL(ours) == BridgeScratch.endpoint.url)

        let lookalikes: [[String: Any]] = [
            ["type": "http", "url": "http://127.0.0.1:51234/hook"],
            ["type": "command", "command": "curl http://127.0.0.1:51234/hook?src=belay"],
            ["type": "http", "url": "http://127.0.0.1:51234/other?src=belay"],
            ["type": "http", "url": "http://127.0.0.1:51234/hook?src=other"]
        ]
        for entry in lookalikes {
            #expect(HookConfiguration.isBelayEntry(entry) == false, "\(entry)")
        }
    }
}

@Suite("HTTP framing")
struct HookRequestParserTests {
    private func head(length: Int, token: String = "abc") -> String {
        """
        POST /hook?src=belay HTTP/1.1\r
        Host: 127.0.0.1\r
        Authorization: Bearer \(token)\r
        Content-Length: \(length)\r
        \r

        """
    }

    @Test func waitsForTheWholeBody() {
        let body = #"{"session_id":"s","hook_event_name":"Stop"}"#
        let full = Data((head(length: body.utf8.count) + body).utf8)

        for cut in stride(from: 1, to: full.count, by: 7) {
            let outcome = HookRequestParser.parse(full.prefix(cut))
            if case .request = outcome { Issue.record("parsed at \(cut) of \(full.count) bytes") }
        }
        guard case .request(let request) = HookRequestParser.parse(full) else {
            Issue.record("the complete request did not parse")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/hook?src=belay")
        #expect(request.authorization == "Bearer abc")
        #expect(String(bytes: request.body, encoding: .utf8) == body)
    }

    @Test func treatsAMissingContentLengthAsAnEmptyBody() {
        let raw = "GET /hook HTTP/1.1\r\nHost: x\r\n\r\n"
        guard case .request(let request) = HookRequestParser.parse(Data(raw.utf8)) else {
            Issue.record("expected a request")
            return
        }
        #expect(request.method == "GET")
        #expect(request.authorization == nil)
        #expect(request.body.isEmpty)
    }

    @Test func rejectsAHeadThatIsNotARequestLine() {
        let raw = "GARBAGE\r\n\r\n"
        guard case .malformed = HookRequestParser.parse(Data(raw.utf8)) else {
            Issue.record("expected malformed")
            return
        }
    }
}
