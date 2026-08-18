import BelaySupport
import UserNotifications

/// Turns a click on a notification into the thing the notification was about.
///
/// Only the update one leads anywhere: the other three are statements about
/// something that already happened, and a banner that opens a window when the
/// user brushes it is exactly the interruption this app is supposed to avoid.
final class NotificationClicks: NSObject, UNUserNotificationCenterDelegate {
    /// What to run when the update banner is clicked. Set by the app so this
    /// file knows nothing about windows.
    ///
    /// `@MainActor` on the property rather than the class: the two delegate
    /// methods are called with types the compiler will not carry across an
    /// actor boundary, so the class stays where the system puts it and the hop
    /// is made deliberately, with only a string crossing.
    @MainActor static var onUpdate: () -> Void = {}

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        guard category == Notifier.Category.updateAvailable.rawValue else { return }
        // Static, so the hop carries nothing but the decision already made:
        // sending `self` across is what the compiler refuses, and it is right
        // to, because the system may call this from anywhere.
        await MainActor.run {
            Log.app.notice("update notification clicked")
            Self.onUpdate()
        }
    }

    /// Banners while Belay is frontmost would otherwise be swallowed, and the
    /// app is frontmost exactly when Settings is open, which is where somebody
    /// would be when they turn these on.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
