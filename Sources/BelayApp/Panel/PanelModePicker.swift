import BelayCore
import SwiftUI

/// Auto / Always on / Off — all three visible, all three one click away.
///
/// Three attempts got here. A menu hid the answer behind a click; a switch with
/// a pin made the third state something you had to work out. With three modes,
/// three targets is right — what was wrong with the original was never the
/// shape, it was that a stock `NSSegmentedControl` looks like a form field
/// bolted into a panel rather than like part of the app.
///
/// So it is drawn: one track, three tabs, and a selection pill that slides
/// between them. The slide is the whole point — it says the modes are three
/// positions of one control rather than three separate buttons that happen to
/// sit together, and it is the difference between reading as a choice and
/// reading as a toolbar. Earlier attempts are kept verbatim in `docs/design/`.
///
/// Animates nothing that can change the panel's height.
struct PanelModePicker: View {
    let state: AppState

    @Namespace private var pill
    /// Which unselected tab the pointer is over. One piece of state for three
    /// tabs, so two can never be lit at once.
    @State private var hovered: AwakeMode?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let corner: CGFloat = 7

    /// What one tab has to draw a label in, and the font it draws with. Held
    /// here rather than inline so a test can measure every translation against
    /// the same numbers the view lays out with: Spanish already overflowed this
    /// by four points, and nothing in the build said so.
    static let symbolSize: CGFloat = 10
    static let titleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let labelWidth: CGFloat = {
        // The picker's own 2pt padding, then 2pt between each pair of tabs,
        // then each tab's horizontal padding, its glyph and the gap after it.
        let track = PanelView.width - 4
        let tab = (track - 4) / 3
        return tab - 16 - symbolSize - 4
    }()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AwakeMode.allCases, id: \.self) { mode in
                tab(mode)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Self.corner + 2)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Awake mode")
    }

    private func tab(_ mode: AwakeMode) -> some View {
        let isSelected = state.mode == mode
        return Button {
            select(mode)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                Text(mode.pickerTitle)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            // Three steps, not two: the chosen one is white on its pill, the one
            // under the pointer comes up to full strength, and the rest stay
            // secondary. Without the middle step the two unchosen tabs look like
            // labels rather than like somewhere to click.
            .foregroundStyle(tint(mode, isSelected: isSelected))
            // Keyed to the hover alone, so it cannot reach the pill: the pill
            // travels on the spring `select` sets, and one curve driving both
            // would make the colour lag the cursor by the pill's length.
            .animation(.easeInOut(duration: 0.18), value: hovered)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                // One pill, moved — not three pills faded in and out. The
                // geometry match is what makes it read as a single control.
                if isSelected {
                    RoundedRectangle(cornerRadius: Self.corner)
                        .fill(mode.pillColor)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? mode : (hovered == mode ? nil : hovered) }
        .accessibilityLabel(mode.pickerTitle)
        .accessibilityValue(Text(mode.pickerExplanation))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// One colour at two opacities, never `.secondary` and `.primary`. The two
    /// hierarchical styles are different types, so SwiftUI cannot interpolate
    /// between them: it swapped the view instead, which read as a flash to dim
    /// followed by a slow fade up. An opacity is a number, and numbers animate.
    private func tint(_ mode: AwakeMode, isSelected: Bool) -> Color {
        if isSelected { return .white }
        return .primary.opacity(hovered == mode ? 1 : 0.6)
    }

    /// Named so the tests can exercise the rule without synthesising a click on
    /// a hosted SwiftUI view, whose accessibility tree comes back empty.
    func selectForTesting(_ mode: AwakeMode) { select(mode) }

    private func select(_ mode: AwakeMode) {
        guard mode != state.mode else { return }
        // Only the pill animates. The row's height never changes, so nothing
        // above or below it can move — see `PanelController.grow(to:)` for why
        // that matters in a popover.
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
            state.mode = mode
        }
        state.onModeChange(mode)
        // Each mode has its own note, so the three are told apart without
        // looking; the haptic is what a Force Touch trackpad gives a control
        // moving between discrete positions.
        Feedback.play(Feedback.sound(for: mode))
        Feedback.levelChanged()
    }
}

extension AwakeMode {
    var pickerTitle: LocalizedStringKey {
        switch self {
        case .auto: return "Auto"
        case .alwaysOn: return "Always on"
        case .off: return "Off"
        }
    }

    /// Read by VoiceOver and used as the tooltip: the three names do not explain
    /// themselves, and a panel this small has no room to explain them in place.
    var pickerExplanation: LocalizedStringKey {
        switch self {
        case .auto: return "Awake only while an agent is working."
        case .alwaysOn: return "Awake until you switch it off."
        case .off: return "Never hold sleep."
        }
    }

    /// A colour each, because the three modes mean different things and the
    /// panel is glanced at, not read. Blue is the one that decides for you,
    /// amber is the one that holds no matter what, grey is the one that does
    /// nothing — the same reading the words give, arriving sooner.
    var pillColor: Color {
        switch self {
        case .auto: return Color(nsColor: .controlAccentColor)
        case .alwaysOn: return Color(red: 0.95, green: 0.62, blue: 0.16)
        case .off: return Color(nsColor: .systemGray)
        }
    }

    var symbolName: String {
        switch self {
        case .auto: return "wand.and.sparkles"
        case .alwaysOn: return "sun.max.fill"
        case .off: return "moon"
        }
    }
}
