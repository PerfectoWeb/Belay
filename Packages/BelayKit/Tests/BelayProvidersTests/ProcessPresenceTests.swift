import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

@Suite("ProcessPresence")
struct ProcessPresenceTests {
    private let scratch = TranscriptScratch()
    private let access = DirectFileAccess()

    private func scan(isAlive: @escaping @Sendable (pid_t) -> Bool) -> [AgentProcessRecord] {
        ProcessPresence.scan(directory: scratch.sessions, access: access, isAlive: isAlive)
    }

    @Test("pid, session and cwd come straight out of ~/.claude/sessions")
    func readsSessionFiles() {
        scratch.processFile(pid: 4242, session: "abc-123", cwd: "/Volumes/BASE/Work/Apps/MacOS/Belay")
        let records = scan { _ in true }
        #expect(records.count == 1)
        #expect(records.first?.pid == 4242)
        #expect(records.first?.session == SessionID("abc-123"))
        #expect(records.first?.workspace == "Belay")
    }

    private func write(pid: pid_t, _ json: String) {
        try? Data(json.utf8).write(to: scratch.sessions.appendingPathComponent("\(pid).json"))
    }

    /// Two sessions in one checkout share a `cwd`, so the workspace name cannot
    /// tell their rows apart. `name` is the only field that can, and a sidecar
    /// written by an older Claude Code has none.
    @Test("The session's own name comes through, and a missing one stays nil")
    func readsSessionName() {
        write(pid: 21, #"{"pid":21,"sessionId":"named","cwd":"/w/Belay","name":"belay-9a"}"#)
        write(pid: 22, #"{"pid":22,"sessionId":"blank","cwd":"/w/Belay","name":""}"#)
        write(pid: 23, #"{"pid":23,"sessionId":"absent","cwd":"/w/Belay"}"#)

        let records = scan { _ in true }
        #expect(records.first { $0.session == SessionID("named") }?.name == "belay-9a")
        #expect(records.first { $0.session == SessionID("blank") }?.name == nil)
        #expect(records.first { $0.session == SessionID("absent") }?.name == nil)
    }

    @Test("Liveness is per-record and injectable")
    func liveAndDead() {
        scratch.processFile(pid: 11, session: "alive")
        scratch.processFile(pid: 12, session: "dead")
        let records = scan { $0 == 11 }
        #expect(records.first { $0.session == SessionID("alive") }?.isAlive == true)
        #expect(records.first { $0.session == SessionID("dead") }?.isAlive == false)
    }

    @Test("kill(pid, 0) sees this process and not an impossible one")
    func realLiveness() {
        #expect(ProcessPresence.isAlive(getpid()))
        #expect(ProcessPresence.isAlive(0) == false)
        #expect(ProcessPresence.isAlive(-1) == false)
        // Above the default kern.maxproc there is nothing to find.
        #expect(ProcessPresence.isAlive(999_999) == false)
    }

    @Test("Malformed and unrelated files are skipped, not fatal")
    func ignoresJunk() {
        scratch.processFile(pid: 7, session: "good")
        let junk = scratch.sessions.appendingPathComponent("8.json")
        try? Data("{not json".utf8).write(to: junk)
        let stray = scratch.sessions.appendingPathComponent("notes.txt")
        try? Data("{\"pid\":9,\"sessionId\":\"x\"}".utf8).write(to: stray)

        let records = scan { _ in true }
        #expect(records.count == 1)
        #expect(records.first?.session == SessionID("good"))
    }

    @Test("A missing sessions directory yields nothing rather than throwing")
    func missingDirectory() {
        let records = ProcessPresence.scan(
            directory: URL(fileURLWithPath: "/nope-\(UUID().uuidString)"), access: access,
            isAlive: { _ in true })
        #expect(records.isEmpty)
    }
}
