import AppKit
import SwiftUI

/// The picture Vigil hands to a share sheet: 1200x630, dark, always identical.
///
/// Every colour here is a literal. `.primary` and `.secondary` resolve against
/// whatever appearance the renderer inherits, and an offscreen `ImageRenderer`
/// inherits nobody's window — a card built in Light mode came out black text on
/// a black plate. A fixed dark plate also happens to be the safer bet socially:
/// it sits well in Telegram, Slack and Messages threads, which are dark far more
/// often than not.
///
/// The lockup is `VigilWordmark`, the same one About shows, rather than a glyph
/// and a `Text` set next to each other here. This is the one image of Vigil most
/// people will ever see, and two hand-built versions of a logo is how they end
/// up disagreeing.
struct ShareCard: View {
    let content: ShareCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 18)
            headline
            Spacer(minLength: 22)
            figures
            Spacer(minLength: 26)
            chart
        }
        .padding(.horizontal, 72)
        .padding(.top, 50)
        .padding(.bottom, 46)
        .frame(width: ShareCardRenderer.size.width, height: ShareCardRenderer.size.height)
        .background(plate)
    }

    private var plate: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Ink.lift, Ink.base],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            // A single source behind the headline, so the number reads as lit
            // rather than pasted onto a flat rectangle. Kept faint: any stronger
            // and the whole plate turns blue at chat-thumbnail size.
            RadialGradient(
                colors: [Ink.accent.opacity(0.16), Ink.accent.opacity(0)],
                center: UnitPoint(x: 0.10, y: 0.34), startRadius: 0, endRadius: 540)
            Rectangle()
                .fill(Ink.accent)
                .frame(height: 6)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            VigilWordmark(size: 44, word: Ink.text, mark: Ink.accent)
            Spacer(minLength: 24)
            // The mark before the address, at the height of the text: a bare
            // URL in a corner reads as a footnote, and this one is the only
            // instruction on the card.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image("logo-github")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 19, height: 19)
                    .alignmentGuide(.firstTextBaseline) { $0.height - 4 }
                Text(content.link)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(Ink.text.opacity(0.52))
        }
    }

    /// Number and sentence on one line rather than stacked. Under the number the
    /// sentence read as a caption to a statistic; beside it, on the number's own
    /// baseline, the two read as one claim, which is what it is.
    private var headline: some View {
        HStack(alignment: .lastTextBaseline, spacing: 26) {
            Text(content.headline)
                .font(.system(size: 112, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Ink.accent)
                .fixedSize()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(captionLines, id: \.self) { line in
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 27, weight: .regular))
            .foregroundStyle(Ink.text.opacity(0.80))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Broken at the sentence, not wherever the width happens to run out. The
    /// two sentences are the claim and its evidence, and a line that ends in the
    /// middle of the first reads as text that did not fit.
    private var captionLines: [String] {
        guard let stop = content.caption.range(of: ". ") else { return [content.caption] }
        return [
            String(content.caption[..<stop.lowerBound]) + ".",
            String(content.caption[stop.upperBound...])
        ]
    }

    /// Four plates rather than four columns divided by a rule. The rule was
    /// doing the separating and the grouping at once and did neither well; a
    /// plate each says "these are four of the same thing" without a line.
    private var figures: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(content.figures, id: \.label) { figure in
                VStack(alignment: .leading, spacing: 4) {
                    Text(figure.value)
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Ink.text)
                    Text(figure.label.uppercased())
                        .font(.system(size: 13, weight: .regular))
                        .tracking(1.7)
                        .foregroundStyle(Ink.text.opacity(0.50))
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                // Not equal numbers: the number's line box carries empty space
                // above the digits that the label's does not carry below its
                // baseline, so equal padding lands optically top-heavy.
                .padding(.top, 12)
                .padding(.bottom, 17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(glass)
            }
        }
    }

    /// Lit from the top, like a pane of something sitting on the plate rather
    /// than a grey rectangle painted on it.
    private var glass: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Ink.text.opacity(0.065), Ink.text.opacity(0.018)],
                    startPoint: .top, endPoint: .bottom)
            )
            // A light source above and to the left of the card, caught by each
            // plate. Faint on purpose: at chat-thumbnail size anything stronger
            // turns four plates into four smudges.
            .overlay(
                RadialGradient(
                    colors: [Ink.accent.opacity(0.16), Ink.accent.opacity(0)],
                    center: UnitPoint(x: 0.12, y: -0.1), startRadius: 0, endRadius: 190)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Ink.text.opacity(0.20), Ink.text.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The label sits under the bars, on the far side of the axis they stand on:
    /// above them it was a heading for a chart that needs no heading, and it
    /// pushed the whole block down for no reason.
    private var chart: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardBars(days: content.days)
                .frame(height: 74)
            Rectangle()
                .fill(Ink.text.opacity(0.14))
                .frame(height: 1)
                .padding(.top, 8)
            Text("LAST 14 DAYS")
                .font(.system(size: 12, weight: .regular))
                .tracking(1.9)
                .foregroundStyle(Ink.text.opacity(0.36))
                .padding(.top, 14)
        }
    }
}

/// One bar per day, the solid part being the time nobody was watching. Days with
/// no runs keep their slot as a stub, so the shape of a fortnight stays true.
private struct CardBars: View {
    let days: [UsageStatistics.Day]

    var body: some View {
        let peak = max(days.map(\.heldSeconds).max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 11) {
            ForEach(days) { day in
                GeometryReader { geometry in
                    let full = geometry.size.height
                    ZStack(alignment: .bottom) {
                        bar(height: max(full * day.heldSeconds / peak, 3), opacity: 0.26)
                        bar(height: full * day.awaySeconds / peak, opacity: 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func bar(height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Ink.accent.opacity(opacity))
            .frame(height: max(height, 0))
    }
}

/// Fixed sRGB values, never semantic ones. See the note on `ShareCard`.
private enum Ink {
    static let base = Color(red: 0.035, green: 0.043, blue: 0.062)
    static let lift = Color(red: 0.078, green: 0.098, blue: 0.145)
    /// The brand accent, unmodified. It is darker against this plate than the
    /// amber it replaced, which is what the glow above is for — a second, paler
    /// blue would be a second brand colour.
    static let accent = Color(red: 0.137, green: 0.475, blue: 1.0)
    static let text = Color.white
}
