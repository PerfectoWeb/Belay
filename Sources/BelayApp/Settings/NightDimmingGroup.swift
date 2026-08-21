import BelaySettings
import SwiftUI

/// The night-dimming rows inside the "While holding" group: the switch, the
/// window and how far down to go. Sits directly under "Also keep the display
/// awake" because it only ever acts while that hold is the reason the screen
/// is lit — with the display allowed to sleep there is nothing to dim.
struct NightDimmingGroup: View {
    @Bindable var settings: SettingsStore

    /// Says when the dim actually happens, with the live number. The dimmer
    /// keys off the system's own display-off delay — ten minutes on power by
    /// default — and a sentence that only said "when you step away" sent the
    /// first tester away for two minutes to wait for nothing. Four shapes,
    /// whole sentences each, never a fragment interpolated into another.
    static var explanation: LocalizedStringKey {
        let onAC = DisplaySleepDelay.isOnACNow
        guard DisplaySleepDelay.isKnown else {
            return """
                When you step away at night and macOS would have turned the display off, \
                Belay dims it to this level instead. It brightens again when you return.
                """
        }
        guard let delay = DisplaySleepDelay.current(onAC: onAC) else {
            return """
                Your Mac is set never to turn the display off, so there is no moment for \
                Belay to dim it. Choose a display-off time in System Settings first.
                """
        }
        let minutes = Int((delay / 60).rounded())
        return onAC
            ? """
            When you step away at night, Belay dims the display to this level instead of \
            letting macOS turn it off, which happens after \(minutes) min on power right now. \
            It brightens again when you return.
            """
            : """
            When you step away at night, Belay dims the display to this level instead of \
            letting macOS turn it off, which happens after \(minutes) min on battery right now. \
            It brightens again when you return.
            """
    }

    var body: some View {
        GroupedCheckbox(
            title: "Dim the display at night",
            explanation: Self.explanation,
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
                title: "Blur the screen while dimmed",
                explanation: """
                    Whatever was on screen becomes shapes rather than words, so a glance \
                    from across the room shows nothing.
                    """,
                isOn: $settings.nightDimmingBlurs
            )

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
