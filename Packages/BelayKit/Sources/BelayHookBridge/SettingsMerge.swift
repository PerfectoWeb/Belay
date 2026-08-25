import Foundation

/// One agent's spelling of a hooks file: which events Belay registers, what an
/// entry looks like, and how Belay recognises its own entries again later.
/// Claude Code's `settings.json` and Codex's `hooks.json` share the section
/// shape — `{event: [group{hooks: [entry]}]}` — and differ in exactly these
/// three answers.
protocol HookVocabulary {
    static var eventNames: [String] { get }
    static func group(for event: String, endpoint: BridgeEndpoint) -> [String: Any]
    /// The URL inside an entry this vocabulary owns, `nil` for anyone else's.
    static func ownURL(_ entry: Any) -> String?
}

/// Claude Code's spelling: HTTP entries in `settings.json`.
enum ClaudeHookVocabulary: HookVocabulary {
    static let eventNames = HookEvent.allCases.map(\.rawValue)

    static func group(for event: String, endpoint: BridgeEndpoint) -> [String: Any] {
        guard let event = HookEvent(rawValue: event) else { return [:] }
        return HookConfiguration.group(for: event, endpoint: endpoint)
    }

    static func ownURL(_ entry: Any) -> String? {
        HookConfiguration.belayURL(entry)
    }
}

/// Pure merge of Belay's hooks into a parsed `settings.json`, and back out again.
///
/// No file touches anything here, which is what lets the dangerous cases — a
/// user who already has their own hooks on the same events — be tested exactly.
/// The rule throughout is that anything Belay does not recognise is copied
/// across untouched, including values of the wrong shape.
enum SettingsMerge {
    /// `endpoint: nil` uninstalls.
    static func merged(
        _ settings: [String: Any],
        endpoint: BridgeEndpoint?,
        vocabulary: any HookVocabulary.Type = ClaudeHookVocabulary.self
    ) throws -> [String: Any] {
        var result = settings
        let original = try existingSection(in: settings)
        var section = strip(original ?? [:], vocabulary: vocabulary)

        if let endpoint {
            // Appended after whatever the user has, never inserted: Codex
            // records hook trust by position in these arrays, so an insert
            // would break the trust of every hook behind it.
            for event in vocabulary.eventNames {
                // A registered event key already holding something that is not a
                // group array is the user's own, of a shape Belay cannot merge
                // into. `strip` deliberately copies such values through untouched
                // — but this loop would then overwrite it with Belay's array,
                // silently destroying it. Refuse instead, the same stance a
                // non-object `hooks` section gets: the merge is pure, so throwing
                // means nothing is ever written.
                if let existing = section[event], !(existing is [Any]) {
                    throw BridgeError.hooksNotAnObject
                }
                var groups = section[event] as? [Any] ?? []
                groups.append(vocabulary.group(for: event, endpoint: endpoint))
                section[event] = groups
            }
        }

        guard section.isEmpty else {
            result["hooks"] = section
            return result
        }
        // An empty section is left alone only if the user's file already had one;
        // one that we emptied is one we created, and it goes away with us.
        if original?.isEmpty == true {
            result["hooks"] = [String: Any]()
        } else {
            result.removeValue(forKey: "hooks")
        }
        return result
    }

    static func installedURLs(
        in settings: [String: Any],
        vocabulary: any HookVocabulary.Type = ClaudeHookVocabulary.self
    ) -> [String] {
        guard let section = settings["hooks"] as? [String: Any] else { return [] }
        return section.values
            .compactMap { $0 as? [Any] }
            .flatMap { $0 }
            .compactMap { $0 as? [String: Any] }
            .compactMap { $0["hooks"] as? [Any] }
            .flatMap { $0 }
            .compactMap(vocabulary.ownURL)
    }

    private static func existingSection(in settings: [String: Any]) throws -> [String: Any]? {
        guard let value = settings["hooks"] else { return nil }
        guard let section = value as? [String: Any] else { throw BridgeError.hooksNotAnObject }
        return section
    }

    private static func strip(
        _ section: [String: Any], vocabulary: any HookVocabulary.Type
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in section {
            guard let groups = value as? [Any] else {
                result[event] = value
                continue
            }
            var kept: [Any] = []
            var removedAny = false
            for group in groups {
                guard
                    let survivor = strip(
                        group: group, removedAny: &removedAny, vocabulary: vocabulary)
                else { continue }
                kept.append(survivor)
            }
            // An event left with no groups had nothing but ours in it, so the key
            // is ours to remove too — unless it was already empty before we looked.
            if !kept.isEmpty || !removedAny { result[event] = kept }
        }
        return result
    }

    /// `nil` means the whole group was Belay's and should disappear.
    private static func strip(
        group: Any, removedAny: inout Bool, vocabulary: any HookVocabulary.Type
    ) -> Any? {
        guard var dictionary = group as? [String: Any],
            let entries = dictionary["hooks"] as? [Any]
        else { return group }

        let kept = entries.filter { vocabulary.ownURL($0) == nil }
        guard kept.count != entries.count else { return group }
        removedAny = true
        guard !kept.isEmpty else { return nil }
        dictionary["hooks"] = kept
        return dictionary
    }
}
