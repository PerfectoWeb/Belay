import BelayCore
import BelaySupport
import Foundation

/// What a Codex rollout line says about the turn.
///
/// Rollouts live at `~/.codex/sessions/YYYY/MM/DD/rollout-<stamp>-<uuid>.jsonl`,
/// one JSON record per line. The two records this reads were verified on a live
/// install (codex-cli 0.148) and match the wire names in codex-rs
/// `protocol.rs`: an `event_msg` whose payload type is `task_started` opens a
/// turn, `task_complete` closes it — `turn_started`/`turn_completed` are the
/// CLI's own aliases for the same pair — and `session_meta` carries the
/// session's `cwd`. Only those fields are decoded; the prompt and the model's
/// output stay unread (PRD R9). Unknown records are ignored, not errors: the
/// format is Codex's to change.
enum CodexRollout {
    struct Verdict: Equatable {
        var activity: SessionActivity
        /// A turn was opened and not closed by the end of the delta: the model
        /// still owes an answer, which grants the longer idle horizon. Mirrors
        /// `TranscriptClassifier.Verdict.awaitingAssistant`.
        var turnOpen: Bool
    }

    private struct Record: Decodable {
        let type: String
        let payload: Payload?

        struct Payload: Decodable {
            let type: String?
            let cwd: String?
        }
    }

    private static let opens: Set<String> = ["task_started", "turn_started"]
    private static let closes: Set<String> = ["task_complete", "turn_completed", "turn_complete"]

    static func isRollout(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-")
    }

    /// The thread UUID from the filename. The stem is
    /// `rollout-<timestamp>-<uuid>`; the uuid alone is the identity, and it is
    /// also what keeps the log's 8-character prefix meaningful — the full stem
    /// would print every session as "rollout-".
    static func sessionID(for url: URL) -> SessionID {
        let stem = url.deletingPathExtension().lastPathComponent
        // 36 = a canonical UUID; anything shaped differently keeps the stem.
        let tail = stem.suffix(36)
        return SessionID(
            tail.count == 36 && tail.filter { $0 == "-" }.count == 4
                ? String(tail) : stem)
    }

    /// `nil` when the delta carries no turn marker: bytes without a marker are
    /// still evidence of work, but that is the caller's sentence to say.
    static func verdict(in lines: [String]) -> Verdict? {
        var last: Verdict?
        for line in lines {
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)),
                record.type == "event_msg", let kind = record.payload?.type
            else { continue }
            if opens.contains(kind) {
                last = Verdict(activity: .working, turnOpen: true)
            } else if closes.contains(kind) {
                last = Verdict(activity: .idle, turnOpen: false)
            }
        }
        return last
    }

    /// The newest record clock in a delta. Every rollout line carries a
    /// top-level `timestamp` from the CLI's own clock — the truth about
    /// freshness where the file's mtime is any toucher's to bump. Codex
    /// Desktop's session importer, for one, writes rollouts for other agents'
    /// old conversations.
    static func newestTimestamp(in lines: [String]) -> Date? {
        struct Stamp: Decodable { let timestamp: String? }
        return lines.compactMap { line -> Date? in
            guard let stamp = try? JSONDecoder().decode(Stamp.self, from: Data(line.utf8)) else {
                return nil
            }
            return stamp.timestamp.flatMap { TranscriptClassifier.date(from: $0) }
        }.max()
    }

    /// The project folder name from a delta's `session_meta`, if one passed by.
    static func workspace(in lines: [String]) -> String? {
        for line in lines {
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)),
                record.type == "session_meta", let cwd = record.payload?.cwd, !cwd.isEmpty
            else { continue }
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// `session_meta` is the rollout's first line. For a file adopted past its
    /// beginning the delta never contains it, so the line is read once from the
    /// head of the file. It is not a short line — `base_instructions` rides in
    /// the same record, 18 KB on a live install — so the read continues until
    /// a newline arrives, bounded at 256 KB. Only the `cwd` field is decoded.
    static func workspace(atHeadOf url: URL, access: FileAccessProvider) -> String? {
        let head: Data?? = try? access.withAccess(to: url) { url -> Data? in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            var collected = Data()
            while collected.count < 256 * 1024 {
                guard let chunk = try? handle.read(upToCount: 32 * 1024), !chunk.isEmpty else {
                    break
                }
                collected.append(chunk)
                if chunk.contains(0x0A) { break }
            }
            return collected
        }
        guard case .some(.some(let data)) = head else { return nil }
        let line = data.prefix(while: { $0 != 0x0A })
        guard let first = String(bytes: line, encoding: .utf8) else { return nil }
        return workspace(in: [first])
    }

    /// Every rollout under the sessions root, which is `YYYY/MM/DD/*.jsonl` —
    /// enumerated against that known layout rather than recursed blindly, for
    /// the same reason `TranscriptWatch.transcripts` is. Compressed history
    /// (`.jsonl.zst`) fails the extension check and is skipped by design: a
    /// live session is always plain JSONL.
    static func rollouts(under root: URL, access: FileAccessProvider) -> [URL] {
        let years = (try? access.withAccess(to: root) { contents(of: $0) }) ?? []
        return
            years
            .flatMap { contents(of: $0) }  // months
            .flatMap { contents(of: $0) }  // days
            .flatMap { contents(of: $0) }  // rollouts
            .filter { isRollout($0) }
    }

    private static func contents(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }
}
