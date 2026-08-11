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

            Button(action: onOpenSettings) {
                // Words and nothing else, in `.link` — the same blue as "Fix"
                // two rows up, which is `linkColor` rather than the accent. Two
                // links in one panel drawn in two different blues is the kind of
                // thing you cannot unsee once noticed.
                Text("Settings")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.vertical, 3)
                    .padding(.trailing, 2)
                    .contentShape(.rect)
            }
            .buttonStyle(.link)
            .accessibilityLabel("Open Settings")
        }
    }
}
