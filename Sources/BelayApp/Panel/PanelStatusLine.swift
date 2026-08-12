import AppKit
import SwiftUI

/// The top block of the panel: one glyph, one headline, one plain sentence.
struct PanelStatusLine: View {
    let status: PanelStatus

    /// How much width the sentence actually gets: the panel, less its padding,
    /// the 18 pt mark and the 10 pt gap. Every status sentence is meant to fit
    /// this on one line in every language, and `LocalizationTests` checks it.
    static let detailWidth: CGFloat = PanelView.width - 14 * 2 - 18 - 10
    static let detailFont = NSFont.systemFont(ofSize: 11)

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Centred, not baseline-aligned: the text beside it is two lines, and a
        // mark sitting on the first baseline reads as having slipped upward.
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: BelayGlyph.image(status.look, size: 18))
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(glyphStyle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // The mode control shares the headline's line, not the block's
                // trailing edge: taking a column off the whole block left the
                // sentence underneath wrapping to three lines for no reason.
                Text(status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                PanelDetailText(text: String(localized: status.detail))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// The accent tint reads as "on" without a colour literal, so tinted and
    /// reduced-transparency menu bars stay correct for free (docs/05).
    private var glyphStyle: AnyShapeStyle {
        guard !status.isInterrupted else { return AnyShapeStyle(.primary) }
        return status.isHolding
            ? AnyShapeStyle(Color(nsColor: .controlAccentColor))
            : AnyShapeStyle(.secondary)
    }

}

extension PanelStatus {
    /// `LocalizedStringResource`, not `LocalizedStringKey`: only the former lets
    /// a test read back the key it will look up, and the test that matters here
    /// measures every one of these sentences in every language.
    var title: LocalizedStringResource {
        switch self {
        case .off, .armed: return "Your Mac will sleep normally"
        case .alwaysOn, .working, .coolingDown: return "Keeping your Mac awake"
        case .awaitingUser: return "An agent is waiting for you"
        case .batteryLow: return "Belay let your Mac sleep"
        case .maxDurationReached: return "Belay let your Mac sleep"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .off:
            return "Belay is switched off, so it will not hold sleep at all."
        case .armed:
            return "Belay is watching. Nothing is running right now."
        case .alwaysOn:
            return "You asked Belay to stay on until you switch it off."
        case .working:
            return "An agent is working, so sleep is on hold."
        case .awaitingUser:
            return "It needs an answer from you before it can carry on."
        case .coolingDown:
            return "Holding on a little longer in case more work arrives."
        case .batteryLow(let percent):
            return "Your battery is down to \(percent)%, so Belay stopped holding to save power."
        case .maxDurationReached:
            return "Belay reached the longest stretch you allow it to hold, so it stopped."
        }
    }

    var symbolName: String {
        switch self {
        case .off: return "moon.slash"
        case .armed: return "moon"
        case .alwaysOn, .working, .coolingDown: return "moon.fill"
        case .awaitingUser: return "moon.stars.fill"
        case .batteryLow: return "battery.25"
        case .maxDurationReached: return "clock.badge.exclamationmark"
        }
    }
}
