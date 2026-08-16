import Testing

@testable import BelayChannel

@Suite struct UpdateChannelTests {
    /// Until there is a signing key and a real feed (BLOCKERS.md B3), the app
    /// must not offer to check for updates at all. A "Check for Updates…" item
    /// that quietly does nothing is worse than no item.
    @Test func noUpdateChannelReportsItselfUnsupported() {
        let channel = NoUpdateChannel()

        #expect(channel.isSupported == false)
        channel.checkForUpdates()
    }

    /// The feed has an address now, and it is still not configured: the signing
    /// key is the piece that is missing (BLOCKERS.md B3). This used to insist
    /// the URL contained ".invalid.", which was a stand-in for "nothing is
    /// wired yet" and stopped being true the moment the host was decided. What
    /// is worth guarding is what the address has to be, not that it is fake.
    @Test func theAppcastIsHttpsOnTheProjectsOwnSite() {
        #expect(Appcast.isConfigured == false)
        #expect(Appcast.feedURL.hasPrefix("https://"))
        #expect(Appcast.feedURL.hasPrefix("https://perfectoweb.github.io/Belay/"))
        #expect(Appcast.feedURL.hasSuffix(".xml"))
    }

    /// docs/06: check on a schedule, never install without being asked.
    @Test func updatesAreNeverInstalledUnattended() {
        #expect(Appcast.installsAutomatically == false)
        #expect(Appcast.checksAutomatically)
    }
}
