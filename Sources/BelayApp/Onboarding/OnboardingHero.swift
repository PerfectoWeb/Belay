import SwiftUI

/// The lit panel at the top of the welcome window, and the three acts that play
/// inside it once.
///
/// Split from `OnboardingView` because that file is at its length limit and
/// this is the half of it that is a picture rather than a page: the sky, the
/// greeting, the scene and the lockup, and the order they arrive in.
extension OnboardingView {
    var hero: some View {
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

            if skyUp || reduceMotion {
                Starfield(animated: true)
                    .transition(.opacity)
            }

            // Below the lockup rather than behind it, and centred in what is
            // left, so the scene has a place of its own to grow into.
            //
            // The scene is not built until the greeting is done. Building both
            // and hiding one would run the nine-second loop behind the word,
            // and it would arrive already halfway through its story.
            // Reduce Motion is read here, not in `onAppear`, which runs a frame
            // too late and would flash the greeting.
            if greeted || reduceMotion {
                // Pushed past the titlebar: it shares the panel with the lockup.
                OnboardingScene()
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.top, 34 + Self.titlebar)
            } else {
                // Centred in all of the panel, titlebar included: it has the
                // panel to itself, and centring under the titlebar read as low.
                WelcomeFlourish(
                    onWritten: { withAnimation(.easeInOut(duration: 0.8)) { skyUp = true } },
                    onFinished: { withAnimation(.easeInOut(duration: 0.45)) { greeted = true } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            // Under the window's buttons, not beside them, and on the same
            // left edge as every line of text below.
            if skyUp || reduceMotion {
                BelayWordmark(size: 22, word: .primary, animated: true)
                    .transition(.opacity)
                    .padding(.leading, Self.margin)
                    .padding(.top, Self.titlebar + 12)
            }
        }
        .frame(height: Self.heroHeight + Self.titlebar)
        .ignoresSafeArea(.container, edges: .top)
    }
}
