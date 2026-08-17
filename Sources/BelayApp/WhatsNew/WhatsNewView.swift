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

    /// One counter per icon. Bumping a row's counter is what makes its symbol
    /// bounce, because `symbolEffect` fires on a change of value rather than on
    /// a flag being true.
    @State private var beats: [Int] = []

    /// Whose turn it is. Counts past the last row on purpose: those extra ticks
    /// are the rest between waves, and without them the wave reads as a loop
    /// that never lets go.
    @State private var turn = 0
    @State private var ticker: Timer?

    /// Matched to `OnboardingView` on purpose. The two windows open on the same
    /// Mac weeks apart and any difference in these numbers reads as sloppiness
    /// rather than as variety.
    static let width: CGFloat = 470
    static let margin: CGFloat = 30
    static let titlebar: CGFloat = 32
    static let heroHeight: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: Self.heroHeight)
            list.modifier(WhatsNewEntrance(shown: entered, delay: 0.10, animated: !reduceMotion))
            button.modifier(WhatsNewEntrance(shown: entered, delay: 0.17, animated: !reduceMotion))
        }
        .frame(width: Self.width)
        .background(alignment: .top) {
            hero.modifier(WhatsNewEntrance(shown: entered, delay: 0, animated: !reduceMotion))
        }
        .onAppear {
            entered = true
            startTheWave()
        }
        .onDisappear {
            ticker?.invalidate()
            ticker = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("What's New"))
    }

    /// Every icon in reading order, one at a time, then a pause.
    ///
    /// The whole point is the waiting. Bouncing all four at once is a jingle;
    /// bouncing them in turn is the eye being walked down the list, which is
    /// what the icons are for. `rest` is four ticks of nothing at the end, so
    /// the wave finishes rather than churns.
    ///
    /// Cheap by construction: one state write every 0.5 seconds, and only the
    /// symbol whose counter changed is redrawn. The starfield above it costs
    /// more than this does by two orders of magnitude.
    ///
    /// Nothing runs under Reduce Motion, and nothing runs after the window
    /// closes.
    private func startTheWave() {
        let count = notes.reduce(0) { $0 + $1.items.count }
        beats = Array(repeating: 0, count: count)
        guard !reduceMotion, count > 0 else { return }

        let rest = 4
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                if turn < beats.count { beats[turn] += 1 }
                turn = (turn + 1) % (beats.count + rest)
            }
        }
    }

    /// Where a row sits in the flattened list, which is what its counter is
    /// indexed by. Versions are shown one after another, so the second version's
    /// first row continues the first version's numbering rather than restarting.
    private func beat(forVersionAt version: Int, item: Int) -> Int {
        let before = notes.prefix(version).reduce(0) { $0 + $1.items.count }
        let index = before + item
        return index < beats.count ? beats[index] : 0
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
            ForEach(Array(notes.enumerated()), id: \.element.version) { position, note in
                VStack(alignment: .leading, spacing: 18) {
                    if notes.count > 1 {
                        // Only when somebody skipped a release. With one version
                        // it repeats the panel above it.
                        Text(verbatim: note.version)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(note.items.enumerated()), id: \.element.id) { row, item in
                        WhatsNewRow(
                            item: item,
                            beat: beat(forVersionAt: position, item: row))
                    }
                    if !note.asides.isEmpty {
                        WhatsNewAsides(asides: note.asides)
                    }
                }
            }
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, Self.margin - 6)
        .padding(.bottom, 18)
    }

    private var button: some View {
        HStack {
            // Not "Continue", which is what a form says. This window interrupted
            // somebody once, on purpose, and the button should sound like the
            // end of the interruption rather than the next step of one.
            Button("Back to work", action: onDismiss)
                .buttonStyle(MagicButtonStyle())
                .keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
        .controlSize(.large)
        // 37 is the symbol column plus its gap, the same inset the asides use,
        // so the button's left edge lands on the vertical line every title
        // starts from. Against the window margin instead, it sat a symbol's
        // width to the left of everything above it and read as belonging to the
        // window rather than to the list.
        .padding(.leading, Self.margin + 37)
        .padding(.trailing, Self.margin)
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

    /// Changes when it is this row's turn to bounce, and at no other time.
    let beat: Int

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: item.symbol)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, options: .nonRepeating, value: beat)
                .frame(width: 24, alignment: .center)
                // Aligned to the title's cap height rather than its box, which
                // sits a symbol visibly low against a 13-point line.
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
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

/// The short list under the rows: everything real that is not worth an icon.
///
/// Indented to the titles above rather than to the margin, so it reads as the
/// tail of the list instead of a second list. No bullets: three left-aligned
/// lines are already a list, and a glyph in front of each would be the fourth
/// column of marks on a screen that has three.
private struct WhatsNewAsides: View {
    let asides: [ReleaseNote.Aside]

    var body: some View {
        // Tighter than the rows above. These are one-line facts, not sentences
        // that need air between them, and at the row spacing they read as four
        // separate items rather than one short list.
        VStack(alignment: .leading, spacing: 3) {
            Text("Also")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 1)
            ForEach(asides) { aside in
                Text(aside.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 24 for the symbol column plus the 13 beside it, so these start on the
        // same vertical line as every title above them.
        .padding(.leading, 37)
        .padding(.top, 2)
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
