import BelayCore
import BelaySupport
import Foundation

/// Where a live Claude Code session runs, from the sidecar it writes into
/// `~/.claude/sessions`: the process, and the place it was started from.
public struct AgentSeat: Sendable, Equatable {
    public let pid: Int32
    /// "claude-desktop" when the session runs inside the Claude desktop app.
    public let entrypoint: String?

    public init(pid: Int32, entrypoint: String?) {
        self.pid = pid
        self.entrypoint = entrypoint
    }

    public var isClaudeDesktop: Bool { entrypoint == "claude-desktop" }
}

public enum AgentSeats {
    /// The live process of a session. A crash leaves a dead sidecar beside the
    /// live one, so a dead record never wins over a living one.
    public static func find(
        session: SessionID, in directory: URL, access: FileAccessProvider
    ) -> AgentSeat? {
        let records = ProcessPresence.scan(directory: directory, access: access)
            .filter { $0.session == session }
        guard let record = records.first(where: \.isAlive) else { return nil }
        return AgentSeat(pid: record.pid, entrypoint: record.entrypoint)
    }
}
