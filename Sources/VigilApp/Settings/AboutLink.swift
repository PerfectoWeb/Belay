import SwiftUI

/// One of the three links at the foot of the About pane.
struct AboutLink: View {
    let title: LocalizedStringKey
    let symbol: String
    let url: URL
    /// Exactly one link on this page gets the accent. Two would be a toolbar.
    var isProminent = false
    /// Plays as the link opens. Only Donate sets one: the browser is about to
    /// take the window, and this is the last thing Vigil gets to say.
    var sound: Feedback.Sound?

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if isProminent {
                    Capsule().fill(Color.accentColor.opacity(isHovering ? 0.85 : 1))
                } else {
                    Capsule().fill(Color.primary.opacity(isHovering ? 0.16 : 0.09))
                }
            }
            // A button that does not answer the pointer looks disabled, and a
            // button that does not answer the click looks broken.
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in
                    isPressed = false
                    if let sound { Feedback.play(sound) }
                }
        )
        .accessibilityLabel(title)
    }
}
