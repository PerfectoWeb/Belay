import Foundation
import Testing

@testable import BelayProviders

@Suite("Codex not installed")
struct CodexNotInstalledTests {
    /// Not there at all, to a build that can tell: "not installed", never
    /// "grant me the folder". The first tester without Codex was asked for
    /// ~/.codex by the old rule, which could not tell absent from unreadable.
    @Test("An absent ~/.codex is reported as not installed")
    func absentHomeIsNotInstalled() async {
        let missing = CodexProvider(
            configuration: .init(
                sessionsDirectory: URL(fileURLWithPath: "/nope-\(UUID().uuidString)/sessions")))
        guard case .unavailable = await missing.availability else {
            Issue.record("expected unavailable when ~/.codex does not exist")
            return
        }
        await #expect(throws: ProviderError.self) { try await missing.start() }
    }
}
