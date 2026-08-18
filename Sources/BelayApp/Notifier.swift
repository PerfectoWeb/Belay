import BelayCore
import BelaySettings
import BelaySupport
import UserNotifications

/// Native notifications, at most one per event, never repeated for the same
/// session.
///
/// Authorization is requested lazily, the first time a notification would
/// actually fire — asking on launch for a menu bar utility the user has not yet
/// seen do anything is how you get denied permanently (docs/05).
@MainActor
final class Notifier {
    enum Category: String {
        case needsInput = "belay.needs-input"
        case taskFinished = "belay.task-finished"
        case safetyRelease = "belay.safety-release"
        case wentQuiet = "belay.went-quiet"
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
            case .wentQuiet(let session, let workspace):
                await agentWentQuiet(session: session, workspace: workspace)
            }
        }
    }

    func agentNeedsInput(session: SessionID, workspace: String?) async {
        guard settings.notifyOnAgentNeedsInput, !announcedWaiting.contains(session) else { return }
        announcedWaiting.insert(session)
        // Two whole sentences, not one sentence with a " in \(workspace)"
        // fragment dropped into it. That fragment was assembled in English and
        // then interpolated into a translated string, so a Russian
        // notification read "Запуск in Belay завершился" and no translator
        // could have fixed it: the word was not in the catalogue.
        let body =
            workspace.map { String(localized: "Your agent needs input in \($0) before it can continue.") }
            ?? String(localized: "Your agent needs input before it can continue.")
        await post(
            category: .needsInput,
            title: String(localized: "An agent is waiting for you"),
            body: body
        )
    }

    /// Said when a session that was working disappeared without finishing.
    ///
    /// Forgets the session first: it may have been announced as waiting earlier,
    /// and a session that has gone is not going to resume and clear that mark
    /// itself.
    func agentWentQuiet(session: SessionID, workspace: String?) async {
        forget(session)
        guard settings.notifyOnAgentWentQuiet else { return }
        let body =
            workspace.map {
                String(
                    localized:
                        "The agent in \($0) stopped without finishing. It may need signing in again."
                )
            }
            ?? String(localized: "The agent stopped without finishing. It may need signing in again.")
        await post(
            category: .wentQuiet,
            title: String(localized: "An agent went quiet"),
            body: body
        )
    }

    func taskFinished(duration: TimeInterval, workspace: String?) async {
        guard settings.notifyOnTaskFinished, duration >= settings.taskFinishedThreshold else { return }
        let took = ElapsedTime.spoken(duration)
        let body =
            workspace.map {
                String(localized: "The run in \($0) took \(took). Your Mac will sleep normally again.")
            } ?? String(localized: "The run took \(took). Your Mac will sleep normally again.")
        await post(
            category: .taskFinished,
            title: String(localized: "Your agent finished"),
            body: body
        )
    }

    func releasedForSafety(_ reason: SuspensionReason) async {
        guard settings.notifyOnSafetyRelease else { return }
        let body: String =
            switch reason {
            case .batteryLow(let charge):
                String(
                    localized: """
                        Battery is at \(Int((charge * 100).rounded()))%, so Belay stopped keeping \
                        your Mac awake.
                        """)
            case .maxDurationReached:
                String(
                    localized: "Belay reached its maximum awake time and stopped keeping your Mac awake."
                )
            }
        await post(category: .safetyRelease, title: String(localized: "Belay stopped holding"), body: body)
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
            Log.app.notice("notification authorization denied; Belay stays silent")
        }
        return granted
    }
}
