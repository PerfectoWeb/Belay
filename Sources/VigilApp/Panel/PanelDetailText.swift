import SwiftUI

/// The panel's one-line explanation, with a way out if it ever does not fit.
///
/// Every status sentence is written and measured to fit this on one line in all
/// six languages, and `LocalizationTests` fails if one stops fitting. This is
/// what happens anyway: a sentence too wide is cut with an ellipsis, and resting
/// the pointer on it walks the text along and back so the ending is readable
/// without the panel growing a second line.
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

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isHovering = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var overflow: CGFloat { max(textWidth - boxWidth, 0) }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(contrast == .increased ? .primary : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            // Only while walking. Fixed the rest of the time, the sentence would
            // overflow its box instead of gaining an ellipsis.
            .fixedSize(horizontal: isHovering && overflow > 0, vertical: false)
            .offset(x: offset)
            .frame(height: Self.lineHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .background { measureBox }
            .background(alignment: .leading) { measureText }
            .contentShape(.rect)
            .onHover(perform: walk)
            .help(overflow > 0 ? Text(verbatim: text) : Text(verbatim: ""))
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

    private func walk(_ hovering: Bool) {
        isHovering = hovering
        guard overflow > 0, !reduceMotion else {
            offset = 0
            return
        }
        guard hovering else {
            withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
            return
        }
        // A beat before setting off, so passing the pointer over the row does
        // not start a sentence moving behind the cursor.
        let seconds = Double(overflow / Self.speed)
        withAnimation(
            .linear(duration: seconds).delay(0.4).repeatForever(autoreverses: true)
        ) {
            offset = -overflow
        }
    }
}
