import BelayCore
import BelaySupport
import Foundation

/// What a Copilot CLI event line says about the turn.
///
/// Sessions live at `~/.copilot/session-state/<uuid>/events.jsonl`, one JSON
/// record per line, appended as the turn moves. The records this reads were
/// verified on a live install (copilot-cli 1.0.80, 2026-08-24):
/// `assistant.turn_start` opens a turn, `assistant.turn_end` closes it, and
/// `session.shutdown` is the session going away — explicit markers, the way
/// Codex writes them, with no hook to install. Only `type`, `timestamp` and
/// the session-start `cwd` are decoded; prompts and answers ride in fields
/// this type has no keys for (PRD R9).
enum CopilotEvents {
    struct Verdict: Equatable {
        var activity: SessionActivity
        var turnOpen: Bool
    }

    private struct Record: Decodable {
        let type: String
        let timestamp: String?
        let data: Payload?
    }

    private struct Payload: Decodable {
        let context: Context?
    }

    private struct Context: Decodable {
        let cwd: String?
    }

    static func isEventsFile(_ url: URL) -> Bool {
        url.lastPathComponent == "events.jsonl"
    }

    /// The session's uuid is its directory's name.
    static func sessionID(for url: URL) -> SessionID {
        SessionID(url.deletingLastPathComponent().lastPathComponent)
    }

    static func eventsFile(forSession id: String, under root: URL) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    /// `nil` when the delta carries no turn marker: bytes without a marker
    /// are still evidence of work, but that is the caller's sentence to say.
    static func verdict(in lines: [String]) -> Verdict? {
        var last: Verdict?
        for line in lines {
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8))
            else { continue }
            switch record.type {
            case "assistant.turn_start":
                last = Verdict(activity: .working, turnOpen: true)
            case "assistant.turn_end":
                last = Verdict(activity: .idle, turnOpen: false)
            default:
                break
            }
        }
        return last
    }

    /// Whether the delta closed the whole session, not just a turn.
    static func sawShutdown(in lines: [String]) -> Bool {
        lines.contains { line in
            (try? JSONDecoder().decode(Record.self, from: Data(line.utf8)))?.type
                == "session.shutdown"
        }
    }

    /// The project folder name from a delta's `session.start`, if one passed by.
    static func workspace(in lines: [String]) -> String? {
        for line in lines {
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)),
                record.type == "session.start",
                let cwd = record.data?.context?.cwd, !cwd.isEmpty
            else { continue }
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// `session.start` is the file's first line; for a file adopted past its
    /// beginning the delta never contains it, so the head is read once.
    /// Bounded generously — the line carries context, not a conversation.
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

    /// The newest record clock in a delta — the freshness truth an importer's
    /// touch cannot fake, same rule as the other two watchers.
    static func newestTimestamp(in lines: [String]) -> Date? {
        lines.compactMap { line -> Date? in
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8))
            else { return nil }
            return record.timestamp.flatMap { TranscriptClassifier.date(from: $0) }
        }.max()
    }

    /// Session directories under the root; the uuid is the identity.
    static func sessionIDs(under root: URL, access: FileAccessProvider) -> [String] {
        let contents: [URL]? = try? access.withAccess(to: root) { url in
            (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }
        return (contents ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
    }
}

/// One followed Copilot session. The same shape as `CodexWatch`, for the same
/// marker-driven life.
struct CopilotWatch: Sendable {
    let id: SessionID
    var cursor: TranscriptCursor
    var lastWriteAt: Date
    var workspace: String?
    var reported: SessionActivity?
    var turnOpen = false
    /// Whether the UI has ever heard of this session: only an announced session
    /// gets an announced ending, so a burst of deleted old sessions cannot
    /// become a burst of phantom `.ended` rows.
    var announced = false

    init(id: SessionID, url: URL, lastWriteAt: Date, workspace: String?) {
        self.id = id
        self.cursor = TranscriptCursor(url: url)
        self.lastWriteAt = lastWriteAt
        self.workspace = workspace
    }

    var url: URL { cursor.url }
}
