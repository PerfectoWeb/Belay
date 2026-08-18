import BelaySupport
import Foundation

/// Whether the app should be saying, unprompted, that an update is waiting.
///
/// Split from `ReleaseChecker` because that file is at the length limit, and
/// because the two answer different questions. The checker answers "what is
/// published"; this answers "should the mark say so", which is not the same.
///
/// There is deliberately no way to dismiss it. A skip row next to the install
/// row is a nudge, and the mark is already the quietest thing the app could
/// say: it sits in the corner of an icon, it never opens a window, and it goes
/// away by itself the moment the update is installed. Something you can ignore
/// does not also need a control for ignoring it.
enum UpdateWaiting {
    /// True when there is a published update newer than this build.
    static func isWaiting(_ status: ReleaseChecker.Status) -> Bool {
        guard case .available = status else { return false }
        return true
    }
}
