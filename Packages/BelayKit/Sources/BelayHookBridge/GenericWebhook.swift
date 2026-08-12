import BelayCore
import Foundation

/// The one-line integration for any tool that can run a shell command:
///
///     curl -s -X POST -H "Authorization: Bearer $TOKEN" \
///       "http://127.0.0.1:$PORT/hook?provider=generic&session=my-tool&state=working"
///
/// Port and token come from `~/Library/Application Support/Belay/bridge.json`.
///
/// Signals are `.inferred`, not `.exact`: unlike a Claude Code hook, nothing
/// verifies that the caller knows what its agent is really doing, and an
/// `.exact` signal would be able to override a real one.
enum GenericWebhook {
    static func signal(path: String, now: Date) -> ActivitySignal? {
        guard
            let components = URLComponents(string: "http://127.0.0.1\(path)"),
            let items = components.queryItems,
            items.first(where: { $0.name == "provider" })?.value == "generic",
            let session = items.first(where: { $0.name == "session" })?.value,
            !session.isEmpty,
            let state = items.first(where: { $0.name == "state" })?.value,
            let activity = SessionActivity(webhookState: state)
        else { return nil }

        return ActivitySignal(
            provider: .generic,
            session: SessionID("generic:\(session)"),
            activity: activity,
            workspace: items.first(where: { $0.name == "workspace" })?.value ?? session,
            // The identifier the caller chose doubles as the preset name, so a
            // webhook from `?session=gemini` shows Gemini's mark with no setup.
            kind: session,
            timestamp: now,
            confidence: .inferred
        )
    }
}
