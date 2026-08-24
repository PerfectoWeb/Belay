import Foundation

/// The JSON Belay writes into `~/.codex/hooks.json`, and the rule it uses to
/// recognise its own entries again later.
///
/// Codex copied Claude Code's hooks wholesale — same section shape, same
/// payload fields — with one difference that matters here: an entry's
/// `command` is a shell-split string, there is no `http` type. So the bridge
/// is one `curl` to the same loopback receiver, with the same bearer token in
/// a header and the ownership marker in the URL. Verified live against
/// codex-cli 0.148.0-alpha.21 (scratch spike, 2026-08-24).
enum CodexHookConfiguration {
    /// The verified set. `UserPromptSubmit` opens the turn, `Stop` closes it,
    /// the session pair brackets the process. Tool events exist in the
    /// binary's vocabulary but are unverified on a live turn, and the rollout
    /// watcher already carries the mid-turn hold — so they are not registered.
    static let eventNames = ["SessionStart", "UserPromptSubmit", "Stop", "SessionEnd"]

    static let markerQuery = "src=belay&agent=codex"

    static func url(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(HookConfiguration.path)?\(markerQuery)"
    }

    /// One line of shell. Quoted where the shell-split needs it (the header
    /// carries a space); `-m 5` so a wedged receiver cannot hold the hook
    /// open, though `async` means nobody is waiting anyway.
    static func command(for endpoint: BridgeEndpoint) -> String {
        "/usr/bin/curl -s -m 5 -X POST"
            + " -H \"Authorization: Bearer \(endpoint.token)\""
            + " --data-binary @- \"\(url(port: endpoint.port))\""
    }

    static func entry(for endpoint: BridgeEndpoint) -> [String: Any] {
        [
            "type": "command",
            "command": command(for: endpoint),
            // Fire and forget, exactly like the Claude hooks: Belay does not
            // get to slow the user's agent down (invariant 5).
            "async": true,
            "timeout": HookConfiguration.timeoutSeconds
        ]
    }

    /// The URL inside a Belay-owned entry, or `nil` if the entry is someone
    /// else's. The marker rides in the command string; the URL is extracted
    /// so self-heal can compare it against the receiver's current port.
    static func belayURL(_ value: Any) -> String? {
        guard let entry = value as? [String: Any],
            entry["type"] as? String == "command",
            let command = entry["command"] as? String,
            let range = command.range(
                of: #"http://127\.0\.0\.1:\d+/hook\?src=belay&agent=codex"#,
                options: .regularExpression)
        else { return nil }
        return String(command[range])
    }

    /// `hooks.state` keys spell events in snake_case; the file spells them in
    /// CamelCase. This is the one place that knows both spellings.
    static func snakeCase(_ event: String) -> String {
        var out = ""
        for character in event {
            if character.isUppercase {
                if !out.isEmpty { out.append("_") }
                out.append(character.lowercased())
            } else {
                out.append(character)
            }
        }
        return out
    }
}

/// Codex's spelling of the shared section shape, for `SettingsMerge`.
enum CodexHookVocabulary: HookVocabulary {
    static let eventNames = CodexHookConfiguration.eventNames

    static func group(for event: String, endpoint: BridgeEndpoint) -> [String: Any] {
        ["hooks": [CodexHookConfiguration.entry(for: endpoint)]]
    }

    static func ownURL(_ entry: Any) -> String? {
        CodexHookConfiguration.belayURL(entry)
    }
}
