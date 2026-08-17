import SwiftUI

/// The sparks over the green Update button.
///
/// Its own view because a `ButtonStyle` is not wanted here: the button keeps
/// AppKit's prominent bordered look, its small control size and its green, and
/// only gains something drawn on top. `allowsHitTesting(false)` keeps the click
/// going to the button underneath.
struct UpdateSparks: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Smaller than the welcome screen's halo. That button is 31 points tall and
    /// alone on a dark panel; this one is 20 and sits in a row of checkboxes, so
    /// sparks travelling 26 points reached the caption above it.
    private static let halo: CGFloat = 16

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
                SparkHalo(
                    time: timeline.date.timeIntervalSinceReferenceDate, halo: Self.halo)
            }
            .padding(-Self.halo)
            .allowsHitTesting(false)
        }
    }
}
