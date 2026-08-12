import BelayCore
import SwiftUI

/// Exactly one screen, shown on first launch, dismissible.
///
/// Not a five-step wizard, and it does not ask for notification permission —
/// that is requested lazily the first time a notification would actually fire
/// (docs/05).
///
/// It used to be a grey moon, three paragraphs and a boxed privacy statement,
/// which is a form to be got past rather than an introduction. The order is now
/// the order somebody actually wants it in: the logo says who this is, the
/// scene says what it does, one sentence says why, and only then, quieter and
/// last, what it needs from them. The privacy line stays because it is both
/// true and the argument that gets the app through review, but it is a line
/// under the sentence rather than a box in the middle of the page.
struct OnboardingView: View {
    let providerReady: Bool
    let onGrantAccess: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BelayWordmark(size: 30, word: .primary, animated: true)
                .padding(.top, 30)

            OnboardingScene()
                .padding(.top, 22)

            VStack(spacing: 7) {
                Text("Keeps your Mac awake while your agent works.")
                    .font(.system(size: 15, weight: .semibold))
                Text(
                    """
                    When the work stops, your Mac sleeps as it always did. \
                    Your sleep settings are never changed.
                    """
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 24)
            .padding(.horizontal, 40)

            Spacer(minLength: 14)

            access
            footer
        }
        .frame(width: 470, height: 438)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to \(Branding.appName)")
    }

    /// The ask, deliberately the quietest thing on the page. It is a condition
    /// of the product working, not the product, and leading with a permission
    /// request is how an app reads as something that wants rather than gives.
    @ViewBuilder private var access: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: providerReady ? "checkmark.circle.fill" : "folder")
                .font(.system(size: 12))
                .foregroundStyle(providerReady ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .padding(.top, 1)
            Text(providerReady ? granted : needed)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 18)
    }

    private var granted: LocalizedStringKey {
        "Belay can see your agent's sessions. Nothing else is read, and nothing leaves this Mac."
    }

    private var needed: LocalizedStringKey {
        """
        Belay needs to read ~/.claude to tell when an agent is working. \
        Nothing else is read, and nothing leaves this Mac.
        """
    }

    private var footer: some View {
        HStack {
            Button("Skip for now", action: onDismiss)
                .accessibilityHint("Belay still works in Always on and Off modes")
            Spacer()
            if providerReady {
                Button("Start watching", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Allow access to ~/.claude", action: onGrantAccess)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Opens a standard macOS panel so you can approve the folder")
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 26)
        .padding(.bottom, 24)
    }
}
