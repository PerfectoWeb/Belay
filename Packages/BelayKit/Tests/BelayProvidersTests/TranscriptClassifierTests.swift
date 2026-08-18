import BelayCore
import Foundation
import Testing

@testable import BelayProviders

@Suite("TranscriptClassifier")
struct TranscriptClassifierTests {
    private func record(_ type: String, _ stop: String? = nil, at time: String = defaultTime) -> String {
        TranscriptScratch.record(type, stop: stop, at: time)
    }

    private static let defaultTime = TranscriptScratch.sampleTime

    @Test(
        "Every stop_reason maps to a turn state",
        arguments: [
            ("end_turn", SessionActivity.idle),
            ("stop_sequence", .idle),
            ("tool_use", .working),
            ("max_tokens", .working)
        ])
    func stopReasons(reason: String, expected: SessionActivity) {
        #expect(TranscriptClassifier.activity(in: [record("assistant", reason)]) == expected)
    }

    @Test("An assistant record with no stop_reason yet is still mid-turn")
    func streamingAssistant() {
        #expect(TranscriptClassifier.activity(in: [record("assistant")]) == .working)
    }

    @Test("A user record means the turn is in flight")
    func userRecord() {
        #expect(TranscriptClassifier.activity(in: [record("user")]) == .working)
    }

    @Test("Metadata after the turn does not hide the assistant record")
    func metadataTailIsIgnored() {
        let lines = [
            record("assistant", "end_turn"),
            #"{"type":"last-prompt","leafUuid":"x","sessionId":"s"}"#,
            #"{"type":"mode","mode":"default"}"#,
            #"{"type":"custom-title","title":"t"}"#
        ]
        #expect(TranscriptClassifier.activity(in: lines) == .idle)
    }

    @Test("Metadata after a tool call does not end the turn")
    func metadataTailAfterToolUse() {
        let lines = [
            record("assistant", "tool_use"),
            #"{"type":"queue-operation"}"#,
            #"{"type":"ai-title","title":"t"}"#
        ]
        #expect(TranscriptClassifier.activity(in: lines) == .working)
    }

    @Test("The metadata-tail fixture classifies from the last conversational record")
    func metadataTailFixture() {
        #expect(TranscriptClassifier.activity(in: Fixture.lines("metadata-tail")) == .idle)
        #expect(TranscriptClassifier.activity(in: Fixture.lines("normal-session")) == .idle)
        #expect(TranscriptClassifier.activity(in: Fixture.lines("unknown-record")) == .working)
    }

    @Test("File order wins over timestamps, which are not ordered")
    func outOfOrderTimestamps() {
        let lines = [
            record("assistant", "end_turn", at: "2026-08-10T14:28:31.000Z"),
            record("assistant", "tool_use", at: "2026-08-10T14:28:27.000Z")
        ]
        #expect(TranscriptClassifier.activity(in: lines) == .working)
    }

    @Test("Nothing conversational in the delta yields no classification")
    func noConversationalRecord() {
        let lines = [
            #"{"type":"mode","mode":"default"}"#,
            #"{"type":"some-future-record","payload":{"nested":[1,2,3]}}"#
        ]
        #expect(TranscriptClassifier.activity(in: lines) == nil)
    }

    @Test("Unparseable lines are skipped, never fatal")
    func malformedLines() {
        let lines = [
            record("assistant", "tool_use"),
            "not json at all",
            #"{"type":"assistant","message":{"role":"assist"#,
            ""
        ]
        #expect(TranscriptClassifier.activity(in: lines) == .working)
        #expect(TranscriptClassifier.activity(in: ["not json at all"]) == nil)
    }

    @Test("A truncated final record falls back to the previous one")
    func truncatedWriteFixture() {
        #expect(TranscriptClassifier.activity(in: Fixture.lines("truncated-write")) == .working)
    }

    @Test("An API-error record is a turn without an answer, not a finished one")
    func apiErrorRecord() {
        let verdict = TranscriptClassifier.verdict(in: [TranscriptScratch.apiErrorRecord()])
        #expect(verdict == .init(activity: .working, awaitingAssistant: true))
    }

    @Test("The same shape without the error flag stays a finished turn")
    func stopSequenceWithoutErrorFlag() {
        let verdict = TranscriptClassifier.verdict(in: [record("assistant", "stop_sequence")])
        #expect(verdict == .init(activity: .idle, awaitingAssistant: false))
    }

    @Test("Whose move it is: a user record leaves the model owing the reply")
    func awaitingAssistant() {
        #expect(TranscriptClassifier.verdict(in: [record("user")])?.awaitingAssistant == true)
        #expect(
            TranscriptClassifier.verdict(in: [record("assistant", "end_turn")])?.awaitingAssistant
                == false)
        // A running tool is the busy-child sweep's to vouch for, not this flag's.
        #expect(
            TranscriptClassifier.verdict(in: [record("assistant", "tool_use")])?.awaitingAssistant
                == false)
    }

    @Test("A record whose message is a bare string keeps its type")
    func messageOfUnexpectedShape() {
        #expect(TranscriptClassifier.activity(in: [#"{"type":"user","message":"hello"}"#]) == .working)
        #expect(TranscriptClassifier.activity(in: [#"{"type":"assistant","message":42}"#]) == .working)
    }

    @Test("A record with no type at all is not a record")
    func missingType() {
        #expect(TranscriptClassifier.activity(in: [#"{"sessionId":"s","timestamp":"now"}"#]) == nil)
    }
}
