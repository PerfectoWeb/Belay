import Foundation
import Testing
@testable import BelayProviders
import BelaySupport
import BelayCore

@Suite("FSE probe") struct FSEProbeTests {
    @Test func decodeRealSession() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cline/data/sessions", isDirectory: true)
        for id in ClineSessions.sessionIDs(under: root, access: DirectFileAccess()) {
            let url = ClineSessions.stateURL(id: id, under: root)
            let state = ClineSessionState.load(from: url, access: DirectFileAccess())
            print("PROBE \(id): decoded=\(state != nil) status=\(state?.status ?? "-") ws=\(state?.workspace ?? "-")")
        }
        let provider = ClineProvider(configuration: .clineHome(), access: DirectFileAccess())
        try await provider.start()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let watched = await provider.watched
        print("PROBE watched=\(watched.count) reported=\(watched.mapValues { $0.reported.map(String.init(describing:)) ?? "nil" })")
        await provider.stop()
    }
}
