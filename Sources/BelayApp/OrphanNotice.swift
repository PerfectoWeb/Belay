import Foundation

extension Notifier {
    /// Orphan Watch found something new. The module's own setting decides
    /// whether this is asked for at all, so there is no guard here.
    func leftBehind(count: Int) async {
        await post(
            category: .orphans,
            title: String(localized: "Left behind by an agent"),
            body: String(
                localized: "Processes that outlived the session that started them: \(count).")
        )
    }
}
