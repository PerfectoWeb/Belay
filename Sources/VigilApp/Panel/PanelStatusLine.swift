import SwiftUI

/// The top block of the panel: one glyph, one headline, one plain sentence.
struct PanelStatusLine: View {
    let status: PanelStatus

    /// Two lines of the 11 pt detail font, spacing included. Measured, and the
    /// test in `PanelHeightStabilityTests` fails if it stops being right.
    private static let detailHeight: CGFloat = 30

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Centred, not baseline-aligned: the text beside it is two lines, and a
        // mark sitting on the first baseline reads as having slipped upward.
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: VigilGlyph.image(status.look, size: 18))
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
                Text(status.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(contrast == .increased ? .primary : .secondary)
                    // Always two lines' worth of space, whether or not the
                    // sentence needs both. Switching modes rewrites this text,
                    // and a block that is one line in Always on and two in Off
                    // makes the whole panel jump as you click between them.
                    // A fixed two-line box, not `reservesSpace`. Reserved space
                    // does not carry the line spacing a real wrap does, so a
                    // one-line sentence measured 2 pt shorter than a wrapped one
                    // and the panel still moved between modes — by less, which
                    // is worse, because it looks like a rendering fault rather
                    // than a layout.
                    .lineLimit(2)
                    .frame(height: Self.detailHeight, alignment: .topLeading)
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
    var title: LocalizedStringKey {
        switch self {
        case .off, .armed: return "Your Mac will sleep normally"
        case .alwaysOn, .working, .coolingDown: return "Keeping your Mac awake"
        case .awaitingUser: return "An agent is waiting for you"
        case .batteryLow: return "Vigil let your Mac sleep"
        case .maxDurationReached: return "Vigil let your Mac sleep"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .off:
            return "Vigil is switched off, so it will not hold sleep at all."
        case .armed:
            return "Vigil is watching. Nothing is running right now."
        case .alwaysOn:
            return "You asked Vigil to stay on until you switch it off."
        case .working:
            return "An agent is working, so sleep is on hold."
        case .awaitingUser:
            return "It needs an answer from you before it can carry on."
        case .coolingDown:
            return "Holding on a little longer in case more work arrives."
        case .batteryLow(let percent):
            return "Your battery is down to \(percent)%, so Vigil stopped holding to save power."
        case .maxDurationReached:
            return "Vigil reached the longest stretch you allow it to hold, so it stopped."
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
