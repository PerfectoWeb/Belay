import SwiftUI

/// The panel's one-line explanation, with a way out if it ever does not fit.
///
/// Every status sentence is written and measured to fit this on one line in all
/// six languages, and `LocalizationTests` fails if one stops fitting. This is
/// what happens anyway: a sentence too wide is cut with an ellipsis, and resting
/// the pointer on it walks the text far enough left to read the end.
///
/// The alternative was reserving two lines for a sentence that needs one, which
/// is what this replaced. It left a gap under every status that looked like room
/// for a third line, and the block has to be a fixed height or the panel jumps
/// as you switch modes.
///
/// Animates nothing that can change the panel's height.
struct PanelDetailText: View {
    let text: String

    /// One line of the 11 pt detail font. `PanelHeightStabilityTests` fails if
    /// this stops holding every state to the same height.
    static let lineHeight: CGFloat = 15
    /// Points per second. Slow enough to read, fast enough that a sentence a
    /// third too long is over in a second.
    private static let speed: CGFloat = 26
    /// A beat before setting off, so passing the pointer across the row does not
    /// start a sentence moving behind the cursor.
    private static let leadIn: TimeInterval = 0.35
    private static let returnDuration: TimeInterval = 0.18

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    /// Drawn at full width rather than truncated. Not the same as hovering: it
    /// stays on through the walk back, or the sentence would snap to its
    /// ellipsis while still sliding.
    @State private var isExpanded = false
    /// Bumped on every hover change so a pointer flicked across the row cannot
    /// have an older exit tidy up after a newer entry.
    @State private var generation = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var overflow: CGFloat { max(textWidth - boxWidth, 0) }

    var body: some View {
        // The sentence lives in an overlay, and that is the whole trick. An
        // overlay is handed its host's size and can never push back, so a
        // sentence drawn at full natural width has no way to widen the panel.
        // Laid out inline instead, `fixedSize` proposes that natural width all
        // the way up the tree, and the panel grew every time the pointer
        // arrived: the ellipsis was fixed and the panel started flinching.
        Color.clear
            .frame(height: Self.lineHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) { sentence }
            .clipped()
            .background { measureBox }
            .background(alignment: .leading) { measureText }
            .contentShape(.rect)
            .onHover(perform: walk)
            .help(overflow > 0 ? Text(verbatim: text) : Text(verbatim: ""))
    }

    private var sentence: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(contrast == .increased ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            // Pinned to the measured box while it is still, which is what puts
            // the ellipsis there; at its own width while walking, which is what
            // there is to read.
            .fixedSize(horizontal: isExpanded, vertical: false)
            .frame(width: isExpanded || boxWidth == 0 ? nil : boxWidth, alignment: .leading)
            .offset(x: offset)
    }

    private var measureBox: some View {
        GeometryReader { box in
            Color.clear
                .onAppear { boxWidth = box.size.width }
                .onChange(of: box.size.width) { _, width in boxWidth = width }
        }
    }

    /// The sentence at its natural width, drawn nowhere. Comparing it with the
    /// box is the only way to know whether there is anything to walk.
    private var measureText: some View {
        Text(text)
            .font(.system(size: 11))
            .lineLimit(1)
            .fixedSize()
            .background {
                GeometryReader { natural in
                    Color.clear
                        .onAppear { textWidth = natural.size.width }
                        .onChange(of: natural.size.width) { _, width in textWidth = width }
                }
            }
            .hidden()
    }

    /// Walks the sentence left far enough to read its end, and leaves it there
    /// for as long as the pointer stays.
    ///
    /// It used to travel there and back on `repeatForever(autoreverses:)`, and
    /// that was wrong twice over. A repeating animation in SwiftUI outlives the
    /// state change that started it, so the sentence went on sliding long after
    /// the pointer had gone; and once it was no longer hovered it was drawn
    /// truncated again, so what slid back and forth was an ellipsis with
    /// nothing behind it. The end never became readable, which was the whole
    /// point. One pass, held at the end, and no repeating animation to cancel.
    private func walk(_ hovering: Bool) {
        generation += 1
        let mine = generation

        guard overflow > 0, !reduceMotion else {
            isExpanded = false
            offset = 0
            return
        }

        guard hovering else {
            withAnimation(.easeOut(duration: Self.returnDuration)) { offset = 0 }
            // Held at full width until it is home. Flipping this now would
            // re-truncate the sentence mid-slide.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.returnDuration) {
                guard generation == mine else { return }
                isExpanded = false
            }
            return
        }

        isExpanded = true
        withAnimation(.linear(duration: Double(overflow / Self.speed)).delay(Self.leadIn)) {
            offset = -overflow
        }
    }
}
