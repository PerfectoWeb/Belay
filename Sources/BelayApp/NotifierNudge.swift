import UserNotifications

extension Notifier {
    /// The userInfo key a Nudge banner carries the app to raise under.
    nonisolated static let raiseKey = "belay.raise"

    static func content(
        category: Category, title: String, body: String, userInfo: [String: String] = [:]
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.userInfo = userInfo
        content.sound = category == .needsInput ? .default : nil
        return content
    }

    /// The Nudge module's banners. `bundleID` rides in the notification so the
    /// click handler knows which app to bring forward.
    func nudge(title: String, body: String, raising bundleID: String?) async {
        let info = bundleID.map { [Self.raiseKey: $0] } ?? [:]
        await post(category: .nudge, title: title, body: body, userInfo: info)
    }

    /// Asks macOS for permission if it was never asked.
    func authorize() async -> Bool { await isAuthorized() }

    /// True only when the person refused in System Settings.
    func isRefused() async -> Bool {
        await centre.notificationSettings().authorizationStatus == .denied
    }
}
