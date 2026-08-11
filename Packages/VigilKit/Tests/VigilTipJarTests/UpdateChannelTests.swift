import Testing

@testable import VigilTipJar

@Suite struct UpdateChannelTests {
    /// Until there is a signing key and a real feed (BLOCKERS.md B3), the app
    /// must not offer to check for updates at all. A "Check for Updates…" item
    /// that quietly does nothing is worse than no item.
    @Test func noUpdateChannelReportsItselfUnsupported() {
        let channel = NoUpdateChannel()

        #expect(channel.isSupported == false)
        channel.checkForUpdates()
    }

    @Test func appcastIsUnconfiguredAndItsPlaceholderIsNotReachable() {
        #expect(Appcast.isConfigured == false)
        #expect(Appcast.feedURL.hasPrefix("https://"))
        #expect(Appcast.feedURL.contains(".invalid."))
    }

    /// docs/06: check on a schedule, never install without being asked.
    @Test func updatesAreNeverInstalledUnattended() {
        #expect(Appcast.installsAutomatically == false)
        #expect(Appcast.checksAutomatically)
    }
}
