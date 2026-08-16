import BelayChannel
import Foundation

/// The sentence About uses to say what Belay reads and what stays here.
///
/// Split by channel, because its last clause is only true of one of them. The
/// App Store build ships without an outbound network entitlement and its own
/// Settings pane tells the user it never connects out; promising a daily update
/// check in the same window was a contradiction visible from one screen.
///
/// Everywhere else in this project already splits this claim by channel:
/// `PRIVACY.md` has a heading each, and `project.yml` records why the Finder
/// copyright string ended up making no claim at all. This was the one place
/// that had not caught up.
enum PrivacyPromise {
    static var forThisChannel: String {
        switch DistributionChannel.current {
        case .direct:
            String(
                localized: """
                    Belay reads only enough of your agent's session files to know whether it is \
                    running. Never your prompts, never your code, and nothing about you leaves \
                    this Mac. The one exception is the daily update check, which you can switch \
                    off.
                    """)
        case .appStore:
            String(
                localized: """
                    Belay reads only enough of your agent's session files to know whether it is \
                    running. Never your prompts, never your code, and nothing about you leaves \
                    this Mac.
                    """)
        }
    }
}
