import SwiftUI

/// The one button on the welcome screen that is asking to be pressed.
///
/// A first-launch screen has two buttons and only one of them is the answer.
/// The standard prominent button says that with colour alone, which on a dark
/// window next to a second button of nearly the same size is not much. This one
/// breathes and throws off sparks, which is a liberty taken exactly once, on a
/// screen shown exactly once.
///
/// The wand lives here rather than in the string, so every language gets it
/// without six translations having to agree about where an icon goes.
struct MagicButtonStyle: ButtonStyle {
    /// How much bigger than the welcome screen's button. The What's New card
    /// asks for 1.2: on a card with no second button to match, the one
    /// button gets to be the size of a button.
    var scale: CGFloat = 1
    /// The label's size when it should not simply follow `scale`; the
    /// padding grows to keep the button's height where the scale put it.
    var textSize: CGFloat?
    /// Points added to (or, negative, taken off) the button's height, for a
    /// card that wants the label and the button tuned separately.
    var heightDelta: CGFloat = 0

    /// Somebody who has asked macOS for less motion gets the same button,
    /// standing still. It is still the coloured one, so it is still the answer.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Face(
            label: configuration.label, pressed: configuration.isPressed, animated: !reduceMotion,
            scale: scale, textSize: textSize ?? 13 * scale, heightDelta: heightDelta)
    }
}

/// Split out because a `ButtonStyle` cannot hold the environment it needs to
/// decide whether to animate, and because the drawing wants somewhere to live.
private struct Face<Label: View>: View {
    let label: Label
    let pressed: Bool
    let animated: Bool
    var scale: CGFloat = 1
    var textSize: CGFloat = 13
    var heightDelta: CGFloat = 0

    /// 30 a second. The breathing is slow and the sparks are small; the
    /// difference against the display's own rate is not visible at this size,
    /// and this window is open for less than a minute.
    private static var tick: TimeInterval { 1.0 / 30 }

    /// One breath. Slow enough to read as alive rather than as a control
    /// flashing for attention: at two seconds it was a notification badge.
    private static var breath: Double { 3.2 }

    /// How far past the button the sparks are allowed to travel. The canvas is
    /// grown by this much in every direction, because a canvas clips to its own
    /// bounds and sparks that stop dead at the button's edge read as a texture
    /// rather than as something leaving.
    private static var halo: CGFloat { 26 }

    var body: some View {
        Group {
            if animated {
                TimelineView(.periodic(from: .now, by: Self.tick)) { timeline in
                    face(at: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                face(at: nil)
            }
        }
    }

    /// `nil` means standing still: the button at the top of its breath, with no
    /// sparks at all.
    private func face(at time: Double?) -> some View {
        let swell = time.map { (sin($0 * 2 * .pi / Self.breath) + 1) / 2 } ?? 1

        return HStack(spacing: 7 * scale) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12 * scale, weight: .semibold))
            label
        }
        // Sized to the button beside it, not to itself. A primary action that
        // is also physically larger than the secondary one reads as a different
        // kind of control, and the row stops looking like a row.
        .font(.system(size: textSize, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16 * scale)
        // Half the text's shortfall on each side, so a smaller label does not
        // shrink the button.
        .padding(.vertical, 7.5 * scale + (13 * scale - textSize) / 2 + heightDelta / 2)
        .background {
            Capsule(style: .continuous)
                .fill(Color.accentColor)
                // Brightness rather than opacity: fading a button towards the
                // window behind it makes it look disabled on the way down.
                .brightness(0.03 + 0.05 * swell)
                .shadow(color: Color.accentColor.opacity(0.25 + 0.3 * swell), radius: 6 + 7 * swell)
        }
        .overlay {
            SparkHalo(time: time, halo: Self.halo)
                .padding(-Self.halo)
                .allowsHitTesting(false)
        }
        .scaleEffect(pressed ? 0.97 : 1)
        .opacity(pressed ? 0.85 : 1)
        .animation(.easeOut(duration: 0.12), value: pressed)
    }

}
