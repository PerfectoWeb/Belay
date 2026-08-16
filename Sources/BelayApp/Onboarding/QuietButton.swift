import SwiftUI

/// The secondary button on the welcome screen, drawn rather than borrowed.
///
/// It used to be `.bordered`, which is the right instinct: the system knows how
/// a secondary button should look, and it changes that look between releases so
/// that an app keeps up without being touched. The problem is that it changed
/// it a lot. On macOS 26 the bordered button beside Start Magic is a quiet
/// translucent capsule; on macOS 15 it is a heavier grey slab with a visible
/// edge, and next to a hand-drawn primary button the pair stopped reading as a
/// pair. Found on a real macOS 15 machine, not guessed at.
///
/// So this draws the macOS 26 shape everywhere. The geometry is copied from
/// `MagicButtonStyle` on purpose: same font, same padding, same capsule, so the
/// two are the same height and the same corner without either one being
/// measured against the other by hand.
///
/// The fill is `primary` at a low opacity rather than a fixed grey, so it is
/// dark type on light in a light window and the reverse in a dark one, which is
/// what a system button would have done.
struct QuietButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Medium, where the primary button is semibold. The two are a
            // pair and should read as one, but not as equals: the lighter
            // weight is what says which of them is the answer. The size is
            // untouched, so both are still the same height.
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7.5)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.16 : 0.10))
            }
            .contentShape(Capsule(style: .continuous))
            .onHover { hovering = $0 }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
