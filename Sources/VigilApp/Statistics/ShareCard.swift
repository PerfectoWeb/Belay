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
/// The lockup is the file from `Resources/Brand`, not a glyph and a `Text` set
/// next to each other. Rebuilding it here is how the card and the brand drift
/// apart, and this is the one image of Vigil most people will ever see.
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
            VigilWordmark(size: 38, word: Ink.text, mark: Ink.accent)
            Spacer(minLength: 24)
            Text(content.link)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
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
            Text(content.caption)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(Ink.text.opacity(0.80))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Ink.text.opacity(0.46))
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
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
                    colors: [Ink.text.opacity(0.10), Ink.text.opacity(0.035)],
                    startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Ink.text.opacity(0.11), lineWidth: 1)
            )
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
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Ink.text.opacity(0.36))
                .padding(.top, 9)
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
