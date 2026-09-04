import Foundation
import Testing

@testable import BelayCore

/// The tool bracket is what the badge shows: which category the session is
/// inside, held open by PreToolUse, closed by its return or by Stop, and not
/// wiped by a return that belongs to the previous call.
@Suite("Tool bracket")
struct ToolBracketTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func fresh() -> SessionState {
        SessionState(id: SessionID("s1"), provider: .claudeCode, workspace: "acme-api", firstSeen: t0)
    }

    @Test("An open carries its category, a return past the grace clears it")
    func openAndReturn() {
        var state = fresh()
        state.record(
            .make(.working, at: t0, confidence: .exact, toolCall: .opened, tool: .command))
        #expect(state.activeTool == .command)
        #expect(state.openToolCallSince == t0)

        state.record(.make(.working, at: t0 + 30, confidence: .exact, toolCall: .returned))
        #expect(state.activeTool == nil)
        #expect(state.openToolCallSince == nil)
    }

    @Test("A return inside the grace is the previous call's and leaves the bracket")
    func reorderedReturnIsIgnored() {
        var state = fresh()
        state.record(
            .make(.working, at: t0, confidence: .exact, toolCall: .opened, tool: .edit))
        state.record(
            .make(
                .working, at: t0 + SessionState.returnGrace / 2, confidence: .exact,
                toolCall: .returned))
        #expect(state.activeTool == .edit, "the badge must not blink on a reordered return")
        #expect(state.openToolCallSince == t0)
    }

    @Test("A new open replaces the category, Stop closes everything")
    func reopenAndClose() {
        var state = fresh()
        state.record(
            .make(.working, at: t0, confidence: .exact, toolCall: .opened, tool: .read))
        state.record(
            .make(.working, at: t0 + 10, confidence: .exact, toolCall: .opened, tool: .web))
        #expect(state.activeTool == .web)

        state.record(.make(.idle, at: t0 + 20, confidence: .exact, toolCall: .closed))
        #expect(state.activeTool == nil)
        #expect(state.openToolCallSince == nil)
    }

    @Test("An open without a category still brackets, just unlabelled")
    func openWithoutCategory() {
        var state = fresh()
        state.record(.make(.working, at: t0, confidence: .exact, toolCall: .opened))
        #expect(state.openToolCallSince == t0)
        #expect(state.activeTool == nil)
    }
}
