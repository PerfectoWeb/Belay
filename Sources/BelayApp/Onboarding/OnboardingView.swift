import BelayCore
import SwiftUI

/// Exactly one screen, shown on first launch, dismissible.
///
/// Not a five-step wizard, and it does not ask for notification permission —
/// that is requested lazily the first time a notification would actually fire
/// (docs/05). The privacy statement is the centrepiece because it is both the
/// honest thing to lead with and the argument that gets the app through review.
struct OnboardingView: View {
    let providerReady: Bool
    let onGrantAccess: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Text(
                """
                Belay keeps your Mac awake while a local AI coding agent is working, \
                and lets it sleep normally the moment everything goes quiet. \
                Your sleep settings are never changed.
                """
            )
            .fixedSize(horizontal: false, vertical: true)

            privacyStatement

            Spacer(minLength: 0)
            buttons
        }
        .padding(28)
        .frame(width: 460)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Belay")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Welcome to \(Branding.appName)")
                .font(.title2)
                .bold()
        }
    }

    private var privacyStatement: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("What Belay reads", systemImage: "lock.shield")
                    .font(.headline)
                Text(
                    """
                    Belay reads only enough of your local agent's session files to know \
                    whether it is running. It never reads your prompts or your code, and \
                    nothing ever leaves your Mac.
                    """
                )
                .fixedSize(horizontal: false, vertical: true)
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            Button("Skip for now", action: onDismiss)
                .accessibilityHint("Belay still works in Always on and Off modes")
            Spacer()
            if providerReady {
                Button("Start watching", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Grant access to ~/.claude", action: onGrantAccess)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Opens a standard macOS panel so you can approve the folder")
            }
        }
    }
}
