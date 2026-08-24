import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

/// A `~/.cline/data/sessions` layout on disk, torn down with the suite.
final class ClineScratch: @unchecked Sendable {
    let root: URL

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cline-scratch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var sessions: URL { root.appendingPathComponent("data/sessions", isDirectory: true) }

    var configuration: ClineProvider.Configuration {
        ClineProvider.Configuration(sessionsDirectory: sessions)
    }

    @discardableResult
    func session(_ id: String, status: String, workspace: String = "/tmp/demo") -> URL {
        let directory = sessions.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = """
            {"version":1,"session_id":"\(id)","status":"\(status)","cwd":"\(workspace)",\
            "workspace_root":"\(workspace)","prompt":"SECRET, never decoded"}
            """
        let url = directory.appendingPathComponent("\(id).json")
        try? Data(state.utf8).write(to: url)
        return url
    }

    func messages(_ id: String, bytes: Int) {
        let url = sessions.appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("\(id).messages.json")
        try? Data(String(repeating: "x", count: bytes).utf8).write(to: url)
    }

    func touch(_ url: URL, secondsAgo: TimeInterval) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-secondsAgo)], ofItemAtPath: url.path)
    }
}
