import BelayCore
import SwiftUI

/// The row under the mode picker that bounds Always on, and the way out of the
/// pause once a bound has fired.
///
/// The pattern is Control Center's Focus: the mode is the big control, the
/// duration a quiet disclosure beside it. Visible, so nobody has to discover
/// that a button hides extra states; one menu deep, so any length is two
/// clicks. Cycling the durations through the segment itself was considered
/// and rejected — it makes a click on the active segment change behaviour,
/// and a stray click that silently turns "always" into "15 minutes" is the
/// kind of surprise this app exists to prevent.
///
/// Animates nothing that can change the panel's height. The row's slot
/// appears and goes with the mode, instantly; what animates is the row's
/// *content* inside that slot — it fades and slides in from the left on the
/// way in, and fades out before the slot is given up on the way out.
struct PanelTimerRow: View {
    let state: AppState

    /// Whether the chip is drawn, one step behind `state.mode`: true a beat
    /// after Always on arrives, false a beat before the slot goes.
    @State private var shown = false
    /// Keeps the slot while the chip fades out.
    @State private var leaving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let pause {
            // The battery guard is deliberately absent: it clears on its own
            // terms (power arrives), so there is nothing honest for a button
            // here to do.
            PanelNoticeRow(
                symbolName: "pause.circle",
                message: pause,
                actionTitle: "Hold again",
                action: { state.onHoldAgain() }
            )
        } else if state.mode == .alwaysOn || leaving {
            chip
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : -10)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: shown)
                .onAppear { shown = true }
                .onChange(of: state.mode) { _, mode in
                    guard mode != .alwaysOn else {
                        shown = true
                        return
                    }
                    // Out: fade first, then let the slot go. The height
                    // change happens after the content has gone, so nothing
                    // visible is mid-motion when the layout moves.
                    shown = false
                    leaving = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.2)) {
                        leaving = false
                    }
                }
        }
    }

    /// The two pauses a click may honestly end.
    private var pause: String? {
        guard case .suspended(let reason) = state.snapshot.state else { return nil }
        switch reason {
        case .timerEnded: return String(localized: "The timer ran out.")
        case .maxDurationReached: return String(localized: "Paused at your time limit.")
        case .batteryLow: return nil
        }
    }

    /// Laid out to `PanelNoticeRow`'s exact metrics, so the slot keeps one
    /// height whether it shows the menu or the pause and nothing below it
    /// moves when one becomes the other.
    private var chip: some View {
        // Centre-aligned, not baseline: a Menu's label carries its own chrome
        // and baseline-aligning it against the icon spills two extra points
        // into the row, which is exactly the jump the tests forbid.
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            // An AppKit menu behind a SwiftUI face: see `DurationMenu` for
            // why — the Shift-extended list has to change while open.
            DurationMenuButton(current: state.snapshot.timer?.duration, choose: state.onTimerChange) {
                HStack(spacing: 4) {
                    if let timer = state.snapshot.timer {
                        // Redraws once a second only while the panel is open;
                        // the popover's view is torn down on close.
                        Countdown(deadline: timer.deadline)
                    } else {
                        Text("Until turned off")
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }
            .fixedSize()
            .frame(height: 14)
            .accessibilityLabel("How long to keep the Mac awake")

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }

    private var selection: Binding<TimeInterval?> {
        Binding(
            get: { state.snapshot.timer?.duration },
            set: { state.onTimerChange($0) }
        )
    }
}
