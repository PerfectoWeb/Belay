import Foundation

/// Keeps `belay.log` from growing forever.
///
/// The file exists only while the diagnostics switch is on, but a switch left
/// on writes for months — and nothing else in the pipeline ever deletes a
/// byte. So the start of collection is the one moment with a natural pause,
/// and this trims there: past three megabytes the file shrinks to its last
/// one, which is the same window `endedDirty` reads and several days of even
/// a soak-grade session. Diagnosis never needs more; `os.Logger` keeps the
/// long history under the system's own rotation.
enum LogTrim {
    static let cap = 3 * 1_048_576
    static let keep = 1_048_576

    /// Trims `file` in place if it is over `cap`, keeping the last `keep`
    /// bytes cut at a line boundary. Returns true when a trim happened.
    @discardableResult
    static func trimIfOversized(
        _ file: URL, cap: Int = LogTrim.cap, keep: Int = LogTrim.keep
    ) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > UInt64(cap) else { return false }

        try? handle.seek(toOffset: size - UInt64(keep))
        guard var data = try? handle.readToEnd() else { return false }
        // The cut lands mid-line; the partial line ahead of the first newline
        // is nobody's, so it goes.
        if let newline = data.firstIndex(of: 0x0A) {
            data = data[data.index(after: newline)...]
        }

        let megabytes = Double(size) / 1_048_576
        var trimmed = Data(
            "log trimmed to its last 1MB (was \(String(format: "%.1f", megabytes))MB)\n".utf8)
        trimmed.append(data)
        do {
            try trimmed.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
