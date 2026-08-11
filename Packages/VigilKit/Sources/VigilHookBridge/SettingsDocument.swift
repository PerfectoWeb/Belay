import Foundation

/// Reading, backing up and replacing `~/.claude/settings.json`.
///
/// This is the file the user cares about more than anything Vigil owns
/// (docs/11 R2), so every method here is written to fail without writing rather
/// than to succeed approximately.
struct SettingsDocument: Sendable {
    /// Deterministic output so a preview is byte-for-byte what lands on disk.
    /// `JSONSerialization` cannot preserve the user's key order anyway — a
    /// Swift dictionary has none — so sorting at least makes the result stable
    /// across runs instead of arbitrary.
    static let writeOptions: JSONSerialization.WritingOptions = [
        .prettyPrinted, .sortedKeys, .withoutEscapingSlashes
    ]

    let url: URL
    let backups: URL

    /// Empty for a file that is not there yet: creating `settings.json` for a
    /// user who has none is safe, and it is the common path on a fresh machine.
    func load() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BridgeError.settingsUnreadable(error.localizedDescription)
        }
        guard !data.isEmpty else { return [:] }
        // JSONSerialization is strict about comments and trailing commas, which
        // is exactly the property we want: if it will not parse, we will not write.
        guard let parsed = try? JSONSerialization.jsonObject(with: data),
            let object = parsed as? [String: Any]
        else { throw BridgeError.settingsNotPlainJSON }
        return object
    }

    /// `JSONSerialization` emits UTF-8 by definition, so the fallback is
    /// unreachable; it is here because the initialiser is optional, not because
    /// the failure can happen.
    static func text(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }

    static func serialize(_ object: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: writeOptions)
        } catch {
            throw BridgeError.settingsWriteFailed(error.localizedDescription)
        }
    }

    /// Copies the raw bytes, not a re-serialised parse, so the backup is a
    /// faithful restore even for a file we would have refused to write.
    /// `nil` when there is nothing there yet.
    @discardableResult
    func backup(now: Date = Date()) throws -> URL? {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return nil }
        do {
            try manager.createDirectory(at: backups, withIntermediateDirectories: true)
            let destination = backups.appendingPathComponent(Self.backupName(at: now))
            try Data(contentsOf: url).write(to: destination)
            return destination
        } catch {
            throw BridgeError.backupFailed(error.localizedDescription)
        }
    }

    /// Write to a temp file in the same directory, then `replaceItem`. Never
    /// truncate in place: a crash mid-write must not be able to leave the user
    /// with half a settings file.
    func write(_ data: Data) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".vigil-\(UUID().uuidString).tmp")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: temporary)
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

    static func backupName(at now: Date) -> String {
        "settings-\(BackupStamp.text(for: now)).json"
    }
}

/// A fixed-format UTC stamp, pinned to POSIX so a user's region cannot turn a
/// backup filename into something that no longer sorts by time.
private enum BackupStamp {
    static func text(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        return formatter.string(from: date)
    }
}
