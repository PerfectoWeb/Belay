import BelayCore
import BelaySupport
import Foundation
import Testing

@testable import BelayProviders

@Suite("Copilot events")
struct CopilotEventsTests {
    @Test("Turn markers map to edges, last one wins, noise maps to nothing")
    func markers() {
        let open = CopilotEvents.verdict(in: [CopilotScratch.line("assistant.turn_start")])
        #expect(open == .init(activity: .working, turnOpen: true))
        let closed = CopilotEvents.verdict(
            in: [
                CopilotScratch.line("assistant.turn_start"),
                CopilotScratch.line("assistant.turn_end")
            ])
        #expect(closed == .init(activity: .idle, turnOpen: false))
        #expect(CopilotEvents.verdict(in: [CopilotScratch.line("session.usage_checkpoint")]) == nil)
        #expect(CopilotEvents.verdict(in: ["not json at all"]) == nil)
    }

    @Test("The workspace is the last path component of session.start's cwd")
    func workspace() {
        let lines = [CopilotScratch.start(cwd: "/Users/x/Work/MyProject")]
        #expect(CopilotEvents.workspace(in: lines) == "MyProject")
        #expect(CopilotEvents.workspace(in: [CopilotScratch.line("assistant.turn_start")]) == nil)
    }

    @Test("Only events.jsonl counts, and the session id is its directory")
    func naming() {
        let url = URL(fileURLWithPath: "/a/session-state/uuid-1/events.jsonl")
        #expect(CopilotEvents.isEventsFile(url))
        #expect(!CopilotEvents.isEventsFile(URL(fileURLWithPath: "/a/uuid-1/plan.md")))
        #expect(CopilotEvents.sessionID(for: url) == SessionID("uuid-1"))
    }
}
