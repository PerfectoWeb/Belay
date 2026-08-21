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
struct PanelTimerRow: View {
    let state: AppState

    /// What the menu offers, mirrored from `SettingsPresets.maxContinuousAwake`
    /// so the two pop-ups speak the same vocabulary, plus the quarter hour a
    /// coffee-timer is actually asked for.
    static let durations: [TimeInterval] = [900, 1800, 3600, 7200, 14400, 28800, 43200]

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
        } else if state.mode == .alwaysOn {
            chip
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

            Menu {
                // A label-less Picker, spelled without the string initialiser:
                // a literal "" would register as a catalogue key and trip the
                // completeness check.
                Picker(selection: selection) {
                    Text("Until turned off").tag(TimeInterval?.none)
                    ForEach(Self.durations, id: \.self) { duration in
                        Text(DurationChoice.label(duration)).tag(TimeInterval?.some(duration))
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                if let timer = state.snapshot.timer {
                    // `Text(timerInterval:)` ticks by itself; no timer of ours
                    // runs while the panel is closed.
                    Text(
                        timerInterval: min(Date.now, timer.deadline)...timer.deadline,
                        countsDown: true
                    )
                    .monospacedDigit()
                } else {
                    Text("Until turned off")
                }
            }
            .font(.system(size: 11))
            .menuStyle(.borderlessButton)
            .fixedSize()
            // Pinned to the text's own line height: the menu control brings
            // a little chrome of its own, just enough to make this row taller
            // than the pause row it swaps with. 14 is what an 11pt text line
            // actually measures in the notice row.
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
