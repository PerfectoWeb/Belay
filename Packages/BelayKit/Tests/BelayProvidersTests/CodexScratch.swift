import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// A `~/.codex/sessions` layout on disk, torn down with the suite.
final class CodexScratch: @unchecked Sendable {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-scratch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: day, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var day: URL {
        root.appendingPathComponent("2026/08/20", isDirectory: true)
    }

    var configuration: CodexProvider.Configuration {
        CodexProvider.Configuration(sessionsDirectory: root)
    }

    static func line(
        _ payloadType: String, at time: String? = nil, type: String = "event_msg"
    ) -> String {
        let stamp = time.map { #""timestamp":"\#($0)","# } ?? ""
        return #"{\#(stamp)"type":"\#(type)","payload":{"type":"\#(payloadType)"}}"#
    }

    static func meta(cwd: String) -> String {
        #"{"type":"session_meta","payload":{"cwd":"\#(cwd)"}}"#
    }

    func rollout(_ stamp: String, lines: [String]) -> URL {
        let url = day.appendingPathComponent("rollout-\(stamp).jsonl")
        let text = lines.map { $0 + "\n" }.joined()
        try? Data(text.utf8).write(to: url)
        return url
    }

    func append(_ lines: [String], to url: URL) {
        let handle = try? FileHandle(forWritingTo: url)
        try? handle?.seekToEnd()
        try? handle?.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
        try? handle?.close()
    }

    func touch(_ url: URL, secondsAgo: TimeInterval) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-secondsAgo)], ofItemAtPath: url.path)
    }
}
