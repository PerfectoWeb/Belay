import Foundation

/// What the nudge plays. A double stands in for it in tests.
@MainActor
protocol NudgeSounds {
    func play(_ sound: Feedback.Sound)
}

/// What the nudge says out loud besides sounds: the banners, and what the
/// notification centre thinks of Belay.
@MainActor
protocol NudgeNotices {
    /// `bundleID` is the app a click on the banner brings forward.
    func post(title: String, body: String, raising bundleID: String?)
    /// Asks macOS for permission if it was never asked; true when allowed.
    func authorize() async -> Bool
    /// True when the person said no in System Settings.
    func isRefused() async -> Bool
}

struct FeedbackSounds: NudgeSounds {
    func play(_ sound: Feedback.Sound) { Feedback.play(sound) }
}

/// Banners through `Notifier`, which owns the notification centre.
@MainActor
struct NotifierNotices: NudgeNotices {
    let notifier: Notifier

    func post(title: String, body: String, raising bundleID: String?) {
        Task { await notifier.nudge(title: title, body: body, raising: bundleID) }
    }

    func authorize() async -> Bool { await notifier.authorize() }
    func isRefused() async -> Bool { await notifier.isRefused() }
}

/// Until the controller hands over the notifier, nothing is said.
struct NoNotices: NudgeNotices {
    func post(title: String, body: String, raising bundleID: String?) {}
    func authorize() async -> Bool { true }
    func isRefused() async -> Bool { false }
}
