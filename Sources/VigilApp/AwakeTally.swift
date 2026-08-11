import Foundation

/// Running total of how long Vigil has held the Mac awake this launch.
///
/// Folded from successive snapshots rather than timed independently, so a hold
/// that starts and ends between two refreshes is still counted.
struct AwakeTally {
    private var completed: TimeInterval = 0
    private var currentHoldStart: Date?

    mutating func update(holdingSince: Date?, now: Date = Date()) -> TimeInterval {
        switch (currentHoldStart, holdingSince) {
        case (nil, let started?):
            currentHoldStart = started
        case (let previous?, nil):
            completed += now.timeIntervalSince(previous)
            currentHoldStart = nil
        case (let previous?, let started?) where previous != started:
            // A new hold began without us seeing the gap; bank the old one.
            completed += started.timeIntervalSince(previous)
            currentHoldStart = started
        default:
            break
        }
        guard let currentHoldStart else { return completed }
        return completed + now.timeIntervalSince(currentHoldStart)
    }
}
