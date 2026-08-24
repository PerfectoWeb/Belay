import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// A `~/.copilot/session-state` layout on disk, torn down with the suite.
final class CopilotScratch: @unchecked Sendable {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("copilot-scratch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var configuration: CopilotProvider.Configuration {
        CopilotProvider.Configuration(sessionsDirectory: root)
    }

    static func line(_ type: String, at time: String? = nil) -> String {
        let stamp = time.map { #""timestamp":"\#($0)","# } ?? ""
        return #"{\#(stamp)"type":"\#(type)","data":{}}"#
    }

    static func start(cwd: String, at time: String? = nil) -> String {
        let stamp = time.map { #""timestamp":"\#($0)","# } ?? ""
        return #"{\#(stamp)"type":"session.start","data":{"context":{"cwd":"\#(cwd)"}}}"#
    }

    func events(_ session: String, lines: [String]) -> URL {
        let dir = root.appendingPathComponent(session, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("events.jsonl")
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
