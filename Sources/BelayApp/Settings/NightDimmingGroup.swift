import BelaySettings
import SwiftUI

/// The night-dimming rows inside the "While holding" group: the switch, the
/// window and how far down to go. Sits directly under "Also keep the display
/// awake" because it only ever acts while that hold is the reason the screen
/// is lit — with the display allowed to sleep there is nothing to dim.
struct NightDimmingGroup: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        GroupedCheckbox(
            title: "Dim the display at night",
            explanation: """
                When you step away at night, Belay dims the display to this \
                level. It brightens again when you return.
                """,
            isOn: $settings.nightDimming
        )
        .disabled(!settings.keepDisplayAwake)

        if settings.nightDimming && settings.keepDisplayAwake {
            // The dash is verbatim, so the catalogue never sees it. The fields
            // are `ClockField`, not SwiftUI's `DatePicker`, for one reason
            // that took three failed widenings to learn: only the AppKit
            // control underneath can actually grow its bezel.
            HStack(spacing: 8) {
                ClockField(minutes: $settings.nightDimmingStart)
                    .accessibilityLabel("Dim from")
                Text(verbatim: "–").foregroundStyle(.secondary)
                ClockField(minutes: $settings.nightDimmingEnd)
                    .accessibilityLabel("Dim until")

                // No step: continuous under the thumb, and stepped sliders
                // draw their ticks — at half-percent steps a hundred of them
                // fused into a stray line under the track. The label rounds
                // to a whole percent so it cannot dither.
                Slider(value: $settings.nightDimmingLevel, in: 0.10...0.60)
                    .controlSize(.small)
                    .frame(width: 110)
                    .accessibilityLabel("Dimmed brightness")
                Text(
                    verbatim: settings.nightDimmingLevel.formatted(
                        .percent.precision(.fractionLength(0)))
                )
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            }
            .font(.callout)

            GroupedCheckbox(
                title: "Show the timer on the dimmed screen",
                explanation: """
                    While an Always on timer runs, the remaining time glows \
                    quietly on the dark display, the way a bedside clock would.
                    """,
                isOn: $settings.nightDimmingShowsTimer
            )
        }
    }
}
