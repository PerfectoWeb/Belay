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
                .accessibilityLabel("Kept awake for \(ElapsedTime.spoken(totalAwake)) since Vigil started")

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
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLit: Bool { isHovering || isFocused }

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    isLit ? AnyShapeStyle(Color(nsColor: .linkColor)) : AnyShapeStyle(.secondary)
                )
                .rotationEffect(.degrees(isLit && !reduceMotion ? 45 : 0))
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($isFocused)
        .onHover { isHovering = $0 }
        // The colour is quick, the turn has weight. One animation for both makes
        // the colour feel sluggish or the gear feel snapped.
        .animation(.easeOut(duration: 0.12), value: isLit)
        .animation(.spring(duration: 0.42, bounce: 0.34), value: isLit)
        .accessibilityLabel("Open Settings")
        .help(Text("Open Settings"))
    }
}
