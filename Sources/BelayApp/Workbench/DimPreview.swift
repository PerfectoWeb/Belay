import AppKit
import BelayCore
import BelaySettings

/// The dimmed screen on demand, for the workbench: the ramp at the user's
/// level and the countdown at 00:59:59, held until switched off. Exists so
/// the night screen can be looked at after any change without waiting for
/// the night, the idle delay and a timer to line up.
///
/// Lets go of everything on its own when the window that owns it closes —
/// a workbench that leaves the display dark is a bug report.
@MainActor
final class DimPreview {
    private let fade = GammaFade()
    private let clock = DimClock()
    /// Its own store: it only reads the level, and the defaults are shared.
    private let settings = SettingsStore()
    private(set) var isOn = false

    func toggle() {
        if isOn { stop() } else { start() }
    }

    private func start() {
        isOn = true
        fade.dim(to: settings.nightDimmingLevel)
        clock.sync(
            dimmed: true, enabled: true,
            timer: AlwaysOnTimer(duration: 3600, deadline: Date() + 3600))
    }

    func stop() {
        guard isOn else { return }
        isOn = false
        clock.hide()
        fade.restore()
    }
}
