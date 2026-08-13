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

    /// The hero and the words below it are two blocks, not one flow. The hero
    /// is a lit panel with the night sky in it, inset from every edge and
    /// rounded hard enough to read as a screen inside the window rather than a
    /// band across the top. Everything under it shares one left edge: heading,
    /// sentence, buttons, and the line about access. Centred text under a
    /// left-aligned lockup was the old arrangement and it read as a poster.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            words
            buttons
            accessLine
        }
        .frame(width: 470, height: 520)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to \(Branding.appName)")
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            Starfield(animated: true)
            OnboardingScene()
                .padding(.top, 26)
            BelayWordmark(size: 22, word: .primary, animated: true)
                .padding(20)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
        .padding(.horizontal, 22)
        .padding(.top, 22)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Keeps your Mac awake while your agent works.")
                .font(.system(size: 18, weight: .semibold))
            Text(
                """
                When the work stops, your Mac sleeps as it always did. \
                Your sleep settings are never changed.
                """
            )
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 30)
        .padding(.top, 26)
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if providerReady {
                Button("Start watching", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Allow access to ~/.claude", action: onGrantAccess)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Opens a standard macOS panel so you can approve the folder")
            }
            Button("Skip for now", action: onDismiss)
                .accessibilityHint("Belay still works in Always on and Off modes")
            Spacer(minLength: 0)
        }
        .controlSize(.large)
        .padding(.horizontal, 30)
        .padding(.top, 22)
    }

    /// Under the buttons rather than above them, and with no icon. The tick
    /// that used to sit here looked like a checkbox somebody had already
    /// ticked on the reader's behalf, which is the wrong thing for a sentence
    /// about what an app may read.
    private var accessLine: some View {
        Text(providerReady ? granted : needed)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 30)
            .padding(.top, 18)
            .padding(.bottom, 30)
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
}
