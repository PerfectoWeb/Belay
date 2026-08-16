import SwiftUI

/// The lit panel above the release notes: who is talking on the left, what this
/// window is on the right.
///
/// The same night sky as the welcome screen and About, at half the height it
/// started at. It is a masthead, not a stage: there is no scene to play, so the
/// panel says which app and which version, names the window, and gets out of the
/// way of the list.
///
/// The title lives up here rather than as a heading below it. Down there it was
/// a third block competing with the first item for the top of the page, and it
/// pushed the news thirty points further from the eye for nothing. Up here it
/// does what a masthead does: says what you are looking at.
extension WhatsNewView {
    var hero: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.10),
                    Color(red: 0.09, green: 0.10, blue: 0.15)
                ],
                startPoint: .top, endPoint: .bottom)

            // Alive, exactly as on the welcome screen. A still starfield under a
            // still wordmark does not read as restraint, it reads as a window
            // that has hung.
            Starfield(animated: true)

            // Centres, not baselines. The wordmark is a lockup rather than a
            // line of text: it carries a mark beside its word, so its optical
            // middle is what should line up with the block opposite, and a
            // shared baseline sat it low against a two-line stack.
            HStack(alignment: .center) {
                BelayWordmark(size: 24, word: .white, animated: true)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("What's New")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(verbatim: newest)
                        // Against the dark panel, not against the window, so this
                        // stays legible whatever the system appearance is.
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, Self.margin)
            // The titlebar is space the panel reaches up under, so the lockup is
            // centred in what is left rather than under the traffic lights.
            .padding(.top, Self.titlebar)
        }
        .frame(height: Self.heroHeight + Self.titlebar)
        .ignoresSafeArea()
    }

    /// The newest version being announced. `notes` arrives newest first, and is
    /// never empty: the window is not opened without something to say.
    ///
    /// The number alone. The name is already spelled out in the wordmark on the
    /// other side of the same line.
    private var newest: String {
        notes.first?.version ?? Branding.version
    }
}
