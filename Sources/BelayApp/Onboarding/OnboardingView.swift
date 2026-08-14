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

    /// Whether the screen has arrived. False for exactly one frame.
    ///
    /// The window opens on a first launch, and a screen that is simply *there*
    /// reads as a screenshot of an app rather than an app starting. The four
    /// blocks come up in the order they are read, a breath apart, which also
    /// buys the panel a moment alone before there is anything to read — the
    /// scene inside it is the argument, and it was competing with a heading
    /// from the first frame.
    @State private var entered = false

    /// Somebody who has asked macOS for less motion gets the finished screen,
    /// with no arrival and no delay.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The hero and the words below it are two blocks, not one flow. The hero
    /// is a lit panel with the night sky in it, inset from every edge and
    /// rounded hard enough to read as a screen inside the window rather than a
    /// band across the top. Everything under it shares one left edge: heading,
    /// sentence, buttons, and the line about access. Centred text under a
    /// left-aligned lockup was the old arrangement and it read as a poster.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The panel's place in the stack, so everything below it sits where
            // it always did. The panel itself is drawn behind, because it has to
            // reach higher than this box does.
            Color.clear.frame(height: Self.heroHeight)
            words.modifier(Entrance(shown: entered, delay: 0.10, animated: !reduceMotion))
            buttons.modifier(Entrance(shown: entered, delay: 0.17, animated: !reduceMotion))
            accessLine.modifier(Entrance(shown: entered, delay: 0.24, animated: !reduceMotion))
        }
        .frame(width: 470)
        // Behind, and not in the stack. A view inside a stack cannot grow past
        // the stack's own top edge, and the window adds a titlebar's height to
        // whatever the content asks for, so a taller panel made a taller window
        // with an empty strip along the bottom rather than a panel that reached
        // the top. As a background it is free to ignore the safe area and run up
        // behind the window's buttons, and the window stays the size it was.
        .background(alignment: .top) {
            hero.modifier(Entrance(shown: entered, delay: 0, animated: !reduceMotion))
        }
        .onAppear { entered = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to \(Branding.appName)")
    }

    /// The height of the titlebar the panel now reaches up under. The window is
    /// `.fullSizeContentView`, so this is space the content already owns and was
    /// simply not using.
    static let titlebar: CGFloat = 32

    /// How much of the window the panel occupies, not counting the titlebar it
    /// reaches up under.
    static let heroHeight: CGFloat = 250

    /// The one inset everything below the panel shares, sides and ends alike.
    /// The ends take a little off it: a text's box is taller than its letters,
    /// so matching the side inset by the number draws a bigger gap than the
    /// sides have. The two numbers below were measured off the rendered window
    /// until both ends came out at thirty points of actual space.
    static let margin: CGFloat = 30

    /// Both buttons stand this tall. The standard control is asked for it
    /// directly; the magic one arrives at it through its own padding, because a
    /// custom style has no bezel to stretch.
    static let buttonHeight: CGFloat = 31

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            // The same night sky as About, and for the same reason: a panel
            // that borrows the window's own grey is not a panel, it is a
            // rectangle drawn on the wall. The gradient is what makes it read
            // as something lit from inside.
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.10),
                    Color(red: 0.09, green: 0.10, blue: 0.15)
                ],
                startPoint: .top, endPoint: .bottom)

            Starfield(animated: true)

            // Below the lockup rather than behind it, and centred in what is
            // left, so the scene has a place of its own to grow into.
            OnboardingScene()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, 34 + Self.titlebar)

            // Under the window's buttons, not beside them, and on the same
            // left edge as every line of text below.
            BelayWordmark(size: 22, word: .primary, animated: true)
                .padding(.leading, Self.margin)
                .padding(.top, Self.titlebar + 12)
        }
        .frame(height: Self.heroHeight + Self.titlebar)
        .ignoresSafeArea(.container, edges: .top)
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
        .padding(.horizontal, Self.margin)
        .padding(.top, Self.margin - 4)
    }

    private var buttons: some View {
        HStack(spacing: 7) {
            if providerReady {
                // The key is still "Start watching"; what English shows is
                // "Start Magic". A key here is not the text it displays, and
                // renaming one would rename it in five other languages that
                // still say "start watching" and mean it.
                Button("Start watching", action: onDismiss)
                    .buttonStyle(MagicButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Allow access to ~/.claude", action: onGrantAccess)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint("Opens a standard macOS panel so you can approve the folder")
            }
            // The padding is inside the label on purpose. A bordered button's
            // bezel comes in fixed steps, 28 points at large and 36 at extra
            // large, and it ignores a frame put around it; what it does honour
            // is the size of the label it has to wrap. This is the only way to
            // land between the steps and keep the system's own chrome.
            Button(action: onDismiss) {
                Text("Skip for now").padding(.vertical, (Self.buttonHeight - 28) / 2)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Belay still works in Always on and Off modes")
            Spacer(minLength: 0)
        }
        .controlSize(.large)
        .padding(.horizontal, Self.margin)
        .padding(.top, 22)
    }

    /// Under the buttons rather than above them, and with no icon. The tick
    /// that used to sit here looked like a checkbox somebody had already
    /// ticked on the reader's behalf, which is the wrong thing for a sentence
    /// about what an app may read.
    private var accessLine: some View {
        Text(providerReady ? granted : needed)
            .font(.system(size: 10))
            // Quieter than secondary. It is a condition of the thing working,
            // and at full secondary it was competing with the sentence above
            // it for the same attention.
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Self.margin)
            .padding(.top, 16)
            .padding(.bottom, Self.margin - 2)
    }

    private var granted: LocalizedStringKey {
        """
        Belay can see your agent's sessions.
        Nothing else is read, and nothing leaves this Mac.
        """
    }

    private var needed: LocalizedStringKey {
        """
        Belay needs to read ~/.claude to tell when an agent is working. \
        Nothing else is read, and nothing leaves this Mac.
        """
    }
}

/// One block arriving: up a little, and in.
///
/// The offset is eight points and not thirty. A welcome screen that slides its
/// parts across the window is a title sequence, and this one is followed
/// immediately by two buttons somebody has to aim at; the movement is here to
/// say the screen is alive, not to be watched.
private struct Entrance: ViewModifier {
    var shown: Bool
    var delay: Double
    var animated: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .animation(animated ? .smooth(duration: 0.5).delay(delay) : nil, value: shown)
    }
}
