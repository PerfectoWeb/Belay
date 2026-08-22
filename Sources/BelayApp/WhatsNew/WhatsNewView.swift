import SwiftUI

/// What changed, shown once, on the first launch after an update.
///
/// Drawn to the designer's card: the wordmark on top, a green version pill
/// under it, a list of outlined icons with a title and a sentence each, a
/// violet glow rising from the bottom, and one blue button that is the
/// answer. Dark in both appearances, like the welcome screen it shares a
/// wordmark with — the card is a small piece of night, not a settings sheet.
struct WhatsNewView: View {
    let notes: [ReleaseNote]
    let onDismiss: () -> Void

    @State private var entered = false
    @State private var closeHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    static let width: CGFloat = 600
    static let margin: CGFloat = 50
    /// The icon column and the gap after it: every title starts at x = 97.
    static let iconColumn: CGFloat = 30
    static let iconGap: CGFloat = 17
    static let cornerRadius: CGFloat = 24

    static let background = Color(red: 0.118, green: 0.118, blue: 0.125)
    static let glow = Color(red: 0.26, green: 0.24, blue: 0.47)
    static let pill = Color(red: 0.20, green: 0.68, blue: 0.36)
    static let icon = Color(red: 0.24, green: 0.52, blue: 0.98)
    static let body = Color(white: 0.62)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                BelayWordmark(size: 28, word: .white, animated: true)
                    .padding(.top, 52)
                ForEach(notes, id: \.version) { note in
                    Text("New in v\(note.version)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.pill))
                        .padding(.top, 16)
                    list(note)
                        .padding(.top, 22)
                }
                footer
                    .padding(.top, 36)
                    .padding(.bottom, Self.margin)
            }
            .frame(width: Self.width)
            // One background, built as one picture: the solid card with the
            // glow — violet-blue rising into the last rows, the one piece of
            // colour the card has besides its marks — painted on top of it.
            // Two separate `background` modifiers were tried both ways round;
            // one hid the glow, the other left the card see-through.
            .background {
                ZStack(alignment: .bottom) {
                    Self.background
                    LinearGradient(
                        colors: [.clear, Self.glow.opacity(0.6)], startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 280)
                }
            }
            .modifier(WhatsNewEntrance(shown: entered, delay: 0.05, animated: !reduceMotion))

            closeButton
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .preferredColorScheme(.dark)
        .onAppear { entered = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What's New"))
    }

    /// Dim until the pointer arrives, white under it. Escape closes too.
    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(closeHovered ? Color.white : Color(white: 0.45))
                .frame(width: 30, height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { closeHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: closeHovered)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel(Text("Close"))
        .padding(.top, 14)
        .padding(.trailing, 14)
    }

    private func list(_ note: ReleaseNote) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(note.items) { item in
                WhatsNewRow(item: item)
            }
        }
        .padding(.horizontal, Self.margin)
    }

    /// The button in the text column, and the changelog beside it for anyone
    /// who wants the whole story.
    private var footer: some View {
        HStack(spacing: 22) {
            Button("Sounds Good!", action: onDismiss)
                .buttonStyle(MagicButtonStyle())
                .keyboardShortcut(.defaultAction)
            Button {
                if let url = Branding.repositoryURL?.appendingPathComponent("blob/main/CHANGELOG.md") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Release notes")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.leading, Self.margin + Self.iconColumn + Self.iconGap)
        .padding(.trailing, Self.margin)
    }
}

/// One line of news: outline, title, sentence.
private struct WhatsNewRow: View {
    let item: ReleaseNote.Item

    var body: some View {
        HStack(alignment: .top, spacing: WhatsNewView.iconGap) {
            Image(systemName: item.symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(WhatsNewView.icon)
                .frame(width: WhatsNewView.iconColumn, height: 26, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(item.body)
                    .font(.system(size: 13))
                    .foregroundStyle(WhatsNewView.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The same arrival as the welcome screen's, and the same reasoning: enough
/// movement to say the window is alive, not enough to be watched.
private struct WhatsNewEntrance: ViewModifier {
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
