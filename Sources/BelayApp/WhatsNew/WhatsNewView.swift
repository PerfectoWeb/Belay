import SwiftUI

/// What changed, shown once, on the first launch after an update.
///
/// The same window as the welcome screen and deliberately so: same width, same
/// margin, same lit panel at the top, same one button that is clearly the
/// answer. Somebody meeting this screen has met the other one, and a second
/// chrome for the same kind of moment would read as a different app.
///
/// What it does **not** borrow is the twelve-second scene. That plays once, to
/// explain the product to somebody who has not used it. This audience has used
/// it for months and wants to know what is different, so the panel is a third
/// of the height and holds the mark and a version, nothing that moves for long.
struct WhatsNewView: View {
    let notes: [ReleaseNote]
    let onDismiss: () -> Void

    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Matched to `OnboardingView` on purpose. The two windows open on the same
    /// Mac weeks apart and any difference in these numbers reads as sloppiness
    /// rather than as variety.
    static let width: CGFloat = 470
    static let margin: CGFloat = 30
    static let titlebar: CGFloat = 32
    static let heroHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Self.heroHeight)
            heading.modifier(WhatsNewEntrance(shown: entered, delay: 0.06, animated: !reduceMotion))
            list.modifier(WhatsNewEntrance(shown: entered, delay: 0.13, animated: !reduceMotion))
            button.modifier(WhatsNewEntrance(shown: entered, delay: 0.20, animated: !reduceMotion))
        }
        .frame(width: Self.width)
        .background(alignment: .top) {
            hero.modifier(WhatsNewEntrance(shown: entered, delay: 0, animated: !reduceMotion))
        }
        .onAppear { entered = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What's New"))
    }

    private var heading: some View {
        Text("What's New")
            .font(.system(size: 18, weight: .semibold))
            .padding(.horizontal, Self.margin)
            .padding(.top, Self.margin - 6)
    }

    /// One row per item, and a version line above each group when more than one
    /// version is being announced at once.
    ///
    /// A plain stack, and no scroll view. Two were tried. A `ScrollView` has no
    /// height of its own to report, so a window sized from its content gets
    /// whatever the scroll view guesses and clips the last item mid-sentence;
    /// wrapping it in `ViewThatFits` moved the guess without fixing it. The
    /// window grows with the list instead, and `WhatsNewDecision` caps how many
    /// items can reach it, which bounds the height where it can actually be
    /// reasoned about.
    private var list: some View {
        // Wider between versions than between the items inside one, so a
        // version heading reads as a break rather than as another row.
        VStack(alignment: .leading, spacing: 26) {
            ForEach(notes, id: \.version) { note in
                VStack(alignment: .leading, spacing: 18) {
                    if notes.count > 1 {
                        // Only when somebody skipped a release. With one version
                        // it repeats the panel above it.
                        Text(verbatim: note.version)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(note.items) { item in
                        WhatsNewRow(item: item)
                    }
                }
            }
        }
        .padding(.horizontal, Self.margin)
        .padding(.vertical, 18)
    }

    private var button: some View {
        HStack {
            Button("Continue", action: onDismiss)
                .buttonStyle(MagicButtonStyle())
                .keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
        .controlSize(.large)
        .padding(.horizontal, Self.margin)
        .padding(.top, 4)
        .padding(.bottom, Self.margin - 2)
    }
}

/// One line of news: symbol, title, sentence.
///
/// The symbol is in a fixed-width column so every title starts on the same
/// vertical line whatever glyph is beside it. Left to itself an SF Symbol is as
/// wide as it needs to be, and a list of them is a ragged left edge.
private struct WhatsNewRow: View {
    let item: ReleaseNote.Item

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: item.symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 24, alignment: .center)
                // Aligned to the title's cap height rather than its box, which
                // sits a symbol visibly low against a 13-point line.
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(item.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
