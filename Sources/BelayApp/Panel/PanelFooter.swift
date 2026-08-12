import SwiftUI

/// Total time held awake this launch, and the way into Settings.
struct PanelFooter: View {
    let totalAwake: TimeInterval
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Awake \(ElapsedTime.compact(totalAwake)) so far")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Kept awake for \(ElapsedTime.spoken(totalAwake)) since Belay started")

            Spacer(minLength: 8)

            SettingsGearButton(action: onOpenSettings)
        }
    }
}

/// The way into Settings: a gear, quiet until the pointer finds it.
///
/// It was the word "Settings" in link blue. A panel this small has one job on
/// screen at a time, and a second blue link under the first one competed with
/// the notice row above it for the same attention. The gear says the same thing
/// in a quarter of the width and stays out of the way until it is wanted.
///
/// Turning by exactly one tooth is the point. `gearshape` has eight, so 45° maps
/// teeth onto teeth: the gear engages and settles rather than spinning to an
/// arbitrary angle, which is what makes it read as a mechanism instead of a
/// rotating picture.
///
/// Animates nothing that can change the panel's height.
private struct SettingsGearButton: View {
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hover only. It used to light on focus as well, and since it was the one
    /// focusable thing in the panel it opened lit, with a focus ring around it —
    /// a resting state that looked like a pressed button. macOS puts plain
    /// buttons in the tab loop only under Full Keyboard Access, and draws its
    /// own ring when it does, which is the behaviour to leave alone.
    private var isLit: Bool { isHovering }

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                // Two `Color`s, deliberately, not `.secondary` and a colour
                // behind `AnyShapeStyle`. Those are different types, so there is
                // nothing to interpolate between, and a spring driving a style
                // it cannot interpolate leaves the gear undrawn for the length
                // of the animation. It reads as a gear that is sometimes
                // missing, which is exactly what the macOS 15 pass found.
                .foregroundStyle(isLit ? Color(nsColor: .linkColor) : Color.primary.opacity(0.55))
                // The colour is quick; only the turn has weight.
                .animation(.easeOut(duration: 0.12), value: isLit)
                .rotationEffect(.degrees(isLit && !reduceMotion ? 45 : 0))
                .animation(.spring(duration: 0.42, bounce: 0.34), value: isLit)
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Open Settings")
        .help(Text("Open Settings"))
    }
}
