import BelayCore
import Foundation

/// Turns a transcript delta into an activity.
///
/// `docs/03` says "classify the tail record". On this machine that is wrong:
/// Claude Code appends metadata (`last-prompt`, `mode`, `custom-title`, …)
/// *after* a turn ends, and it was the literal last line in 12 of 13 finished
/// sessions. Records are not ordered by timestamp either. So we scan backwards
/// for the last record that is actually part of the conversation and classify
/// that. See `docs/DISCOVERY.md` §2.1.
enum TranscriptClassifier {
    /// What the tail record says, and whose move it is.
    ///
    /// `awaitingAssistant` is the narrow claim that the next record can only
    /// come from the API. That is the one silence with a legitimate reason to
    /// run long: a 529 retry loop writes nothing for minutes — 3½ to 5½ on this
    /// machine's transcripts — and gives up into a single error record. The
    /// idle sweep grants that silence a longer horizon. A trailing `tool_use`
    /// stays out: a running tool has the busy-child sweep speaking for it.
    struct Verdict: Equatable {
        var activity: SessionActivity
        var awaitingAssistant: Bool
    }

    /// `nil` means the delta said nothing about the turn — the caller falls back
    /// to "the file grew, so something is happening".
    static func activity(in lines: [String]) -> SessionActivity? {
        verdict(in: lines)?.activity
    }

    /// Tokens the delta's records account for: `usage.input_tokens` plus
    /// `usage.output_tokens`, summed. Cache counters are deliberately left
    /// out — a cache read is the model rereading its own context, and adding
    /// it makes an afternoon read as a billion tokens. Numbers only; the R9
    /// boundary is untouched.
    static func tokens(in lines: [String]) -> Int {
        // The substring check is the budget: only assistant records carry a
        // usage block, and running the full decoder over every user and
        // metadata line doubled the provider's CPU on a busy transcript —
        // caught by the QA pass at 2% where the budget says 1.
        lines.lazy
            .filter { $0.contains("\"usage\"") }
            .compactMap { TranscriptRecord(jsonLine: $0)?.tokens }
            .reduce(0, +)
    }

    /// The newest record clock in the delta, or nil when no record carries one.
    ///
    /// What "this file just appeared" gets checked against. A file's mtime is
    /// the file system's word and third parties bump it — Codex's session
    /// importer swept `~/.claude` once and thirty month-old subagents rose as
    /// Working rows in a second — but the records' own timestamps cannot be
    /// touched from outside.
    static func newestTimestamp(in lines: [String]) -> Date? {
        lines.compactMap { TranscriptRecord(jsonLine: $0)?.timestamp }.max()
    }

    /// RFC 3339 with or without fractional seconds — the clock format both
    /// CLIs write. Here so the Codex rollout reader can parse the same way.
    static func date(from string: String) -> Date? {
        TranscriptRecord.date(from: string)
    }

    static func verdict(in lines: [String]) -> Verdict? {
        for line in lines.reversed() {
            guard let record = TranscriptRecord(jsonLine: line) else { continue }
            switch record.kind {
            case .assistant:
                // The CLI writes a synthetic assistant record when a request
                // fails ("API Error: 529 Overloaded…"), with a stop_reason that
                // would read as a finished turn. It is the opposite: the turn
                // still has no answer, and the CLI is retrying or the user is
                // about to. docs/DISCOVERY §2.3.
                guard !record.isAPIError else {
                    return Verdict(activity: .working, awaitingAssistant: true)
                }
                return Verdict(
                    activity: activity(forStopReason: record.stopReason),
                    awaitingAssistant: false)
            case .user:
                // Either a tool result coming back or a prompt going out; both
                // mean the turn is in flight and the model owes the next record.
                return Verdict(activity: .working, awaitingAssistant: true)
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
    /// `usage.input_tokens + usage.output_tokens`, when the record carries a
    /// usage block. Numbers beside the message, never the message.
    let tokens: Int?
    /// Top-level flag on the CLI's synthetic error records. A boolean beside
    /// the message, so reading it stays inside the R9 boundary.
    let isAPIError: Bool
    /// When the record was written, by the CLI's own clock.
    let timestamp: Date?

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
        tokens = wire.message?.usage.map { ($0.inputTokens ?? 0) + ($0.outputTokens ?? 0) }
        isAPIError = wire.isApiErrorMessage ?? false
        timestamp = wire.timestamp.flatMap(TranscriptRecord.date(from:))
    }

    /// The CLI writes RFC 3339 with milliseconds; be liberal about both
    /// forms. Formatters are made per call because `ISO8601DateFormatter` is
    /// not `Sendable`; the adopt path parses a handful of lines, not a feed.
    /// Internal because Codex stamps its rollout lines the same way.
    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

private struct Wire: Decodable {
    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    struct Message: Decodable {
        let stopReason: String?
        let usage: Usage?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            stopReason = try? container.decodeIfPresent(String.self, forKey: .stopReason)
            usage = try? container.decodeIfPresent(Usage.self, forKey: .usage)
        }

        private enum CodingKeys: String, CodingKey {
            case stopReason = "stop_reason"
            case usage
        }
    }

    let type: String
    let message: Message?
    let isApiErrorMessage: Bool?
    let timestamp: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        // `message` is an object on conversational records but a bare string on
        // some metadata ones; a mistyped field must lose the field, not the
        // record, or an unknown shape becomes a missing signal.
        message = try? container.decodeIfPresent(Message.self, forKey: .message)
        isApiErrorMessage = try? container.decodeIfPresent(Bool.self, forKey: .isApiErrorMessage)
        timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case isApiErrorMessage
        case timestamp
    }
}
