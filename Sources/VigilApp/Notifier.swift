import UserNotifications
import VigilCore
import VigilSettings
import VigilSupport

/// Native notifications, at most one per event, never repeated for the same
/// session.
///
/// Authorization is requested lazily, the first time a notification would
/// actually fire — asking on launch for a menu bar utility the user has not yet
/// seen do anything is how you get denied permanently (docs/05).
@MainActor
final class Notifier {
    enum Category: String {
        case needsInput = "vigil.needs-input"
        case taskFinished = "vigil.task-finished"
        case safetyRelease = "vigil.safety-release"
    }

    private let centre: UNUserNotificationCenter
    private let settings: SettingsStore
    /// Sessions already announced as waiting, so a session that stays blocked
    /// for fifteen minutes produces one notification rather than fifteen.
    private var announcedWaiting: Set<SessionID> = []
    private var authorization: Bool?

    init(settings: SettingsStore, centre: UNUserNotificationCenter = .current()) {
        self.settings = settings
        self.centre = centre
    }

    /// Acts on what `AnnouncementTrigger` decided is worth saying.
    func handle(_ announcements: [AnnouncementTrigger.Announcement]) async {
        for announcement in announcements {
            switch announcement {
            case .needsInput(let session, let workspace):
                await agentNeedsInput(session: session, workspace: workspace)
            case .finished(let duration, let workspace):
                await taskFinished(duration: duration, workspace: workspace)
            case .releasedForSafety(let reason):
                await releasedForSafety(reason)
            case .resumed(let session):
                forget(session)
            }
        }
    }

    func agentNeedsInput(session: SessionID, workspace: String?) async {
        guard settings.notifyOnAgentNeedsInput, !announcedWaiting.contains(session) else { return }
        announcedWaiting.insert(session)
        let place = workspace.map { " in \($0)" } ?? ""
        await post(
            category: .needsInput,
            title: String(localized: "An agent is waiting for you"),
            body: String(localized: "Your agent needs input\(place) before it can continue.")
        )
    }

    func taskFinished(duration: TimeInterval, workspace: String?) async {
        guard settings.notifyOnTaskFinished, duration >= settings.taskFinishedThreshold else { return }
        let place = workspace.map { " in \($0)" } ?? ""
        let took = ElapsedTime.spoken(duration)
        await post(
            category: .taskFinished,
            title: String(localized: "Your agent finished"),
            body: String(localized: "The run\(place) took \(took). Your Mac will sleep normally again.")
        )
    }

    func releasedForSafety(_ reason: SuspensionReason) async {
        guard settings.notifyOnSafetyRelease else { return }
        let body: String =
            switch reason {
            case .batteryLow(let charge):
                String(
                    localized: """
                        Battery is at \(Int((charge * 100).rounded()))%, so Vigil stopped keeping \
                        your Mac awake.
                        """)
            case .maxDurationReached:
                String(
                    localized: "Vigil reached its maximum awake time and stopped keeping your Mac awake."
                )
            }
        await post(category: .safetyRelease, title: String(localized: "Vigil stopped holding"), body: body)
    }

    /// A session that resumes may block again later, and that is worth saying.
    func forget(_ session: SessionID) {
        announcedWaiting.remove(session)
    }

    private func post(category: Category, title: String, body: String) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.sound = category == .needsInput ? .default : nil

        do {
            try await centre.add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        } catch {
            Log.app.error("could not post notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isAuthorized() async -> Bool {
        if let authorization { return authorization }
        let granted =
            (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        authorization = granted
        if !granted {
            Log.app.notice("notification authorization denied; Vigil stays silent")
        }
        return granted
    }
}
