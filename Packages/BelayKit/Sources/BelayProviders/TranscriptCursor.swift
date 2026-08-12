import BelaySupport
import Foundation

/// What one incremental read of a transcript found.
struct TranscriptDelta: Sendable, Equatable {
    /// Complete JSONL lines, in file order. A trailing partial line is held back
    /// by the cursor and prepended to the next delta.
    let lines: [String]
    let bytesRead: Int
    /// The cursor had to re-sync: truncation, rotation, or an oversized delta.
    let didReset: Bool

    static let quiet = TranscriptDelta(lines: [], bytesRead: 0, didReset: false)

    /// Any evidence that something wrote to the file. Growth alone is a valid
    /// activity signal even when not one line of the delta parses — that is the
    /// whole mitigation for risk R1 (docs/11), so it must never depend on JSON.
    var indicatesWrite: Bool { bytesRead > 0 || didReset }
}

/// Incremental tail reader for a single session transcript.
///
/// Transcripts on a real machine reach 82 MB (docs/DISCOVERY §1), so the file is
/// never read from offset 0 after the first sight of it. The cursor keeps
/// `(inode, offset)` and reads only the delta.
struct TranscriptCursor: Sendable {
    /// Where a freshly adopted file should be picked up from.
    enum Seed {
        /// Exactly at EOF: history is not ours to read (docs/03, startup rule).
        case endOfFile
        /// The last `resyncWindow` bytes, for a transcript that appeared while
        /// we were already running and therefore has news in it.
        case tailWindow
    }

    /// Past this, the delta is history rather than news — typically a wake from
    /// sleep. We skip to `resyncWindow` and carry on.
    static let maxDelta = 256 * 1024
    static let resyncWindow = 64 * 1024
    /// A "line" this long is not a JSONL record, it is a corrupt or binary file.
    /// Dropping it bounds memory no matter what lands in the directory.
    static let maxPartial = 4 * 1024 * 1024

    let url: URL

    private var offset: UInt64 = 0
    private var inode: UInt64 = 0
    private var partial = Data()
    /// Set whenever we land mid-record, so the first newline we meet terminates
    /// a fragment that must be thrown away rather than parsed.
    private var dropsNextLine = false

    init(url: URL) {
        self.url = url
    }

    var currentOffset: UInt64 { offset }

    mutating func seed(_ seed: Seed, snapshot: FileSnapshot) {
        inode = snapshot.inode
        partial.removeAll(keepingCapacity: false)
        switch seed {
        case .endOfFile:
            offset = snapshot.size
            dropsNextLine = false
        case .tailWindow:
            rewindToTail(of: snapshot.size)
        }
    }

    /// Reads everything appended since the last call. Never throws: a transcript
    /// that vanished or turned unreadable is silence, and session death is the
    /// job of Tier C and the coordinator TTL, not of the reader.
    mutating func read(using access: FileAccessProvider) -> TranscriptDelta {
        guard let snapshot = FileSnapshot(url: url) else { return .quiet }

        var didReset = false
        let rotated = inode != 0 && snapshot.inode != inode
        if rotated || snapshot.size < offset || snapshot.size - offset > UInt64(Self.maxDelta) {
            partial.removeAll(keepingCapacity: false)
            rewindToTail(of: snapshot.size)
            didReset = true
        }
        inode = snapshot.inode

        guard snapshot.size > offset else {
            return TranscriptDelta(lines: [], bytesRead: 0, didReset: didReset)
        }
        let wanted = Int(min(snapshot.size - offset, UInt64(Self.maxDelta)))
        guard let chunk = readChunk(count: wanted, using: access), !chunk.isEmpty else {
            return TranscriptDelta(lines: [], bytesRead: 0, didReset: didReset)
        }
        offset += UInt64(chunk.count)
        return TranscriptDelta(lines: completeLines(from: chunk), bytesRead: chunk.count, didReset: didReset)
    }

    private mutating func rewindToTail(of size: UInt64) {
        let window = UInt64(Self.resyncWindow)
        offset = size > window ? size - window : 0
        dropsNextLine = offset > 0
    }

    private func readChunk(count: Int, using access: FileAccessProvider) -> Data? {
        do {
            return try access.withAccess(to: url) { url in
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: offset)
                return try handle.read(upToCount: count)
            }
        } catch {
            Log.providers.debug("transcript read failed: \(String(describing: error), privacy: .private)")
            return nil
        }
    }

    private mutating func completeLines(from chunk: Data) -> [String] {
        partial.append(chunk)
        var lines: [String] = []
        var start = partial.startIndex
        while let newline = partial[start...].firstIndex(of: UInt8(ascii: "\n")) {
            let raw = partial[start..<newline]
            start = partial.index(after: newline)
            if dropsNextLine {
                dropsNextLine = false
                continue
            }
            if let line = Self.text(of: raw) { lines.append(line) }
        }
        partial = Data(partial[start...])
        if partial.count > Self.maxPartial {
            partial.removeAll(keepingCapacity: false)
            dropsNextLine = true
        }
        return lines
    }

    private static func text(of raw: Data) -> String? {
        var slice = raw
        if slice.last == UInt8(ascii: "\r") { slice = slice.dropLast() }
        guard !slice.isEmpty else { return nil }
        return String(data: slice, encoding: .utf8)
    }
}
