import BelayCore
import BelaySupport
import Foundation

@testable import BelayProviders

/// A throwaway `~/.claude` tree, torn down when the test's reference goes away.
final class TranscriptScratch {
    let root: URL
    let projects: URL
    let sessions: URL

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("belay-tests-\(UUID().uuidString)", isDirectory: true)
        projects = root.appendingPathComponent("projects", isDirectory: true)
        sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var configuration: ClaudeCodeProvider.Configuration {
        ClaudeCodeProvider.Configuration(
            projectsDirectory: projects,
            sessionsDirectory: sessions,
            inferredIdleAfter: 45,
            staleAtStartupAfter: 600,
            latency: 0.15)
    }

    @discardableResult
    func transcript(_ session: String, project: String = "-fake-project", lines: [String] = []) -> URL {
        let directory = projects.appendingPathComponent(project, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(session).jsonl")
        let body = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? Data(body.utf8).write(to: url)
        return url
    }

    /// A subagent transcript, in either of the two layouts Claude Code writes
    /// (docs/DISCOVERY §1.2). `workflow` nil gives the Task-tool layout.
    @discardableResult
    func subagent(
        _ agent: String,
        of session: String,
        project: String = "-fake-project",
        workflow: String? = nil,
        kind: String? = nil,
        lines: [String] = []
    ) -> URL {
        var directory =
            projects
            .appendingPathComponent(project, isDirectory: true)
            .appendingPathComponent(session, isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        if let workflow {
            directory =
                directory
                .appendingPathComponent("workflows", isDirectory: true)
                .appendingPathComponent(workflow, isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(agent).jsonl")
        let body = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? Data(body.utf8).write(to: url)
        if let kind {
            let meta = "{\"agentType\":\"\(kind)\",\"description\":\"secret plan\",\"spawnDepth\":1}"
            try? Data(meta.utf8).write(to: directory.appendingPathComponent("\(agent).meta.json"))
        }
        return url
    }

    func append(_ text: String, to url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }

    func touch(_ url: URL, secondsAgo: TimeInterval) {
        let date = Date().addingTimeInterval(-secondsAgo)
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// A `~/.claude/sessions/<pid>.json` entry, per docs/DISCOVERY §1.1.
    func processFile(pid: pid_t, session: String, cwd: String = "/Volumes/Work/Demo") {
        let json = """
            {"pid":\(pid),"sessionId":"\(session)","cwd":"\(cwd)","startedAt":1786372058888,\
            "version":"2.1.222","kind":"interactive","entrypoint":"claude-desktop"}
            """
        try? Data(json.utf8).write(to: sessions.appendingPathComponent("\(pid).json"))
    }

    static let sampleTime = "2026-08-10T14:28:21.000Z"

    static func record(_ type: String, stop: String? = nil, at time: String = sampleTime) -> String {
        var message = ""
        if type == "assistant" || type == "user" {
            let reason = stop.map { "\"stop_reason\":\"\($0)\"," } ?? ""
            message = ",\"message\":{\(reason)\"role\":\"\(type)\",\"content\":[]}"
        }
        return "{\"type\":\"\(type)\",\"sessionId\":\"s\",\"timestamp\":\"\(time)\"\(message)}"
    }

    /// The synthetic record the CLI writes when a request fails, shaped like the
    /// real one: an assistant record whose stop_reason would read as a finished
    /// turn, marked apart only by the top-level flag (docs/DISCOVERY §2.3).
    static func apiErrorRecord(at time: String = sampleTime) -> String {
        "{\"type\":\"assistant\",\"sessionId\":\"s\",\"timestamp\":\"\(time)\","
            + "\"error\":\"server_error\",\"apiErrorStatus\":529,\"isApiErrorMessage\":true,"
            + "\"message\":{\"stop_reason\":\"stop_sequence\",\"role\":\"assistant\",\"content\":[]}}"
    }
}

/// Buffers everything a provider yields so a test can assert on the timeline.
actor SignalCollector {
    private var received: [ActivitySignal] = []
    private var pump: Task<Void, Never>?

    func attach(to stream: AsyncStream<ActivitySignal>) {
        pump = Task { [weak self] in
            for await signal in stream {
                await self?.append(signal)
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
    }

    /// Waits until `count` signals have arrived, or the timeout expires. Returns
    /// everything seen either way so the assertion, not the helper, reports.
    func wait(for count: Int, timeout: TimeInterval = 3) async -> [ActivitySignal] {
        let deadline = Date().addingTimeInterval(timeout)
        while received.count < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return received
    }

    /// Lets in-flight yields land before asserting that nothing arrived.
    func settle() async -> [ActivitySignal] {
        try? await Task.sleep(nanoseconds: 120_000_000)
        return received
    }

    private func append(_ signal: ActivitySignal) {
        received.append(signal)
    }
}

enum Fixture {
    static func url(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures")
    }

    /// Reads a fixture the way the provider would: tail-seeded cursor, one delta.
    static func lines(_ name: String) -> [String] {
        guard let url = url(name), let snapshot = FileSnapshot(url: url) else { return [] }
        var cursor = TranscriptCursor(url: url)
        cursor.seed(.tailWindow, snapshot: snapshot)
        return cursor.read(using: DirectFileAccess()).lines
    }
}
