import Foundation
import VigilCore
import VigilSupport

/// One live Claude Code process, as described by `~/.claude/sessions/<pid>.json`.
struct AgentProcessRecord: Sendable, Equatable {
    let pid: pid_t
    let session: SessionID
    /// Last path component of the session's `cwd`, for display only.
    let workspace: String?
    /// The per-session name Claude Code writes into the sidecar (`vigil-9a`).
    /// Two sessions in one checkout share a workspace, so this is the only thing
    /// that tells their rows apart. Display only, and only when it is needed.
    let name: String?
    let isAlive: Bool
}

/// Tier C — process presence.
///
/// `docs/03` reaches for `KERN_PROCARGS2`; `docs/DISCOVERY.md` §1.1 found an
/// undocumented `~/.claude/sessions/<pid>.json` that maps pid to sessionId to
/// cwd outright, so we never inspect another process's argument vector — which
/// is both unnecessary and hostile to the sandbox. Liveness is a bare
/// `kill(pid, 0)`.
///
/// This exists only to expire sessions whose process is gone. It never produces
/// `.working`: a process being alive says nothing about whether it is busy.
enum ProcessPresence {
    static func scan(
        directory: URL,
        access: FileAccessProvider,
        isAlive: (pid_t) -> Bool = ProcessPresence.isAlive
    ) -> [AgentProcessRecord] {
        let files =
            (try? access.withAccess(to: directory) { url in
                try FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            }) ?? []

        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                let wire = try? JSONDecoder().decode(SessionFile.self, from: data),
                !wire.sessionId.isEmpty
            else { return nil }
            return AgentProcessRecord(
                pid: wire.pid,
                session: SessionID(wire.sessionId),
                workspace: wire.cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
                name: wire.name.flatMap { $0.isEmpty ? nil : $0 },
                isAlive: isAlive(wire.pid))
        }
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        guard kill(pid, 0) != 0 else { return true }
        // EPERM means the process exists but belongs to someone else. Only ESRCH
        // proves it is gone, and only that may end a session.
        return errno == EPERM
    }
}

private struct SessionFile: Decodable {
    let pid: pid_t
    let sessionId: String
    let cwd: String?
    let name: String?
}
