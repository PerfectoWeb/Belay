import BelayCore
import Testing

@testable import BelayHookBridge

/// The badge must land on the right shelf for the names both CLIs actually
/// send, and an unknown name is still a tool.
@Suite("Tool categories")
struct ToolCategoryTests {
    @Test("Known names map to their categories")
    func knownNames() {
        #expect(HookEnvelope.category(of: "Bash") == .command)
        #expect(HookEnvelope.category(of: "shell") == .command)
        #expect(HookEnvelope.category(of: "Edit") == .edit)
        #expect(HookEnvelope.category(of: "Write") == .edit)
        #expect(HookEnvelope.category(of: "apply_patch") == .edit)
        #expect(HookEnvelope.category(of: "Read") == .read)
        #expect(HookEnvelope.category(of: "Grep") == .search)
        #expect(HookEnvelope.category(of: "Glob") == .search)
        #expect(HookEnvelope.category(of: "WebSearch") == .web, "web outranks search")
        #expect(HookEnvelope.category(of: "WebFetch") == .web)
        #expect(HookEnvelope.category(of: "Task") == .subagent)
        #expect(HookEnvelope.category(of: "mcp__figma__export") == .tool)
        #expect(HookEnvelope.category(of: "SomethingNew") == .tool)
        #expect(HookEnvelope.category(of: nil) == .tool)
    }
}
