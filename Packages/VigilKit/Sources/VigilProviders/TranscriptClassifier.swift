import Foundation
import VigilCore

/// Turns a transcript delta into an activity.
///
/// `docs/03` says "classify the tail record". On this machine that is wrong:
/// Claude Code appends metadata (`last-prompt`, `mode`, `custom-title`, …)
/// *after* a turn ends, and it was the literal last line in 12 of 13 finished
/// sessions. Records are not ordered by timestamp either. So we scan backwards
/// for the last record that is actually part of the conversation and classify
/// that. See `docs/DISCOVERY.md` §2.1.
enum TranscriptClassifier {
    /// `nil` means the delta said nothing about the turn — the caller falls back
    /// to "the file grew, so something is happening".
    static func activity(in lines: [String]) -> SessionActivity? {
        for line in lines.reversed() {
            guard let record = TranscriptRecord(jsonLine: line) else { continue }
            switch record.kind {
            case .assistant:
                return activity(forStopReason: record.stopReason)
            case .user:
                // Either a tool result coming back or a prompt going out; both
                // mean the turn is in flight.
                return .working
            case .metadata:
                continue
            }
        }
        return nil
    }

    private static func activity(forStopReason reason: String?) -> SessionActivity {
        switch reason {
        case "end_turn", "stop_sequence":
            return .idle
        default:
            // `tool_use`, a record still being streamed with no reason yet, and
            // any reason a future CLI invents. Guessing `.idle` here would cut a
            // live turn short; guessing `.working` costs at most one
            // `inferredIdleAfter` window, which the sweep closes anyway.
            return .working
        }
    }
}

/// The only two fields classification needs.
///
/// PRD **R9**: message content, prompt text and paths inside user projects are
/// never decoded, logged or retained. That is enforced by the shape of this type
/// rather than by remembering not to touch them.
private struct TranscriptRecord {
    enum Kind {
        case assistant
        case user
        case metadata
    }

    let kind: Kind
    let stopReason: String?

    init?(jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
            let wire = try? JSONDecoder().decode(Wire.self, from: data)
        else { return nil }
        switch wire.type {
        case "assistant": kind = .assistant
        case "user": kind = .user
        default: kind = .metadata
        }
        stopReason = wire.message?.stopReason
    }
}

private struct Wire: Decodable {
    struct Message: Decodable {
        let stopReason: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stopReason = try? container.decodeIfPresent(String.self, forKey: .stopReason)
        }

        private enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
        }
    }

    let type: String
    let message: Message?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        // `message` is an object on conversational records but a bare string on
        // some metadata ones; a mistyped field must lose the field, not the
        // record, or an unknown shape becomes a missing signal.
        message = try? container.decodeIfPresent(Message.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case message
    }
}
