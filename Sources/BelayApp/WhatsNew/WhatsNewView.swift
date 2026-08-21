import SwiftUI

/// What changed, shown once, on the first launch after an update.
///
/// A card, not a page: a version pill, one headline, a paragraph or two, and
/// a picture running off the bottom edge. Everything is centred because the
/// card is glanced at, not studied, and the only control is the close mark in
/// the corner — there is nothing here to decide.
///
/// It replaced a list of icon rows under a starfield masthead. That window
/// was a small changelog, and a changelog is what `CHANGELOG.md` is for; this
/// one says the single thing the release is about, the way the apps people
/// actually read these cards in do.
struct WhatsNewView: View {
    let notes: [ReleaseNote]
    let onDismiss: () -> Void

    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let width: CGFloat = 400
    static let margin: CGFloat = 32
    /// The picture's box, at the card's full width. Artwork is supplied to
    /// exactly this shape at 2x (800 by 440 pixels).
    static let imageHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            closeRow
            ForEach(Array(notes.enumerated()), id: \.element.version) { position, note in
                card(note)
                    .modifier(
                        WhatsNewEntrance(
                            shown: entered, delay: 0.08 + Double(position) * 0.1,
                            animated: !reduceMotion))
            }
        }
        .frame(width: Self.width)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { entered = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What's New"))
    }

    /// The close mark alone on its line, top right, where the reference puts
    /// it. Escape and Return both close, so the card never traps a keyboard.
    private var closeRow: some View {
        HStack {
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text("Close"))
            Button(action: onDismiss) { EmptyView() }
                .keyboardShortcut(.defaultAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        // The content already sits under a transparent titlebar, which is
        // the top inset; this only keeps the mark off the corner radius.
        .padding(.top, 4)
        .padding(.trailing, 14)
    }

    private func card(_ note: ReleaseNote) -> some View {
        VStack(spacing: 0) {
            Text("New in v\(note.version)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.accentColor))
                .padding(.top, 6)

            Text(note.title)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .padding(.horizontal, Self.margin)

            VStack(spacing: 14) {
                ForEach(note.paragraphs) { paragraph in
                    Text(paragraph.text)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, Self.margin)

            if let image = note.image {
                picture(image)
                    .padding(.top, 26)
            } else {
                Color.clear.frame(height: Self.margin)
            }
        }
    }

    /// Full width, off the bottom edge, and faded in from the card's own
    /// background across its top so any artwork sits on the card rather than
    /// being pasted onto it.
    private func picture(_ name: String) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: Self.width, height: Self.imageHeight)
            .clipped()
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color(nsColor: .windowBackgroundColor), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 70)
            }
            .accessibilityHidden(true)
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
