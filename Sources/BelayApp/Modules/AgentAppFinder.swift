import AppKit
import BelayCore
import BelayProviders
import BelaySupport
import Darwin
import Foundation

/// Which application a session lives in, so that a click on its notification
/// can bring that application forward.
@MainActor
protocol AgentAppFinding {
    /// The bundle identifier of the app, or nil when there is nobody to raise.
    func bundleID(provider: ProviderID, session: SessionID) -> String?
}

/// What the system can say about a process: who its parent is and whether it
/// is an application in the Dock sense.
protocol ProcessAncestry: Sendable {
    /// The bundle identifier of the nearest application at or above `pid`.
    func owningApp(ofPid pid: pid_t) -> String?
}

enum ProcessWalk {
    /// How far up the walk goes. A terminal multiplexer, a shell, an agent and
    /// a wrapper or two is five; a table mangled into a cycle must still end.
    static let maxDepth = 32

    /// Climbs from `pid` through its parents until something is an app.
    static func owner(
        of pid: pid_t, parent: (pid_t) -> pid_t?, app: (pid_t) -> String?
    ) -> String? {
        var current = pid
        var visited: Set<pid_t> = []
        while current > 1, visited.insert(current).inserted, visited.count <= maxDepth {
            if let bundle = app(current) { return bundle }
            guard let next = parent(current) else { return nil }
            current = next
        }
        return nil
    }
}

/// The system's answer: `sysctl` for the pid and ppid of every process, the
/// same table `AgentChildren` reads and nothing more of it, and
/// `NSRunningApplication` for which of them is an app.
struct SystemProcessAncestry: ProcessAncestry {
    func owningApp(ofPid pid: pid_t) -> String? {
        guard let parents = Self.parentTable() else { return nil }
        return ProcessWalk.owner(
            of: pid, parent: { parents[$0] },
            app: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier })
    }

    private static func parentTable() -> [pid_t: pid_t]? {
        var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&request, UInt32(request.count), nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        let stride = MemoryLayout<kinfo_proc>.stride
        let capacity = size / stride + max(64, size / stride / 4)
        let buffer = UnsafeMutablePointer<kinfo_proc>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        size = capacity * stride
        guard sysctl(&request, UInt32(request.count), buffer, &size, nil, 0) == 0 else { return nil }
        var parents: [pid_t: pid_t] = [:]
        for index in 0..<(size / stride) {
            let process = buffer[index]
            parents[process.kp_proc.p_pid] = process.kp_eproc.e_ppid
        }
        return parents
    }
}

@MainActor
struct AgentAppFinder: AgentAppFinding {
    static let claudeDesktop = "com.anthropic.claudefordesktop"
    /// The Codex agent lives in ChatGPT.app, whose bundle identifier says so.
    static let codexApp = "com.openai.codex"

    /// Where Claude Code writes `<pid>.json`, one folder per watched profile.
    var sessionFolders: () -> [URL]
    var access: FileAccessProvider
    var ancestry: ProcessAncestry
    var isRunning: (String) -> Bool

    init(
        sessionFolders: @escaping () -> [URL] = { AgentAppFinder.watchedSessionFolders() },
        access: FileAccessProvider = ClaudeAccess.provider,
        ancestry: ProcessAncestry = SystemProcessAncestry(),
        isRunning: @escaping (String) -> Bool = {
            !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
        }
    ) {
        self.sessionFolders = sessionFolders
        self.access = access
        self.ancestry = ancestry
        self.isRunning = isRunning
    }

    static func watchedSessionFolders() -> [URL] {
        let extra = BuiltInRootsStore().roots(for: .claudeCode)
        return ([ClaudeAccess.folder] + extra).map {
            $0.appendingPathComponent("sessions", isDirectory: true)
        }
    }

    func bundleID(provider: ProviderID, session: SessionID) -> String? {
        switch provider {
        case .claudeCode: return claudeHome(of: session)
        // No pid registry for Codex: its agent is the app, or nothing.
        case .codex: return isRunning(Self.codexApp) ? Self.codexApp : nil
        default: return nil
        }
    }

    /// The desktop app when the sidecar says the session runs inside it,
    /// otherwise whatever application owns the session's process.
    private func claudeHome(of session: SessionID) -> String? {
        for folder in sessionFolders() {
            guard let seat = AgentSeats.find(session: session, in: folder, access: access) else {
                continue
            }
            if seat.isClaudeDesktop { return Self.claudeDesktop }
            return ancestry.owningApp(ofPid: seat.pid)
        }
        return nil
    }
}
