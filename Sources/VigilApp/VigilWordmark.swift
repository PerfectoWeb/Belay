import SwiftUI

/// The horizontal lockup: the word, then the mark.
///
/// Drawn here rather than loaded from `Resources/Brand`, and the reason is the
/// opposite of the reason those files exist. They are outlined because a logo
/// that falls back to Times on somebody else's machine is not a logo; inside the
/// app the font is guaranteed, and drawing it means the mark is the same
/// `VigilGlyph` artwork the menu bar uses rather than a second copy that can go
/// stale.
///
/// The proportions are the ones in `docs/BRAND.md` and in
/// `scripts/make-wordmark.swift`, expressed against the word's point size so the
/// lockup scales as one thing. The mark trailing the word is deliberate and
/// explained there: ahead of it, the lockup reads as "icon with a caption",
/// which is what the user already sees in the menu bar all day.
struct VigilWordmark: View {
    /// Point size of the word. Everything else follows from it.
    var size: CGFloat = 36
    var word: Color = .white
    var mark: Color = Color(red: 0.137, green: 0.475, blue: 1.0)

    /// Against a 36 pt word: mark 26, gap 7. Both to the ascender, which is why
    /// the mark sits on the baseline rather than being centred on the word.
    private static let markRatio: CGFloat = 26.0 / 36
    private static let gapRatio: CGFloat = 7.0 / 36

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * Self.gapRatio) {
            Text(verbatim: "vigil")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(word)
            Image(nsImage: VigilGlyph.image(.alwaysOn, size: (size * Self.markRatio).rounded()))
                .renderingMode(.template)
                .foregroundStyle(mark)
                // Its bottom edge on the word's baseline, so the mark occupies
                // exactly the ascender. Alignment by frame instead would follow
                // the line box, which sits above the letters by a different
                // amount at every size.
                .alignmentGuide(.firstTextBaseline) { $0.height }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: Branding.appName))
    }
}
