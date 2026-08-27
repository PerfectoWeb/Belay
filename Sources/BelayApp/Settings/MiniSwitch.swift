import SwiftUI

/// A switch drawn in SwiftUI instead of hosted from AppKit.
///
/// `NSSwitch` animates its knob into place when it is created already on,
/// and a Settings window busy with its first layout freezes that entrance:
/// a solid blue capsule with no knob for a second or two, on every open of
/// this pane. Two rounds of animation-suppression did not cure it, because
/// the slide belongs to AppKit, not to SwiftUI. A drawn switch has no
/// entrance to freeze — the first frame is the true state — and the only
/// thing that ever animates is a real click.
struct MiniSwitch: View {
    let isOn: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .circular)
                .fill(isOn ? Color.accentColor : Color.primary.opacity(0.18))
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.25), radius: 0.7, y: 0.5)
                .padding(1)
        }
        .frame(width: 22, height: 13)
        .animation(.easeOut(duration: 0.16), value: isOn)
        .contentShape(Rectangle())
        .onTapGesture { toggle(!isOn) }
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { isOn }, set: toggle)) { EmptyView() }
        }
    }
}
