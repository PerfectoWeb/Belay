import SwiftUI

/// The lit panel above the release notes: the mark, the name, the version.
///
/// The same night sky as the welcome screen and About, at a third of the
/// welcome screen's height. It is a masthead, not a stage: there is no scene to
/// play and nothing to explain, so the panel's job is to say which app is
/// talking and which version has arrived, and then get out of the way of the
/// list.
///
/// The version is drawn here rather than in the heading below because it is
/// identification, not news. "What's New" is the sentence; "Belay 1.3.0" is the
/// letterhead.
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

            VStack(spacing: 3) {
                BelayWordmark(size: 20, word: .white, animated: true)
                Text(verbatim: newest)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    // Against the dark panel, not against the window, so this
                    // stays legible whatever the system appearance is.
                    .foregroundStyle(.white.opacity(0.55))
            }
            // The titlebar is space the panel reaches up under, and centring in
            // the whole panel would sit the lockup under the traffic lights.
            .padding(.top, Self.titlebar)
        }
        .frame(height: Self.heroHeight + Self.titlebar)
        .ignoresSafeArea()
    }

    /// The newest version being announced. `notes` arrives newest first, and is
    /// never empty: the window is not opened without something to say.
    ///
    /// The number alone. The name is already spelled out in the wordmark
    /// directly above it, and "Belay 1.3.0" under a word that says *belay* is
    /// the app introducing itself twice in two lines.
    private var newest: String {
        notes.first?.version ?? Branding.version
    }
}
