import Foundation

/// Reading, backing up and surgically editing `~/.codex/config.toml`.
///
/// This file holds the user's model, their auth mode, their desktop client's
/// `notify` wiring — everything. Belay's business in it is exactly one kind of
/// line: `[hooks.state."<key>"]` tables carrying a `trusted_hash`, one per
/// Belay hook. So the edit is textual and surgical — no TOML round-trip that
/// could reorder or reformat what the user wrote — and every write is backed
/// up raw first, like `settings.json`.
struct CodexConfigDocument: Sendable {
    let url: URL
    let backups: URL

    /// Empty for a file that is not there: a fresh codex install has one, but
    /// refusing to trust hooks over its absence would be backwards.
    func load() throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw BridgeError.settingsUnreadable(error.localizedDescription)
        }
    }

    @discardableResult
    func backup(now: Date = Date()) throws -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return nil }
        do {
            try manager.createDirectory(at: backups, withIntermediateDirectories: true)
            let destination = backups.appendingPathComponent(
                "config-\(SettingsDocument.backupStamp(at: now)).toml")
            try Data(contentsOf: url).write(to: destination)
            return destination
        } catch {
            throw BridgeError.backupFailed(error.localizedDescription)
        }
    }

    func write(_ text: String) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".belay-\(UUID().uuidString).tmp")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: temporary)
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw BridgeError.settingsWriteFailed(error.localizedDescription)
        }
    }

    // MARK: - Pure edits

    /// Removes the trust tables for `keys`, each being a whole
    /// `[hooks.state."<key>"]` section: the header line and everything under
    /// it up to the next `[` header. Only exact keys go — a user's own hook in
    /// the same file keeps its trust untouched.
    static func removingTrust(_ text: String, keys: [String]) -> String {
        guard !keys.isEmpty, !text.isEmpty else { return text }
        let headers = Set(keys.map { "[hooks.state.\"\($0)\"]" })
        var kept: [Substring] = []
        var dropping = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if headers.contains(trimmed) {
                dropping = true
                continue
            }
            if dropping {
                guard trimmed.hasPrefix("[") else { continue }
                dropping = false
            }
            kept.append(line)
        }
        // The drop can leave doubled blank lines where a section was; collapse
        // only at the seam by trimming trailing emptiness and ending cleanly.
        var result = kept.joined(separator: "\n")
        while result.hasSuffix("\n\n") { result.removeLast() }
        return result
    }

    /// Appends one trust table per entry, after removing any stale table for
    /// the same key, so the edit is idempotent and a re-install refreshes the
    /// hash instead of stacking a second copy.
    static func addingTrust(_ text: String, entries: [(key: String, hash: String)]) -> String {
        var result = removingTrust(text, keys: entries.map(\.key))
        if !result.isEmpty, !result.hasSuffix("\n") { result.append("\n") }
        for entry in entries {
            result.append("\n[hooks.state.\"\(entry.key)\"]\n")
            result.append("trusted_hash = \"\(entry.hash)\"\n")
        }
        return result
    }
}
