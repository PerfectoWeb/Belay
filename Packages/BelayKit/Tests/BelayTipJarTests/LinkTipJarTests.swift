// `OpenedURLs` below is @unchecked Sendable, which docs/00-INVARIANTS.md asks to justify in
// the file header: the opener closure LinkTipJar takes is `@Sendable`, so its
// capture has to be, but the spy is only ever written by the closure and read
// by the test after the awaited call has returned. There is no concurrency to
// protect against here and a lock would only test the lock.

import Foundation
import Testing

@testable import BelayTipJar

private final class OpenedURLs: @unchecked Sendable {
    private(set) var urls: [URL] = []

    func record(_ url: URL) { urls.append(url) }
}

@Suite struct LinkTipJarTests {
    private func supportURL() throws -> URL {
        try #require(URL(string: "https://github.com/perfectoweb/belay"))
    }

    @Test func offersASingleSupportLink() async throws {
        let spy = OpenedURLs()
        let jar = LinkTipJar(destination: try supportURL(), open: { spy.record($0) })

        #expect(jar.isAvailable)
        #expect(await jar.availableTips() == [TipProducts.supportLink])
    }

    @Test func purchaseOpensTheSupportURL() async throws {
        let support = try supportURL()
        let spy = OpenedURLs()
        let jar = LinkTipJar(destination: support, open: { spy.record($0) })

        try await jar.purchase(TipProducts.supportLink)

        #expect(spy.urls == [support])
    }

    @Test func purchaseRejectsATipItDidNotOffer() async throws {
        let spy = OpenedURLs()
        let jar = LinkTipJar(destination: try supportURL(), open: { spy.record($0) })
        let stray = Tip(id: TipProducts.medium, title: "Medium", subtitle: "")

        await #expect(throws: TipJarError.unknownTip(TipProducts.medium)) {
            try await jar.purchase(stray)
        }
        #expect(spy.urls.isEmpty)
    }
}
