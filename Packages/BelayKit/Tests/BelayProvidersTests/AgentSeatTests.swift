import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

@Suite("AgentSeats")
struct AgentSeatTests {
    private let scratch = TranscriptScratch()
    private let access = DirectFileAccess()

    private func write(pid: pid_t, _ json: String) {
        try? Data(json.utf8).write(to: scratch.sessions.appendingPathComponent("\(pid).json"))
    }

    private func find(_ session: String) -> AgentSeat? {
        AgentSeats.find(session: SessionID(session), in: scratch.sessions, access: access)
    }

    @Test("The entrypoint says a session runs inside the Claude desktop app")
    func desktopEntrypoint() {
        write(pid: getpid(), #"{"pid":\#(getpid()),"sessionId":"app","entrypoint":"claude-desktop"}"#)
        let seat = find("app")
        #expect(seat?.pid == getpid())
        #expect(seat?.isClaudeDesktop == true)
    }

    @Test("Any other entrypoint, or none, is not the desktop app")
    func terminalEntrypoint() {
        write(pid: getpid(), #"{"pid":\#(getpid()),"sessionId":"cli","entrypoint":"cli"}"#)
        #expect(find("cli")?.isClaudeDesktop == false)
    }

    @Test("A sidecar without an entrypoint still gives the process")
    func noEntrypoint() {
        write(pid: getpid(), #"{"pid":\#(getpid()),"sessionId":"old"}"#)
        #expect(find("old") == AgentSeat(pid: getpid(), entrypoint: nil))
    }

    @Test("An entrypoint of a shape nobody knows costs only the entrypoint")
    func strangeEntrypoint() {
        write(pid: getpid(), #"{"pid":\#(getpid()),"sessionId":"odd","entrypoint":{"a":1}}"#)
        #expect(find("odd") == AgentSeat(pid: getpid(), entrypoint: nil))
    }

    @Test("A dead process has no seat, and an unknown session none either")
    func deadOrUnknown() {
        write(pid: 999_999, #"{"pid":999999,"sessionId":"dead","entrypoint":"claude-desktop"}"#)
        #expect(find("dead") == nil)
        #expect(find("nobody") == nil)
    }
}
