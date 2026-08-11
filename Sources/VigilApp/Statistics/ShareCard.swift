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
struct ShareCard: View {
    let content: ShareCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 20)
            headline
            Spacer(minLength: 20)
            Rectangle()
                .fill(Ink.text.opacity(0.12))
                .frame(height: 1)
            Spacer(minLength: 20)
            figures
            Spacer(minLength: 24)
            chart
        }
        .padding(.horizontal, 72)
        .padding(.top, 54)
        .padding(.bottom, 50)
        .frame(width: ShareCardRenderer.size.width, height: ShareCardRenderer.size.height)
        .background(plate)
    }

    private var plate: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Ink.lift, Ink.base],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            // A single warm source behind the headline, so the number reads as
            // lit rather than pasted onto a flat rectangle. Kept faint: any
            // stronger and the whole plate turns brown at chat-thumbnail size.
            RadialGradient(
                colors: [Ink.accent.opacity(0.13), Ink.accent.opacity(0)],
                center: UnitPoint(x: 0.10, y: 0.38), startRadius: 0, endRadius: 520)
            Rectangle()
                .fill(Ink.accent)
                .frame(height: 6)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Image(nsImage: VigilGlyph.image(.alwaysOn, size: 40))
                .renderingMode(.template)
                .foregroundStyle(Ink.accent)
                .alignmentGuide(.firstTextBaseline) { $0.height - 8 }
            Text(Branding.appName)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.text)
                .padding(.leading, 12)
            Spacer(minLength: 24)
            Text(content.link)
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(Ink.text.opacity(0.52))
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content.headline)
                .font(.system(size: 116, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Ink.accent)
            Text(content.caption)
                .font(.system(size: 25, weight: .regular))
                .foregroundStyle(Ink.text.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 840, alignment: .leading)
        }
    }

    private var figures: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(content.figures, id: \.label) { figure in
                VStack(alignment: .leading, spacing: 5) {
                    Text(figure.value)
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Ink.text)
                    Text(figure.label.uppercased())
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(Ink.text.opacity(0.44))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LAST 14 DAYS")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(Ink.text.opacity(0.36))
            CardBars(days: content.days)
                .frame(height: 76)
            Rectangle()
                .fill(Ink.text.opacity(0.12))
                .frame(height: 1)
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
                        bar(height: max(full * day.heldSeconds / peak, 3), opacity: 0.24)
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
    static let base = Color(red: 0.039, green: 0.047, blue: 0.063)
    static let lift = Color(red: 0.090, green: 0.106, blue: 0.141)
    /// The one accent. Warm, because the app is about a machine staying awake.
    static let accent = Color(red: 1.0, green: 0.706, blue: 0.243)
    static let text = Color.white
}
