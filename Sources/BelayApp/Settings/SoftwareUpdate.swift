import BelaySupport
import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

/// Installing a newer Belay over this one, in place.
///
/// `ReleaseChecker` finds updates and this installs them, and the split is on
/// purpose. Finding is one HTTPS GET that this project can explain in a
/// sentence and has tested; installing is replacing a running application with
/// a signed copy of itself, which is a solved problem with a long list of ways
/// to get it wrong. Sparkle is that solution, and nothing here reimplements any
/// of it.
///
/// **The App Store build has none of this.** The store updates its own apps and
/// rejects a second updater, so the Sparkle package is a dependency of the
/// direct target only. `canImport` is therefore false in the other build, this
/// file compiles down to "no", and `verify-mas-build.sh` fails if a Sparkle
/// symbol appears in that binary anyway.
///
/// **Automatic checking stays off in Sparkle.** `SUEnableAutomaticChecks` is
/// false and the scheduled check is Belay's own, once a day, through
/// `ReleaseChecker`. Two updaters both polling on their own timers is two
/// network habits to explain in a privacy statement that currently needs one.
@MainActor
enum SoftwareUpdate {
    /// Whether this build can replace itself. False in the App Store build.
    static var isSupported: Bool {
        #if canImport(Sparkle)
        return true
        #else
        return false
        #endif
    }

    /// Downloads and installs the newest release, showing progress and asking
    /// before it relaunches.
    ///
    /// Sparkle checks the appcast again rather than being handed the URL
    /// `ReleaseChecker` already found. That is the point of it: the appcast
    /// entry carries an EdDSA signature over the exact bytes, checked against
    /// the public key compiled into this build, and an installer that accepted
    /// a URL from elsewhere would be checking nothing.
    static func install() {
        #if canImport(Sparkle)
        Log.app.notice("asking Sparkle to install the newest release")
        controller.checkForUpdates(nil)
        #endif
    }

    #if canImport(Sparkle)
    /// Built once, on first use, and kept for the life of the process.
    ///
    /// `startingUpdater: true` starts the updater immediately, which is what
    /// makes `checkForUpdates` answer. It does not schedule anything on its own:
    /// that is `SUEnableAutomaticChecks` in `Info-Direct.plist`, and it is false.
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: feedSwitch, userDriverDelegate: nil)

    private static let feedSwitch = FeedSwitch()

    /// Chooses which appcast the updater reads.
    ///
    /// Release builds have one answer and it comes from `SUFeedURL`. Debug builds
    /// with **Pretend Update** on read a test feed instead, whose single entry
    /// advertises an absurd version and carries the real, signed v1.1.0 disk
    /// image. That is what makes the download, the signature check and the
    /// install exercisable before a release newer than this build exists.
    ///
    /// Nothing about verification is relaxed for it. The bytes that arrive are
    /// checked against `SUPublicEDKey` in the running bundle exactly as they
    /// would be in production; the only thing the switch changes is which URL is
    /// asked. An installed test update leaves 1.1.0 on disk, which is the proof
    /// that it really installed.
    private final class FeedSwitch: NSObject, SPUUpdaterDelegate {
        func feedURLString(for updater: SPUUpdater) -> String? {
            #if DEBUG
            if ReleaseChecker.isPretending {
                return "https://perfectoweb.github.io/Belay/appcast-test.xml"
            }
            #endif
            return nil
        }

        /// Sparkle's own alert says "an error occurred" and nothing else, so
        /// a field report of a failed update used to arrive as a screenshot
        /// of that sentence. The error's chain goes to the local log instead:
        /// with Diagnostics on, the next report can say what actually broke —
        /// a flaky download, a signature refusal, an installer refusal.
        nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
            var failure = error as NSError
            var chain = "update abort domain=\(failure.domain) code=\(failure.code)"
            chain += " error=\"\(failure.localizedDescription)\""
            while let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError {
                failure = underlying
                chain += " <- \(failure.domain)#\(failure.code) \"\(failure.localizedDescription)\""
            }
            Log.app.error("\(chain, privacy: .public)")
            EventLog.note(chain)
        }
    }
    #endif
}
