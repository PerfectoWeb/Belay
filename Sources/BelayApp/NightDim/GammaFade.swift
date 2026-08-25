import CoreGraphics
import Foundation

/// The actuator: takes every display's white point down and back.
///
/// `CGSetDisplayTransferByFormula` is the whole trick (docs/ROADMAP, probed
/// 2026-08-18: the main display reports a 1024-entry table and takes a
/// fractional white point cleanly). No private API and no entitlement. The
/// property that makes it safe is the one the invariants care about: gamma
/// belongs to the process that set it, and CoreGraphics restores it when that
/// process exits. A crashed Belay cannot leave a dark screen behind.
///
/// `@unchecked` because the compiler cannot see the discipline: every stored
/// property is only ever touched on `queue`, which both public methods hop to
/// first.
final class GammaFade: @unchecked Sendable {
    /// Down over about a second, back in about a third of one — the cadence
    /// the system's own display fade taught everyone to expect. Both eased,
    /// because a linear ramp reads as a stutter at the ends.
    private static let dimDuration: TimeInterval = 1.0
    private static let restoreDuration: TimeInterval = 0.35
    private static let stepInterval: TimeInterval = 1.0 / 30

    private let queue = DispatchQueue(
        label: "com.perfectoweb.belay.gamma-fade", qos: .userInteractive)
    private var ramp: DispatchSourceTimer?
    /// Where the white point stands now, so a restore that interrupts a dim
    /// starts from the brightness on screen rather than jumping.
    private var current: Double = 1.0

    /// Ramps every active display down to `level` (1.0 untouched, bounded well
    /// above black by `SettingsBounds.nightDimmingLevel`).
    func dim(to level: Double) {
        queue.async { [weak self] in
            self?.animate(to: level, over: Self.dimDuration) { _ in }
        }
    }

    /// Re-applies the current white point immediately, without animating.
    ///
    /// A display reconfiguration — a monitor power-cycling, a resolution change,
    /// a display connected or disconnected — resets the gamma tables, which
    /// would strand the screen bright for the rest of the night while we still
    /// believe it is dimmed. The dimmed tick calls this to put the level back;
    /// it re-queries the active displays, so a newly attached one is covered
    /// too. A no-op when not dimmed, so it costs nothing the rest of the time.
    func reassert() {
        queue.async { [weak self] in
            guard let self, self.current < 1.0, self.ramp == nil else { return }
            Self.apply(whitePoint: self.current, to: Self.activeDisplays())
        }
    }

    /// Back up quickly but smoothly: a person who moved the mouse is waiting,
    /// and a flash-cut reads as a glitch. The final hand-off goes through
    /// `CGDisplayRestoreColorSyncSettings`, the same restore a process exit
    /// performs, so this path and the crash path cannot disagree.
    func restore() {
        queue.async { [weak self] in
            self?.animate(to: 1.0, over: Self.restoreDuration) { finished in
                if finished { CGDisplayRestoreColorSyncSettings() }
            }
        }
    }

    /// Queue-confined. Cancels any ramp in flight and starts from `current`,
    /// so dim-into-restore hands over mid-flight instead of snapping.
    private func animate(
        to target: Double, over duration: TimeInterval, done: @escaping (Bool) -> Void
    ) {
        ramp?.cancel()
        let displays = Self.activeDisplays()
        guard !displays.isEmpty else {
            done(false)
            return
        }
        let from = current
        let steps = max(1, Int(duration / Self.stepInterval))
        var step = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: duration / Double(steps))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            step += 1
            let linear = min(1, Double(step) / Double(steps))
            // Smoothstep: eases both ends, which is what the system fade does.
            let progress = linear * linear * (3 - 2 * linear)
            self.current = from + (target - from) * progress
            Self.apply(whitePoint: self.current, to: displays)
            if linear >= 1 {
                self.ramp?.cancel()
                self.ramp = nil
                done(true)
            }
        }
        timer.resume()
        ramp = timer
    }

    /// Every display, not only the main one (docs/ROADMAP).
    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private static func apply(whitePoint: Double, to displays: [CGDirectDisplayID]) {
        let ceiling = CGGammaValue(whitePoint)
        for display in displays {
            CGSetDisplayTransferByFormula(
                display, 0, ceiling, 1, 0, ceiling, 1, 0, ceiling, 1)
        }
    }
}
