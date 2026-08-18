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
/// `@unchecked` because the compiler cannot see the discipline: `ramp` is
/// only ever touched on `queue`, which both public methods hop to first.
final class GammaFade: @unchecked Sendable {
    /// Down over about a second rather than stepping (docs/ROADMAP).
    private static let rampDuration: TimeInterval = 1.0
    private static let rampSteps = 24

    private let queue = DispatchQueue(
        label: "com.perfectoweb.belay.gamma-fade", qos: .userInteractive)
    private var ramp: DispatchSourceTimer?

    /// Ramps every active display down to `level` (1.0 untouched, bounded well
    /// above black by `SettingsBounds.nightDimmingLevel`).
    func dim(to level: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.ramp?.cancel()
            let displays = Self.activeDisplays()
            guard !displays.isEmpty else { return }

            var step = 0
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now(),
                repeating: Self.rampDuration / Double(Self.rampSteps))
            timer.setEventHandler { [weak self] in
                step += 1
                let progress = min(1, Double(step) / Double(Self.rampSteps))
                let point = 1 - (1 - level) * progress
                Self.apply(whitePoint: point, to: displays)
                if progress >= 1 { self?.ramp?.cancel() }
            }
            timer.resume()
            self.ramp = timer
        }
    }

    /// Instantly, not over a ramp: a person who came back is waiting.
    ///
    /// `CGDisplayRestoreColorSyncSettings` hands every display back to the
    /// system's own tables — the same restore a process exit performs, so this
    /// path and the crash path cannot disagree.
    func restore() {
        queue.async { [weak self] in
            self?.ramp?.cancel()
            self?.ramp = nil
            CGDisplayRestoreColorSyncSettings()
        }
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
