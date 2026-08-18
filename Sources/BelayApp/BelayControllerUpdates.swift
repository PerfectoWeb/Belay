import Foundation

/// The one thing the controller does about updates.
///
/// Split out rather than added to `BelayController`, which is at the length
/// limit. It belongs to the controller because the notifier does, while the
/// update checker itself lives a layer away in Settings.
extension BelayController {
    /// Says a version exists, at most once per version.
    func announceUpdate(version: String) async {
        await notifier.updateAvailable(version: version)
    }
}
