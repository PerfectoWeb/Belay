import Foundation

/// Pure merge of Belay's hooks into a parsed `settings.json`, and back out again.
///
/// No file touches anything here, which is what lets the dangerous cases — a
/// user who already has their own hooks on the same events — be tested exactly.
/// The rule throughout is that anything Belay does not recognise is copied
/// across untouched, including values of the wrong shape.
enum SettingsMerge {
    /// `endpoint: nil` uninstalls.
    static func merged(_ settings: [String: Any], endpoint: BridgeEndpoint?) throws -> [String: Any] {
        var result = settings
        let original = try existingSection(in: settings)
        var section = strip(original ?? [:])

        if let endpoint {
            for event in HookEvent.allCases {
                var groups = section[event.rawValue] as? [Any] ?? []
                groups.append(HookConfiguration.group(for: event, endpoint: endpoint))
                section[event.rawValue] = groups
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

    static func installedURLs(in settings: [String: Any]) -> [String] {
        guard let section = settings["hooks"] as? [String: Any] else { return [] }
        return section.values
            .compactMap { $0 as? [Any] }
            .flatMap { $0 }
            .compactMap { $0 as? [String: Any] }
            .compactMap { $0["hooks"] as? [Any] }
            .flatMap { $0 }
            .compactMap(HookConfiguration.belayURL)
    }

    private static func existingSection(in settings: [String: Any]) throws -> [String: Any]? {
        guard let value = settings["hooks"] else { return nil }
        guard let section = value as? [String: Any] else { throw BridgeError.hooksNotAnObject }
        return section
    }

    private static func strip(_ section: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in section {
            guard let groups = value as? [Any] else {
                result[event] = value
                continue
            }
            var kept: [Any] = []
            var removedAny = false
            for group in groups {
                guard let survivor = strip(group: group, removedAny: &removedAny) else { continue }
                kept.append(survivor)
            }
            // An event left with no groups had nothing but ours in it, so the key
            // is ours to remove too — unless it was already empty before we looked.
            if !kept.isEmpty || !removedAny { result[event] = kept }
        }
        return result
    }

    /// `nil` means the whole group was Belay's and should disappear.
    private static func strip(group: Any, removedAny: inout Bool) -> Any? {
        guard var dictionary = group as? [String: Any],
            let entries = dictionary["hooks"] as? [Any]
        else { return group }

        let kept = entries.filter { !HookConfiguration.isBelayEntry($0) }
        guard kept.count != entries.count else { return group }
        removedAny = true
        guard !kept.isEmpty else { return nil }
        dictionary["hooks"] = kept
        return dictionary
    }
}
