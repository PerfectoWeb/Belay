import SwiftUI

/// The one time Belay asks for anything.
///
/// It appears in Statistics, under numbers that are already on screen, and only
/// once the app has actually saved some work: asking before that is asking a
/// stranger for a favour. Pressing either button ends it for good.
///
/// Deliberately not a modal. A menu bar utility that puts a dialogue in front
/// of you has misunderstood what it is, and a dialogue you did not summon is
/// the fastest way to be quit and forgotten. This is a row that sits under the
/// evidence, in the one pane somebody opened on purpose.
struct StarAsk: View {
    /// How many runs must have been rescued before the row appears. Ten is a
    /// week or so of real use: enough that the answer to "was this worth it"
    /// is already on the screen above.
    static let threshold = 10

    let rescued: Int
    @State private var isDismissed = UserDefaults.standard.bool(forKey: StarAsk.key)
    @Environment(\.openURL) private var openURL

    static let key = "belay.starAsk.settled"

    var body: some View {
        if rescued >= Self.threshold, !isDismissed, let repository = Branding.repositoryURL {
            HStack(spacing: 10) {
                Image(systemName: "star")
                    .font(.system(size: 13))
                    .foregroundStyle(.tint)
                Text(
                    """
                    Belay has saved \(rescued) runs for you. A star on GitHub helps the next \
                    person find it.
                    """
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Not now") { settle() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                Button("Star") {
                    openURL(repository)
                    settle()
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .transition(.opacity)
        }
    }

    /// Either answer is an answer. There is no "ask me later", because an app
    /// that asks twice is an app that will ask a third time.
    private func settle() {
        UserDefaults.standard.set(true, forKey: Self.key)
        isDismissed = true
    }
}
