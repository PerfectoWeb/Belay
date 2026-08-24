import BelayCore
import Foundation

/// The Cline half of the receiver: which lifecycle events Belay registers and
/// what a posted payload is allowed to say.
///
/// Cline's hooks are per-event files, not JSON entries, and its payloads have
/// their own vocabulary — `sessionContext.rootSessionId` where the others say
/// `session_id`. The event itself rides in the URL Belay wrote into the hook
/// script, because the script's file name *is* the event and the payload's
/// `hookName` speaks internal names (`agent_start`) this build would rather
/// not depend on.
enum ClineHookEvent: String, CaseIterable {
    case taskStart = "TaskStart"
    case taskResume = "TaskResume"
    case taskCancel = "TaskCancel"
    case taskComplete = "TaskComplete"
    case taskError = "TaskError"
    case sessionShutdown = "SessionShutdown"

    /// Verified live (2026-08-24): start/resume open a turn; cancel, complete
    /// and error close one; shutdown is the process going away — the abort
    /// path, in practice, since a normal completion never fires it.
    var activity: SessionActivity {
        switch self {
        case .taskStart, .taskResume: return .working
        case .taskCancel, .taskComplete, .taskError: return .idle
        case .sessionShutdown: return .ended
        }
    }
}

/// The three fields Belay takes out of a Cline hook payload. The payload also
/// carries task metadata and, on some events, output text; none of it has a
/// coding key here, so none of it is ever decoded (PRD R9).
struct ClineHookEnvelope: Decodable {
    struct SessionContext: Decodable {
        let rootSessionId: String?
    }

    let sessionContext: SessionContext?
    let workspaceRoots: [String]?

    /// `nil` for an unknown event or a payload without a session: ignored,
    /// never guessed at.
    static func signal(path: String, body: Data, at now: Date) -> ActivitySignal? {
        guard
            let components = URLComponents(string: path),
            let name = components.queryItems?.first(where: { $0.name == "event" })?.value,
            let event = ClineHookEvent(rawValue: name),
            let envelope = try? JSONDecoder().decode(ClineHookEnvelope.self, from: body),
            let session = envelope.sessionContext?.rootSessionId, !session.isEmpty
        else { return nil }
        let workspace = envelope.workspaceRoots?.first.flatMap { root -> String? in
            let name = URL(fileURLWithPath: root).lastPathComponent
            return name.isEmpty ? nil : name
        }
        return ActivitySignal(
            provider: .cline,
            session: SessionID(session),
            activity: event.activity,
            workspace: workspace,
            timestamp: now,
            confidence: .exact)
    }
}

/// The scripts Belay writes into `~/.cline/hooks`, and the rule it uses to
/// recognise its own again later.
enum ClineHookConfiguration {
    /// The first line of every Belay hook script. Recognition is this marker
    /// plus the marked URL — a file without both is somebody else's and is
    /// never overwritten or removed.
    static let marker = "# Installed by Belay; removed from Belay's settings."

    static func url(port: UInt16, event: ClineHookEvent) -> String {
        "http://127.0.0.1:\(port)\(HookConfiguration.path)?src=belay&agent=cline&event=\(event.rawValue)"
    }

    static func fileName(for event: ClineHookEvent) -> String { "\(event.rawValue).sh" }

    /// `exec` so the shell process is the curl process; `-m 5` so a wedged
    /// receiver cannot hold the hook open. Cline dispatches lifecycle hooks
    /// detached and ignores their output, so nothing waits on this.
    static func script(for endpoint: BridgeEndpoint, event: ClineHookEvent) -> String {
        """
        #!/bin/sh
        \(marker)
        exec /usr/bin/curl -s -m 5 -X POST \
        -H "Authorization: Bearer \(endpoint.token)" \
        --data-binary @- "\(url(port: endpoint.port, event: event))" >/dev/null 2>&1

        """
    }

    static func isBelayScript(_ content: String) -> Bool {
        content.contains(marker) && installedURL(in: content) != nil
    }

    /// The URL inside a Belay script, for the port-drift comparison.
    static func installedURL(in content: String) -> String? {
        guard
            let range = content.range(
                of: #"http://127\.0\.0\.1:\d+/hook\?src=belay&agent=cline&event=[A-Za-z]+"#,
                options: .regularExpression)
        else { return nil }
        return String(content[range])
    }
}
