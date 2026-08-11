import Foundation

/// The JSON Vigil writes into `~/.claude/settings.json`, and the rule it uses to
/// recognise its own entries again later.
///
/// Shape verified against the installed CLI in docs/DISCOVERY §3.4.
enum HookConfiguration {
    static let path = "/hook"
    static let markerName = "src"
    static let markerValue = "vigil"
    /// Generous, because `async: true` means nobody waits on us anyway; it only
    /// exists so a wedged receiver cannot hold a connection open forever.
    static let timeoutSeconds = 5

    static func url(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(path)?\(markerName)=\(markerValue)"
    }

    static func entry(for endpoint: BridgeEndpoint) -> [String: Any] {
        [
            "type": "http",
            "url": url(port: endpoint.port),
            // The one line that makes it impossible for Vigil to slow the user's
            // agent down: an async hook is fire and forget, so there is no exit
            // code to get wrong and nothing to wait on (docs/00-INVARIANTS.md invariant 5).
            "async": true,
            "timeout": timeoutSeconds,
            "headers": ["Authorization": "Bearer \(endpoint.token)"]
        ]
    }

    static func group(for event: HookEvent, endpoint: BridgeEndpoint) -> [String: Any] {
        var group: [String: Any] = ["hooks": [entry(for: endpoint)]]
        if event.isToolScoped { group["matcher"] = "*" }
        return group
    }

    static func hooksSection(for endpoint: BridgeEndpoint) -> [String: Any] {
        var section: [String: Any] = [:]
        for event in HookEvent.allCases {
            section[event.rawValue] = [group(for: event, endpoint: endpoint)]
        }
        return section
    }

    /// Vigil's ownership marker lives in the hook's `url` as a query item rather
    /// than as an extra JSON key, for two reasons.
    ///
    /// Claude Code validates the shape of `settings.json`, and slipping an
    /// unrecognised key into a hook object is a way to break the user's agent
    /// for the sake of our own bookkeeping — precisely risk R2. And a URL is a
    /// string: it survives `JSONSerialization` unchanged, where a marker written
    /// as `true` comes back as an `NSNumber` and no longer compares equal to
    /// what we wrote, which would make uninstall miss entries it owns.
    static func isVigilEntry(_ value: Any) -> Bool {
        guard let url = vigilURL(value) else { return false }
        return !url.isEmpty
    }

    /// The URL of a Vigil-owned entry, or `nil` if the entry is not ours. This
    /// is what self-heal compares against the receiver's current port.
    static func vigilURL(_ value: Any) -> String? {
        guard let entry = value as? [String: Any],
            entry["type"] as? String == "http",
            let url = entry["url"] as? String,
            let components = URLComponents(string: url),
            components.path == path,
            components.queryItems?.contains(where: {
                $0.name == markerName && $0.value == markerValue
            }) == true
        else { return nil }
        return url
    }
}
